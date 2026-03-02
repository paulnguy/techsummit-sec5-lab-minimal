#!/bin/bash
# Quick route check for student VPC

STACK_NAME="${1:-nfw-lab-student}"
REGION="${2:-us-east-1}"

VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`StudentVpcId`].OutputValue' \
  --output text 2>/dev/null)

if [ -z "$VPC_ID" ]; then
  echo "❌ Stack not found or no VPC ID"
  exit 1
fi

echo "VPC: $VPC_ID"
echo
echo "All Route Tables:"
aws ec2 describe-route-tables \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'RouteTables[*].[Tags[?Key==`Name`].Value|[0],Routes[*].[DestinationCidrBlock,GatewayId,VpcEndpointId,State]]' \
  --output text | awk 'BEGIN{rt=""} /^[^\t]/{rt=$0; next} {print rt": "$0}'
