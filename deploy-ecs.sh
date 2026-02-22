#!/usr/bin/env bash

# Quick ECS Deployment Script
set -e

REGION="us-east-1"
CLUSTER="djangotutorial-cluster"
SERVICE="djangotutorial-service"
TASK_FAMILY="djangotutorial"
IMAGE="357323381626.dkr.ecr.us-east-1.amazonaws.com/djangotutorial:latest"
ACCOUNT_ID="357323381626"

echo "🚀 Deploying Django to ECS..."

# 1. Create log group
echo "📝 Creating CloudWatch log group..."
aws logs create-log-group --log-group-name /ecs/djangotutorial --region $REGION 2>/dev/null || echo "Log group already exists"

# 2. Register task definition
echo "📋 Registering task definition..."
aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json --region $REGION

# 3. Create cluster
echo "🏗️  Creating ECS cluster..."
aws ecs create-cluster --cluster-name $CLUSTER --region $REGION 2>/dev/null || echo "Cluster already exists"

# 4. Get VPC and Subnet info
echo "🔍 Getting VPC information..."
VPC_ID=vpc-0f422414ac79b308f
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text --region $REGION | tr '\t' ',')

# 5. Create or get security group
echo "🔒 Setting up security group..."
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=djangotutorial-sg" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text --region $REGION 2>/dev/null)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
    SG_ID=$(aws ec2 create-security-group \
        --group-name djangotutorial-sg \
        --description "Django Tutorial Security Group" \
        --vpc-id $VPC_ID \
        --region $REGION \
        --query 'GroupId' \
        --output text)
    
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 8000 \
        --cidr 0.0.0.0/0 \
        --region $REGION
fi

# 6. Create or update service
echo "🎯 Creating/Updating ECS service..."
SERVICE_EXISTS=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $REGION --query 'services[0].status' --output text 2>/dev/null)

if [ "$SERVICE_EXISTS" == "ACTIVE" ]; then
    echo "Updating existing service..."
    aws ecs update-service \
        --cluster $CLUSTER \
        --service $SERVICE \
        --force-new-deployment \
        --region $REGION
else
    echo "Creating new service..."
    SUBNET_ARRAY=$(echo $SUBNET_IDS | sed 's/,/","/g')
    aws ecs create-service \
        --cluster $CLUSTER \
        --service-name $SERVICE \
        --task-definition $TASK_FAMILY \
        --desired-count 1 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[\"$SUBNET_ARRAY\"],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
        --region $REGION
fi

echo "✅ Deployment initiated!"
echo ""
echo "To check status:"
echo "  aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $REGION"
echo ""
echo "To view logs:"
echo "  aws logs tail /ecs/djangotutorial --follow --region $REGION"
