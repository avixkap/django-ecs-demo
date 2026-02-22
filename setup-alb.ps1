# Quick ALB Setup Script for Django ECS
# Run this in PowerShell

$ErrorActionPreference = "Stop"
$REGION = "us-east-1"
$CLUSTER = "djangotutorial-cluster"
$SERVICE = "djangotutorial-service"

Write-Host "🚀 Setting up Application Load Balancer..." -ForegroundColor Green

# Get VPC
Write-Host "Getting VPC information..." -ForegroundColor Yellow
$VPC_ID = aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text --region $REGION
Write-Host "VPC ID: $VPC_ID" -ForegroundColor Cyan

# Get Subnets (need at least 2 in different AZs)
Write-Host "Getting subnets..." -ForegroundColor Yellow
$SUBNETS = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0:2].SubnetId' --output text --region $REGION
$SUBNET_ARRAY = $SUBNETS -split '\s+'
$SUBNET1 = $SUBNET_ARRAY[0]
$SUBNET2 = $SUBNET_ARRAY[1]
Write-Host "Subnets: $SUBNET1, $SUBNET2" -ForegroundColor Cyan

# Create ALB Security Group
Write-Host "Creating ALB security group..." -ForegroundColor Yellow
try {
    $ALB_SG_ID = aws ec2 create-security-group `
        --group-name djangotutorial-alb-sg `
        --description "Django ALB Security Group" `
        --vpc-id $VPC_ID `
        --region $REGION `
        --query 'GroupId' `
        --output text
    
    Start-Sleep -Seconds 2
    
    # Allow HTTP
    aws ec2 authorize-security-group-ingress `
        --group-id $ALB_SG_ID `
        --protocol tcp `
        --port 80 `
        --cidr 0.0.0.0/0 `
        --region $REGION
    
    # Allow HTTPS
    aws ec2 authorize-security-group-ingress `
        --group-id $ALB_SG_ID `
        --protocol tcp `
        --port 443 `
        --cidr 0.0.0.0/0 `
        --region $REGION
    
    Write-Host "ALB Security Group: $ALB_SG_ID" -ForegroundColor Cyan
} catch {
    Write-Host "Security group may already exist, continuing..." -ForegroundColor DarkYellow
    $ALB_SG_ID = aws ec2 describe-security-groups --filters "Name=group-name,Values=djangotutorial-alb-sg" --query 'SecurityGroups[0].GroupId' --output text --region $REGION
}

# Get ECS Security Group
$ECS_SG_ID = aws ec2 describe-security-groups --filters "Name=group-name,Values=djangotutorial-sg" --query 'SecurityGroups[0].GroupId' --output text --region $REGION

# Allow ALB to ECS
Write-Host "Configuring ECS security group..." -ForegroundColor Yellow
try {
    aws ec2 authorize-security-group-ingress `
        --group-id $ECS_SG_ID `
        --protocol tcp `
        --port 8000 `
        --source-group $ALB_SG_ID `
        --region $REGION 2>$null
} catch {
    Write-Host "Rule may already exist, continuing..." -ForegroundColor DarkYellow
}

# Create Target Group
Write-Host "Creating target group..." -ForegroundColor Yellow
try {
    $TG_ARN = aws elbv2 create-target-group `
        --name djangotutorial-tg `
        --protocol HTTP `
        --port 8000 `
        --vpc-id $VPC_ID `
        --target-type ip `
        --health-check-path / `
        --health-check-interval-seconds 30 `
        --region $REGION `
        --query 'TargetGroups[0].TargetGroupArn' `
        --output text
    Write-Host "Target Group: $TG_ARN" -ForegroundColor Cyan
} catch {
    $TG_ARN = aws elbv2 describe-target-groups --names djangotutorial-tg --query 'TargetGroups[0].TargetGroupArn' --output text --region $REGION
    Write-Host "Using existing Target Group: $TG_ARN" -ForegroundColor DarkYellow
}

# Create ALB
Write-Host "Creating Application Load Balancer..." -ForegroundColor Yellow
try {
    $ALB_ARN = aws elbv2 create-load-balancer `
        --name djangotutorial-alb `
        --subnets $SUBNET1 $SUBNET2 `
        --security-groups $ALB_SG_ID `
        --scheme internet-facing `
        --type application `
        --region $REGION `
        --query 'LoadBalancers[0].LoadBalancerArn' `
        --output text
    
    Write-Host "ALB created successfully!" -ForegroundColor Green
    Start-Sleep -Seconds 5
} catch {
    Write-Host "ALB may already exist, getting existing ALB..." -ForegroundColor DarkYellow
    $ALB_ARN = aws elbv2 describe-load-balancers --names djangotutorial-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text --region $REGION
}

# Get ALB DNS Name
$ALB_DNS = aws elbv2 describe-load-balancers `
    --load-balancer-arns $ALB_ARN `
    --region $REGION `
    --query 'LoadBalancers[0].DNSName' `
    --output text

Write-Host "`n🌐 ALB DNS Name: $ALB_DNS" -ForegroundColor Green -BackgroundColor Black

# Create Listener
Write-Host "Creating HTTP listener..." -ForegroundColor Yellow
try {
    aws elbv2 create-listener `
        --load-balancer-arn $ALB_ARN `
        --protocol HTTP `
        --port 80 `
        --default-actions Type=forward,TargetGroupArn=$TG_ARN `
        --region $REGION 2>$null
} catch {
    Write-Host "Listener may already exist, continuing..." -ForegroundColor DarkYellow
}

# Update ECS Service
Write-Host "Updating ECS service to use ALB..." -ForegroundColor Yellow
aws ecs update-service `
    --cluster $CLUSTER `
    --service $SERVICE `
    --load-balancers targetGroupArn=$TG_ARN,containerName=djangotutorial,containerPort=8000 `
    --health-check-grace-period-seconds 60 `
    --region $REGION `
    --force-new-deployment

Write-Host "`n✅ Setup complete!" -ForegroundColor Green
Write-Host "`n📋 Next Steps:" -ForegroundColor Yellow
Write-Host "1. Wait 2-3 minutes for ALB to become active"
Write-Host "2. Test your app: http://$ALB_DNS"
Write-Host "3. Add DNS record (CNAME) pointing to: $ALB_DNS"
Write-Host "4. Update DJANGO_ALLOWED_HOSTS in task definition with your domain"
Write-Host "`nTo check ALB status:"
Write-Host "  aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --region $REGION --query 'LoadBalancers[0].State'" -ForegroundColor Cyan
