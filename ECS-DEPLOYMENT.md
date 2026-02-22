# ECS Deployment Guide

## Prerequisites
- Docker image pushed to ECR ✓
- AWS CLI configured
- VPC with public/private subnets
- Security group allowing port 8000

## Step 1: Create CloudWatch Log Group
```bash
aws logs create-log-group --log-group-name /ecs/djangotutorial --region us-east-1
```

## Step 2: Store Secret in AWS Secrets Manager
```bash
aws secretsmanager create-secret \
  --name djangotutorial/SECRET_KEY \
  --secret-string "your-production-secret-key-here" \
  --region us-east-1
```

## Step 3: Create ECS Task Execution Role (if not exists)
```bash
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
```

## Step 4: Register Task Definition
```bash
aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json --region us-east-1
```

## Step 5: Create ECS Cluster (if not exists)
```bash
aws ecs create-cluster --cluster-name djangotutorial-cluster --region us-east-1
```

## Step 6: Create Security Group
```bash
# Get your VPC ID
VPC_ID=$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text --region us-east-1)

# Create security group
SG_ID=$(aws ec2 create-security-group \
  --group-name djangotutorial-sg \
  --description "Django Tutorial Security Group" \
  --vpc-id $VPC_ID \
  --region us-east-1 \
  --query 'GroupId' \
  --output text)

# Allow port 8000
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8000 \
  --cidr 0.0.0.0/0 \
  --region us-east-1
```

## Step 7: Create ECS Service
```bash
# Get subnet IDs (use your VPC subnets)
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0].SubnetId' --output text --region us-east-1)

# Create service
aws ecs create-service \
  --cluster djangotutorial-cluster \
  --service-name djangotutorial-service \
  --task-definition djangotutorial \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
  --region us-east-1
```

## Step 8: Get Public IP
```bash
aws ecs list-tasks --cluster djangotutorial-cluster --service-name djangotutorial-service --region us-east-1

# Get task ARN and then ENI
TASK_ARN=$(aws ecs list-tasks --cluster djangotutorial-cluster --service-name djangotutorial-service --query 'taskArns[0]' --output text --region us-east-1)

aws ecs describe-tasks --cluster djangotutorial-cluster --tasks $TASK_ARN --region us-east-1 --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text
```

## With Application Load Balancer (Recommended)

### Create Target Group
```bash
TG_ARN=$(aws elbv2 create-target-group \
  --name djangotutorial-tg \
  --protocol HTTP \
  --port 8000 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-path / \
  --region us-east-1 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)
```

### Create Application Load Balancer
```bash
# Get multiple subnet IDs for ALB
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0:2].SubnetId' --output text --region us-east-1 | tr '\t' ',')

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name djangotutorial-alb \
  --subnets $SUBNETS \
  --security-groups $SG_ID \
  --region us-east-1 \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

# Create listener
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --region us-east-1
```

### Update ECS Service with Load Balancer
```bash
aws ecs update-service \
  --cluster djangotutorial-cluster \
  --service djangotutorial-service \
  --load-balancers targetGroupArn=$TG_ARN,containerName=djangotutorial,containerPort=8000 \
  --region us-east-1
```

## Update Deployment (after code changes)
```bash
# Build and push new image
docker build -t djangotutorial .
docker tag djangotutorial:latest 357323381626.dkr.ecr.us-east-1.amazonaws.com/djangotutorial:latest
docker push 357323381626.dkr.ecr.us-east-1.amazonaws.com/djangotutorial:latest

# Force new deployment
aws ecs update-service \
  --cluster djangotutorial-cluster \
  --service djangotutorial-service \
  --force-new-deployment \
  --region us-east-1
```

## Useful Commands
```bash
# View service status
aws ecs describe-services --cluster djangotutorial-cluster --services djangotutorial-service --region us-east-1

# View logs
aws logs tail /ecs/djangotutorial --follow --region us-east-1

# Scale service
aws ecs update-service --cluster djangotutorial-cluster --service djangotutorial-service --desired-count 2 --region us-east-1

# Delete service
aws ecs delete-service --cluster djangotutorial-cluster --service djangotutorial-service --force --region us-east-1
```
