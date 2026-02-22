# Setup Application Load Balancer for DNS

## Step 1: Get VPC and Subnet Information
```powershell
# Get VPC ID
$VPC_ID = aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text --region us-east-1

# Get multiple subnets (ALB needs at least 2 in different AZs)
$SUBNETS = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0:2].SubnetId' --output text --region us-east-1
$SUBNET1 = ($SUBNETS -split '\s+')[0]
$SUBNET2 = ($SUBNETS -split '\s+')[1]
```

## Step 2: Create Security Group for ALB
```powershell
$ALB_SG_ID = aws ec2 create-security-group `
  --group-name djangotutorial-alb-sg `
  --description "Django ALB Security Group" `
  --vpc-id $VPC_ID `
  --region us-east-1 `
  --query 'GroupId' `
  --output text

# Allow HTTP (port 80)
aws ec2 authorize-security-group-ingress `
  --group-id $ALB_SG_ID `
  --protocol tcp `
  --port 80 `
  --cidr 0.0.0.0/0 `
  --region us-east-1

# Allow HTTPS (port 443) if you have SSL certificate
aws ec2 authorize-security-group-ingress `
  --group-id $ALB_SG_ID `
  --protocol tcp `
  --port 443 `
  --cidr 0.0.0.0/0 `
  --region us-east-1
```

## Step 3: Update ECS Service Security Group
```powershell
# Get the current ECS security group ID
$ECS_SG_ID = aws ec2 describe-security-groups --filters "Name=group-name,Values=djangotutorial-sg" --query 'SecurityGroups[0].GroupId' --output text --region us-east-1

# Allow traffic from ALB to ECS on port 8000
aws ec2 authorize-security-group-ingress `
  --group-id $ECS_SG_ID `
  --protocol tcp `
  --port 8000 `
  --source-group $ALB_SG_ID `
  --region us-east-1

# Remove public access to port 8000 (optional, for better security)
# aws ec2 revoke-security-group-ingress --group-id $ECS_SG_ID --protocol tcp --port 8000 --cidr 0.0.0.0/0 --region us-east-1
```

## Step 4: Create Target Group
```powershell
$TG_ARN = aws elbv2 create-target-group `
  --name djangotutorial-tg `
  --protocol HTTP `
  --port 8000 `
  --vpc-id $VPC_ID `
  --target-type ip `
  --health-check-path / `
  --health-check-interval-seconds 30 `
  --health-check-timeout-seconds 5 `
  --healthy-threshold-count 2 `
  --unhealthy-threshold-count 3 `
  --region us-east-1 `
  --query 'TargetGroups[0].TargetGroupArn' `
  --output text

echo "Target Group ARN: $TG_ARN"
```

## Step 5: Create Application Load Balancer
```powershell
$ALB_ARN = aws elbv2 create-load-balancer `
  --name djangotutorial-alb `
  --subnets $SUBNET1 $SUBNET2 `
  --security-groups $ALB_SG_ID `
  --scheme internet-facing `
  --type application `
  --region us-east-1 `
  --query 'LoadBalancers[0].LoadBalancerArn' `
  --output text

# Get ALB DNS Name (this is what you'll use for DNS)
$ALB_DNS = aws elbv2 describe-load-balancers `
  --load-balancer-arns $ALB_ARN `
  --region us-east-1 `
  --query 'LoadBalancers[0].DNSName' `
  --output text

echo "🌐 ALB DNS Name: $ALB_DNS"
```

## Step 6: Create Listener (HTTP)
```powershell
aws elbv2 create-listener `
  --load-balancer-arn $ALB_ARN `
  --protocol HTTP `
  --port 80 `
  --default-actions Type=forward,TargetGroupArn=$TG_ARN `
  --region us-east-1
```

## Step 7: Update ECS Service to use ALB
```powershell
aws ecs update-service `
  --cluster djangotutorial-cluster `
  --service djangotutorial-service `
  --load-balancers targetGroupArn=$TG_ARN,containerName=djangotutorial,containerPort=8000 `
  --health-check-grace-period-seconds 60 `
  --region us-east-1 `
  --force-new-deployment
```

## Step 8: Add DNS Record

Once the ALB is created, you'll get a DNS name like:
`djangotutorial-alb-1234567890.us-east-1.elb.amazonaws.com`

### Option A: Using Route 53
```powershell
# Create/Update A record with Alias to ALB
aws route53 change-resource-record-sets `
  --hosted-zone-id YOUR_HOSTED_ZONE_ID `
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "yourdomain.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "'$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text)'",
          "DNSName": "'$ALB_DNS'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

### Option B: Using External DNS Provider
Create a CNAME record:
- **Type**: CNAME
- **Name**: www.yourdomain.com (or @ for root domain with A record)
- **Value**: `djangotutorial-alb-1234567890.us-east-1.elb.amazonaws.com`
- **TTL**: 300

### Don't forget to update Django settings!
```powershell
# Update ALLOWED_HOSTS in settings or via environment variable
aws ecs update-service `
  --cluster djangotutorial-cluster `
  --service djangotutorial-service `
  --force-new-deployment `
  --region us-east-1
```

Update your task definition environment variable:
```json
{
  "name": "DJANGO_ALLOWED_HOSTS",
  "value": "yourdomain.com,www.yourdomain.com,djangotutorial-alb-1234567890.us-east-1.elb.amazonaws.com"
}
```

## Quick Test
After setup, test your ALB endpoint:
```powershell
curl http://$ALB_DNS
```

## Add SSL/HTTPS (Recommended)

### Request ACM Certificate
```powershell
$CERT_ARN = aws acm request-certificate `
  --domain-name yourdomain.com `
  --subject-alternative-names www.yourdomain.com `
  --validation-method DNS `
  --region us-east-1 `
  --query 'CertificateArn' `
  --output text
```

### Add HTTPS Listener
```powershell
aws elbv2 create-listener `
  --load-balancer-arn $ALB_ARN `
  --protocol HTTPS `
  --port 443 `
  --certificates CertificateArn=$CERT_ARN `
  --default-actions Type=forward,TargetGroupArn=$TG_ARN `
  --region us-east-1
```

### Redirect HTTP to HTTPS
```powershell
# Get HTTP listener ARN
$HTTP_LISTENER_ARN = aws elbv2 describe-listeners `
  --load-balancer-arn $ALB_ARN `
  --query 'Listeners[?Protocol==`HTTP`].ListenerArn' `
  --output text `
  --region us-east-1

# Modify to redirect
aws elbv2 modify-listener `
  --listener-arn $HTTP_LISTENER_ARN `
  --default-actions Type=redirect,RedirectConfig='{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}' `
  --region us-east-1
```
