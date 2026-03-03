#!/bin/bash

echo "=== EC2 INSTANCE PUBLIC IP DIAGNOSTIC ==="
echo ""

STACK_NAME="nfw-pnguyen1"
REGION="us-east-1"

# 1. Get instance ID from CloudFormation
echo "1. Getting Instance ID from CloudFormation stack..."
INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`TestInstanceId`].OutputValue' \
  --output text 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
  echo "   ✗ ERROR: Could not get instance ID from stack outputs"
  exit 1
fi
echo "   Instance ID: $INSTANCE_ID"
echo ""

# 2. Check instance details
echo "2. Checking EC2 instance network configuration..."
INSTANCE_INFO=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0]' \
  --output json 2>/dev/null)

PRIVATE_IP=$(echo "$INSTANCE_INFO" | jq -r '.PrivateIpAddress // "None"')
PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.PublicIpAddress // "None"')
STATE=$(echo "$INSTANCE_INFO" | jq -r '.State.Name')
SUBNET_ID=$(echo "$INSTANCE_INFO" | jq -r '.SubnetId')

echo "   Private IP:  $PRIVATE_IP"
echo "   Public IP:   $PUBLIC_IP"
echo "   State:       $STATE"
echo "   Subnet ID:   $SUBNET_ID"
echo ""

if [ "$PUBLIC_IP" = "None" ] || [ "$PUBLIC_IP" = "null" ]; then
  echo "   ❌ NO PUBLIC IP ASSIGNED"
else
  echo "   ✅ PUBLIC IP ASSIGNED: $PUBLIC_IP"
fi
echo ""

# 3. Check CloudFormation outputs
echo "3. Checking CloudFormation stack outputs..."
PUBLIC_IP_OUTPUT=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`TestInstancePublicIp`].OutputValue' \
  --output text 2>/dev/null)

if [ -z "$PUBLIC_IP_OUTPUT" ] || [ "$PUBLIC_IP_OUTPUT" = "None" ]; then
  echo "   TestInstancePublicIp output: NOT FOUND or empty"
  echo "   ⚠️  This output may not exist in the deployed template"
else
  echo "   TestInstancePublicIp output: $PUBLIC_IP_OUTPUT"
fi
echo ""

# 4. Check subnet settings
echo "4. Checking subnet MapPublicIpOnLaunch setting..."
MAP_PUBLIC=$(aws ec2 describe-subnets \
  --subnet-ids "$SUBNET_ID" \
  --region "$REGION" \
  --query 'Subnets[0].MapPublicIpOnLaunch' \
  --output text 2>/dev/null)

echo "   Subnet: $SUBNET_ID"
echo "   MapPublicIpOnLaunch: $MAP_PUBLIC"
echo ""

# 5. Check network interface details
echo "5. Checking network interface configuration..."
ENI_ID=$(echo "$INSTANCE_INFO" | jq -r '.NetworkInterfaces[0].NetworkInterfaceId // "None"')
ASSOCIATION=$(echo "$INSTANCE_INFO" | jq -r '.NetworkInterfaces[0].Association // "null"')

echo "   Network Interface ID: $ENI_ID"
if [ "$ASSOCIATION" = "null" ]; then
  echo "   Public IP Association: NONE"
  echo "   ❌ Network interface has no public IP association"
else
  echo "   Public IP Association: EXISTS"
  echo "   ✅ Network interface has public IP association"
fi
echo ""

# 6. Root cause analysis
echo "=== ROOT CAUSE ANALYSIS ==="
echo ""

if [ "$PUBLIC_IP" = "None" ] || [ "$PUBLIC_IP" = "null" ]; then
  echo "❌ ISSUE CONFIRMED: Instance has NO public IP"
  echo ""
  echo "Possible causes:"
  echo "1. Template deployed WITHOUT 'AssociatePublicIpAddress: true' in NetworkInterfaces"
  echo "2. Subnet has MapPublicIpOnLaunch disabled (subnet setting: $MAP_PUBLIC)"
  echo "3. Instance was created before template was updated with public IP config"
  echo ""
  echo "SOLUTION: Update the CloudFormation stack with the new template"
  echo "This will REPLACE the EC2 instance (delete old, create new with public IP)"
  echo ""
  echo "Run this command:"
  echo "  aws cloudformation update-stack \\"
  echo "    --stack-name $STACK_NAME \\"
  echo "    --template-body file://nfw-student-min.yaml \\"
  echo "    --region $REGION"
else
  echo "✅ Instance HAS public IP: $PUBLIC_IP"
  echo ""
  echo "If you cannot connect to the internet from this instance:"
  echo "  1. Check security group allows outbound traffic"
  echo "  2. Check route table: Protected subnet → Firewall Endpoint"
  echo "  3. Check firewall route table: Firewall subnet → IGW"
  echo "  4. Check IGW edge route table: IGW → Firewall Endpoint"
  echo "  5. Run: ./troubleshoot-student.sh"
fi
echo ""
