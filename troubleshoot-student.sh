#!/bin/bash
# Troubleshoot student VPC connectivity issues
# Run this from your local machine with AWS CLI configured

set -e

STACK_NAME="${1:-nfw-lab-student}"
REGION="${2:-us-east-1}"

echo "🔍 Troubleshooting Student VPC: $STACK_NAME in $REGION"
echo "=============================================="
echo

# Get stack outputs
echo "📋 Stack Outputs:"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table

VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`StudentVpcId`].OutputValue' \
  --output text)

INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`TestInstanceId`].OutputValue' \
  --output text)

FIREWALL_ENDPOINT_ID=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`FirewallEndpointId`].OutputValue' \
  --output text)

echo
echo "🔑 Key Resources:"
echo "  VPC ID: $VPC_ID"
echo "  Instance ID: $INSTANCE_ID"
echo "  Firewall Endpoint: $FIREWALL_ENDPOINT_ID"
echo

# Check instance status
echo "✅ EC2 Instance Status:"
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PrivateIpAddress,SubnetId]' \
  --output table

# Check route tables
echo
echo "🗺️  Route Tables:"
echo "Protected Route Table:"
aws ec2 describe-route-tables \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*protected-rt*" \
  --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,GatewayId,VpcEndpointId,State]' \
  --output table

echo
echo "Firewall Route Table:"
aws ec2 describe-route-tables \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*firewall-rt*" \
  --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,GatewayId,VpcEndpointId,State]' \
  --output table

echo
echo "IGW Route Table:"
aws ec2 describe-route-tables \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*igw-rt*" \
  --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,GatewayId,VpcEndpointId,State]' \
  --output table

# Check security groups
echo
echo "🔒 Security Group (Instance):"
INSTANCE_SG=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text)

aws ec2 describe-security-groups \
  --group-ids "$INSTANCE_SG" \
  --region "$REGION" \
  --query 'SecurityGroups[0].[GroupId,GroupName]' \
  --output table

echo
echo "Egress Rules (Outbound):"
aws ec2 describe-security-groups \
  --group-ids "$INSTANCE_SG" \
  --region "$REGION" \
  --query 'SecurityGroups[0].IpPermissionsEgress[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]' \
  --output table

# Check VPC endpoints
echo
echo "🔗 VPC Endpoints:"
aws ec2 describe-vpc-endpoints \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[*].[VpcEndpointId,ServiceName,State]' \
  --output table

# Check firewall endpoint association
echo
echo "🛡️  Firewall Endpoint Association:"
if [ ! -z "$FIREWALL_ENDPOINT_ID" ]; then
  echo "  Endpoint ID: $FIREWALL_ENDPOINT_ID"
  echo "  Status: Check in Network Firewall console"
else
  echo "  ⚠️  No firewall endpoint found in outputs"
fi

# Check NAT Gateway (should be none)
echo
echo "📡 NAT Gateways (should be empty):"
aws ec2 describe-nat-gateways \
  --region "$REGION" \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'NatGateways[*].[NatGatewayId,State,SubnetId]' \
  --output table

# Check Internet Gateway
echo
echo "🌐 Internet Gateway:"
aws ec2 describe-internet-gateways \
  --region "$REGION" \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query 'InternetGateways[*].[InternetGatewayId,Attachments[0].State]' \
  --output table

echo
echo "✅ Troubleshooting complete!"
echo
echo "📝 Common Issues:"
echo "  1. If firewall endpoint is empty → VpcEndpointAssociation failed"
echo "  2. If routes show 'blackhole' → Firewall endpoint not ready"
echo "  3. If IGW route table is empty → Gateway association failed"
echo "  4. Check instructor firewall rules allow HTTP/HTTPS/DNS"
echo
echo "🔧 Next Steps:"
echo "  1. SSH to EC2 via Instance Connect"
echo "  2. Run: curl -v http://example.com"
echo "  3. Run: dig @8.8.8.8 google.com"
echo "  4. Check CloudWatch Logs for firewall alerts"
