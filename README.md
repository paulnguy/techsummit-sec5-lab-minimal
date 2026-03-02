# AWS Network Firewall Multi-Account Lab - TechSummit Sec5

## Overview

This lab demonstrates a **scalable, multi-account AWS Network Firewall deployment** designed for instructor-led training with minimal infrastructure footprint. It showcases how to deploy a shared Network Firewall that serves multiple student accounts via VPC Endpoint Associations, with bidirectional traffic inspection and browser-based access.

### Key Features

- **Shared Firewall Inspection**: One Network Firewall per Region serves multiple students via VPC Endpoint Associations
- **Bidirectional Inspection**: IGW edge route tables ensure return traffic is also inspected
- **Browser-Based Access**: EC2 Instance Connect Endpoint for secure, keyless console access
- **Multi-Region**: Deployable across us-east-1, eu-west-2, ap-southeast-1
- **Automated Cleanup**: Scripted teardown of all resources
- **30-Minute Deployment**: Fully operational lab in under 30 minutes
- **Scales to 300+ Students**: Supports 300+ VPC associations per firewall per region

---

## Architecture

### Overall Lab Design

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          AWS Organizations                              │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Management Account (StackSet Deployment)                       │    │
│  │  └─> Creates and manages CloudFormation StackSets               │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                              │                                          │
│                              │ Service-Managed StackSets                │
│                              ├──> Instructor Stack per Region/Account   │
│                              └──> Student Stack per Account             │
│                                                                         │
│  ┌──────────────────────┬──────────────────────┬──────────────────────┐ │
│  │  Account 1           │  Account 2           │  Account 3           │ │
│  │  (Instructor + Lab)  │  (Student)           │  (Student)           │ │
│  └──────────────────────┴──────────────────────┴──────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                         Deployed in 3 Regions:
                    us-east-1 | eu-west-2 | ap-southeast-1
```

### Per-Region Per-Account Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│  AWS Region (us-east-1, eu-west-2, or ap-southeast-1)                      │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Instructor Account                                                  │  │
│  │                                                                      │  │
│  │  ┌────────────────────────────────────────────────────────────────┐  │  │
│  │  │  Firewall VPC (10.0.0.0/16) - Availability Zone A              │  │  │
│  │  │                                                                │  │  │
│  │  │  ┌─────────────────────────┐         ┌─────────────────────┐ │ │  │
│  │  │  │  Firewall Subnet        │         │  Internet Gateway   │ │ │  │
│  │  │  │  10.0.1.0/24 (AZ-a)     │         │   (IGW)             │ │ │  │
│  │  │  │                         │         │                     │ │ │  │
│  │  │  │  ┌─────────────────┐    │         │                     │ │ │  │
│  │  │  │  │  Network        │    │◄───────►│                     │ │ │  │
│  │  │  │  │  Firewall       │    │  Route  │                     │ │ │  │
│  │  │  │  │  - Endpoint     │    │  0.0.0/0│                     │ │ │  │
│  │  │  │  │  - Optional     │    │         │                     │ │ │  │
│  │  │  │  │    rules        │    │         │                     │ │ │  │
│  │  │  │  └─────────────────┘    │         │                     │ │ │  │
│  │  │  └─────────────────────────┘         └─────────────────────┘ │ │  │
│  │  │                                                                │  │ │
│  │  └────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                      │ │
│  │  Optional Logging (enable post-deploy):                              │ │
│  │  CloudWatch Logs for ALERT and FLOW                                  │ │
│  │                                                                      │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │  Student Account(s)                                                  │ │
│  │                                                                      │ │
│  │  ┌─────────────────────────────────────────────────────────────┐     │ │
│  │  │  Student VPC (10.1.0.0/16) - Availability Zone A            │   │ │
│  │  │                                                             │   │ │
│  │  │  ┌─────────────────────────────┐    ┌──────────────────┐   │   │ │
│  │  │  │ Protected Subnet (10.1.1/24)│    │ Firewall Subnet  │   │   │ │
│  │  │  │                             │    │  (10.1.2/24)     │   │   │ │
│  │  │  │ Route Table:                │    │                  │   │   │ │
│  │  │  │ 0.0.0.0/0 → vpce-firewall   │    │  Firewall        │   │   │ │
│  │  │  │                             │    │  Endpoint Assoc. │   │   │ │
│  │  │  │ ┌──────────────────────┐    │    │                  │   │   │ │
│  │  │  │ │ EC2 Test Instance    │    │    │  (Link to shared │   │   │ │
│  │  │  │ │ (t3.micro private IP)│    │    │   firewall)      │   │   │ │
│  │  │  │ │                      │    │    │                  │   │   │ │
│  │  │  │ │ Pre-installed:       │    │    │ IGW Route Table: │   │   │ │
│  │  │  │ │ - curl               │    │    │ 10.1.1/24        │   │   │ │
│  │  │  │ │ - dig                │    │    │ → vpce-firewall  │   │   │ │
│  │  │  │ │ - wget               │    │    │ (return traffic) │   │   │ │
│  │  │  │ └──────────────────────┘    │    │                  │   │   │ │
│  │  │  │                             │    │                  │   │   │ │
│  │  │  │ ┌─────────────────────┐     │    │                  │   │   │ │
│  │  │  │ │ EIC Endpoint        │     │    │                  │   │   │ │
│  │  │  │ │ (browser SSH access)│     │    │                  │   │   │ │
│  │  │  │ └─────────────────────┘     │    │                  │   │   │ │
│  │  │  └─────────────────────────────┘    └──────────────────┘   │   │ │
│  │  │                                                             │   │ │
│  │  │  VPC Endpoint Association to Shared Network Firewall        │   │ │
│  │  │  (Connected to Instructor's Firewall Endpoint)              │   │ │
│  │  │                                                             │   │ │
│  │  │  Internet Gateway:                                          │   │ │
│  │  │  └─► Provides egress for firewall                           │   │ │
│  │  │  └─► Return traffic routed back through firewall            │   │ │
│  │  │      via IGW edge route table                               │   │ │
│  │  │                                                             │   │ │
│  │  └─────────────────────────────────────────────────────────┘   │   │
│  │                                                                    │ │
│  │  [Multiple student accounts can be deployed with identical setup]  │ │
│  │                                                                      │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow (Bidirectional Inspection)

**Outbound (EC2 to Internet):**
```
EC2 Test Instance (10.1.1.x)
   ↓ curl http://example.com
Protected Subnet Route Table (0.0.0.0/0)
   ↓ routes to vpce-firewall
Shared Network Firewall
   ↓ evaluates rules (HTTP/HTTPS/DNS/ICMP pass, others drop)
Firewall Route Table (0.0.0.0/0)
   ↓ routes to IGW
Internet Gateway
   ↓
Internet (Public IP conversion, NAT)
```

**Return Traffic (Internet to EC2):**
```
Internet → Response packets
   ↓
Internet Gateway
   ↓
IGW Edge Route Table (10.1.1.0/24 pattern)
   ↓ routes return traffic back through vpce-firewall
Shared Network Firewall
   ↓ evaluates stateful rules (connection already established)
Firewall Subnet Route Table
   ↓
Protected Subnet
   ↓
EC2 Instance (receives response)
```

**SSH Access (via EIC Endpoint - not inspected by firewall):**
```
AWS Console → "Connect" button
   ↓
EC2 Instance Connect Endpoint
   ↓ (uses port 22, direct path)
EC2 Instance Terminal
   ↓
curl/dig testing
```

---

## Components

### 1. **nfw-instructor.yaml** - Shared Network Firewall Infrastructure

Deployed once **per account per Region** (management overhead = minimal).

**Resources Created:**
- **Firewall VPC** (10.0.0.0/16, single-AZ)
  - Subnet in AZ-a for firewall placement
  - Route to Internet Gateway
  - Network Firewall with default allow rules
- **Default Rule Group**: Allows HTTP/HTTPS/DNS/ICMP (can be customized post-deploy)
- **Logging**: Optional, enable after deployment via CloudWatch

**Parameters:**
- `FirewallName`: Name of the firewall (default: `nfw-lab`)
- `FirewallVpcCIDR`: VPC CIDR block (default: `10.0.0.0/16`)
- `FirewallSubnetCIDR`: Firewall subnet CIDR (default: `10.0.1.0/24`)

**Outputs:**
- `FirewallArn`: Used by student templates
- `FirewallId`: Firewall identifier
- `FirewallAzName`: Availability Zone hosting the firewall endpoint

---

### 2. **nfw-student-min.yaml** - Per-Student Lab Environment

Deployed via **CloudFormation StackSets** (service-managed) across target accounts and Regions.

**Resources Created per Student:**
- **Student VPC** (10.1.0.0/16, configurable)
  - **Protected Subnet** (10.1.1.0/24): EC2 instance located here
  - **Firewall Subnet** (10.1.2.0/24): Firewall endpoint association located here
  - Single-AZ (AZ-a) placement aligned with firewall
  
- **Route Tables for Bidirectional Inspection**:
  - **Protected Route Table**: 0.0.0.0/0 → Firewall Endpoint
  - **Firewall Route Table**: 0.0.0.0/0 → Internet Gateway
  - **IGW Edge Route Table**: 10.1.1.0/24 → Firewall Endpoint (return traffic)

- **VPC Endpoint Association**: Connects to shared firewall in instructor account

- **EC2 Test Instance** (t3.micro):
  - Private IP only (no public IP)
  - Pre-installed: `curl`, `dig`, `wget`
  - Located in protected subnet

- **EC2 Instance Connect (EIC) Endpoint**:
  - Browser-based SSH access via AWS Console
  - No SSH keys required
  - Security group allows SSH (port 22) to EC2 instance

- **Internet Gateway**: Provides egress path for firewall traffic

**Parameters:**
- `FirewallArn`: ARN from instructor stack (required)
- `LabName`: Lab identifier (default: `nfw-lab-student`)
- `StudentVpcCIDR`: Student VPC CIDR (default: `10.1.0.0/16`)
- `ProtectedSubnetCIDR`: EC2 subnet (default: `10.1.1.0/24`)
- `FirewallSubnetCIDR`: Firewall endpoint subnet (default: `10.1.2.0/24`)
- `InstanceType`: EC2 type (default: `t3.micro`, options: t3.small, t3.medium)

**Scalability:**
- Default quota: 300 VPC Endpoint Associations per Region per firewall
- Supports 300+ students per Region on a single firewall
- Each student gets isolated VPC with bidirectional inspection

---

### 3. **lab-cleanup.sh** - Automated Resource Cleanup

Comprehensive cleanup script with error handling and role-based targeting.

**Features:**
- Deletes StackSet instances (student VPCs)
- Deletes StackSet template
- Optionally deletes instructor stacks
- Supports both OU-based and account-ID-based targeting
- Detailed logging and timeout handling

---

## Deployment Guide

### Prerequisites

1. **AWS Account Setup**:
   - Management account with AWS Organizations enabled
   - CloudFormation StackSets enabled (trusted access)
   - 3+ AWS accounts in desired OU (or specified account IDs)

2. **Tools**:
   - AWS CLI v2 configured with credentials
   - Bash shell
   - Internet connectivity

3. **Permissions** (in management account):
   - CloudFormation full permissions
   - Organizations read permissions
   - IAM role creation permissions

### Step 1: Deploy Instructor Stack (Per Account/Region)

From each lab account, deploy the instructor stack in each target Region:

```bash
# Set variables
REGION=us-east-1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Deploy to us-east-1
aws cloudformation deploy \
  --region us-east-1 \
  --stack-name nfw-instructor \
  --template-file nfw-instructor.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides FirewallName=nfw-lab-us-east-1

# Record outputs
aws cloudformation describe-stacks \
  --region us-east-1 \
  --stack-name nfw-instructor \
  --query 'Stacks[0].Outputs' \
  --output table

# Repeat for eu-west-2 and ap-southeast-1
aws cloudformation deploy \
  --region eu-west-2 \
  --stack-name nfw-instructor \
  --template-file nfw-instructor.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides FirewallName=nfw-lab-eu-west-2

aws cloudformation deploy \
  --region ap-southeast-1 \
  --stack-name nfw-instructor \
  --template-file nfw-instructor.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides FirewallName=nfw-lab-ap-southeast-1
```

**Note**: Record the `FirewallArn` outputs—you'll need them for the StackSet.

### Step 2: Create Student StackSet (From Management Account)

Login to the **management account** and create the StackSet:

```bash
# Create StackSet
aws cloudformation create-stack-set \
  --stack-set-name nfw-student-min \
  --template-body file://nfw-student-min.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --description "Network Firewall student labs" \
  --region us-east-1

# For each Region, create a stack instance with region-specific FirewallArn
# Example for us-east-1:
aws cloudformation create-stack-instances \
  --stack-set-name nfw-student-min \
  --regions us-east-1 \
  --deployment-targets OrganizationalUnitIds=ou-xxxx-yyyyyyyy \
  --parameter-overrides \
    ParameterKey=FirewallArn,ParameterValue=arn:aws:network-firewall:us-east-1:123456789012:firewall/nfw-lab-us-east-1 \
    ParameterKey=LabName,ParameterValue=nfw-lab-student \
  --region us-east-1

# Repeat for eu-west-2 and ap-southeast-1 with their respective FirewallArn values
aws cloudformation create-stack-instances \
  --stack-set-name nfw-student-min \
  --regions eu-west-2 \
  --deployment-targets OrganizationalUnitIds=ou-xxxx-yyyyyyyy \
  --parameter-overrides \
    ParameterKey=FirewallArn,ParameterValue=arn:aws:network-firewall:eu-west-2:123456789012:firewall/nfw-lab-eu-west-2 \
    ParameterKey=LabName,ParameterValue=nfw-lab-student \
  --region us-east-1

aws cloudformation create-stack-instances \
  --stack-set-name nfw-student-min \
  --regions ap-southeast-1 \
  --deployment-targets OrganizationalUnitIds=ou-xxxx-yyyyyyyy \
  --parameter-overrides \
    ParameterKey=FirewallArn,ParameterValue=arn:aws:network-firewall:ap-southeast-1:123456789012:firewall/nfw-lab-ap-southeast-1 \
    ParameterKey=LabName,ParameterValue=nfw-lab-student \
  --region us-east-1

# Verify StackSet operations
aws cloudformation list-stack-instances \
  --stack-set-name nfw-student-min \
  --region us-east-1
```

**Alternative**: Use the AWS Console for StackSet creation with parameter overrides per Region.

### Step 3: Verify Deployment

```bash
# Check instructor stack in each region
for region in us-east-1 eu-west-2 ap-southeast-1; do
  echo "=== Region: $region ==="
  aws cloudformation describe-stacks \
    --region $region \
    --stack-name nfw-instructor \
    --query 'Stacks[0].StackStatus' \
    --output text
done

# Check student stacks (from management account)
aws cloudformation list-stack-instances \
  --stack-set-name nfw-student-min \
  --region us-east-1 \
  --query 'Summaries[].[Region,Account,Status]' \
  --output table

# Verify firewall is operational
aws ec2 describe-network-interfaces \
  --filters "Name=description,Values=*firewall*" \
  --region us-east-1 \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status]' \
  --output table
```

---

## Student Lab Instructions

### Accessing Your Lab Instance

**Method 1: EC2 Instance Connect Endpoint (Recommended)**

1. **Login to AWS Console** in your assigned student account
2. Navigate to **EC2** → **Instances**
3. Select your instance (e.g., `nfw-lab-student-instance`)
4. Click the **Connect** button (top right)
5. Select **EC2 Instance Connect** tab
6. Click **Connect** to open browser-based terminal

No SSH keys, no public IPs required—direct browser-based access!

**Method 2: AWS Systems Manager Session Manager (Alternative)**

1. Navigate to **Systems Manager** → **Session Manager** → **Start session**
2. Select your instance
3. Click **Start session**

### Lab Exercise: Test Firewall Rules

Once connected to your EC2 instance via the browser terminal:

```bash
# Test DNS query (UDP 53) - should PASS
dig @8.8.8.8 amazon.com

# Test HTTPS (TCP 443) - should PASS
curl -I https://www.google.com

# Test HTTP (TCP 80) - should PASS
curl -I http://example.com

# Test ICMP (ping) - should PASS
ping -c 3 8.8.8.8

# Test blocked traffic (e.g., port 3306/MySQL) - should FAIL with timeout
timeout 3 curl telnet://10.0.0.1:3306 2>&1 || echo "Connection blocked (expected)"
```

**Expected Results:**
- HTTP, HTTPS, DNS, ICMP: ✅ **Success** (firewall allows)
- Other ports/protocols: ❌ **Timeout** (firewall blocks)

### Viewing Firewall Logs (Optional)

Logging is not enabled by default in the instructor template. To enable CloudWatch logging post-deployment:

```bash
# Enable ALERT and FLOW logging
aws network-firewall update-firewall-policy \
  --update-token <token-from-describe> \
  --firewall-policy-arn arn:aws:network-firewall:us-east-1:ACCOUNT:firewall-policy/nfw-lab-policy \
  --region us-east-1
```

Then view logs:
```bash
aws logs tail /aws/network-firewall/nfw-lab --follow
```

---

## Cleanup

### Complete Cleanup (All Resources)

```bash
# Make script executable
chmod +x lab-cleanup.sh

# Delete all student stacks and instructor stacks
export OU_ID="ou-xxxx-yyyyyyyy"  # Or use ACCOUNT_IDS instead
./lab-cleanup.sh --delete-instructor

# Alternatively, with explicit options:
./lab-cleanup.sh \
  --delete-instructor \
  --ou-id ou-xxxx-yyyyyyyy \
  --stackset-name nfw-student-min \
  --regions "us-east-1 eu-west-2 ap-southeast-1"
```

### Partial Cleanup (Student VPCs Only)

```bash
# Keep instructor stacks, delete only student VPCs
./lab-cleanup.sh --ou-id ou-xxxx-yyyyyyyy
```

---

## Troubleshooting

### Issue: VPC Endpoint Association Fails

**Cause**: Firewall endpoint not available in the target AZ.

**Solution**:
- Ensure firewall is deployed in **AZ-a** (same as student subnet)
- Check firewall status: `aws ec2 describe-network-interfaces --filters "Name=description,Values=*firewall*"`

### Issue: EC2 Instance Connect Endpoint Won't Connect

**Cause**: Security group misconfiguration or endpoint not ready.

**Solution**:
1. Verify EIC endpoint is created and in "available" state:
   ```bash
   aws ec2 describe-instance-connect-endpoints \
     --region us-east-1 \
     --filters "Name=vpc-id,Values=vpc-xxxx"
   ```
2. Verify instance security group allows inbound SSH (port 22) from EIC security group:
   ```bash
   aws ec2 describe-security-groups \
     --group-ids sg-xxxx \
     --region us-east-1
   ```
3. Verify EIC endpoint is in protected subnet (10.1.1.0/24)
4. Check browser console for permission errors (may need IAM policy for ec2-instance-connect:OpenTerminal)

### Issue: Firewall Tests Fail or All Traffic Blocked

**Cause**: Route table misconfiguration or firewall rules too restrictive.

**Solution**:
1. Verify routes in protected subnet:
   ```bash
   aws ec2 describe-route-tables \
     --filters "Name=association.subnet-id,Values=subnet-xxxx" \
     --region us-east-1 \
     --query 'RouteTables[0].Routes'
   ```
   Should show: `0.0.0.0/0 → vpce-xxxx` (firewall endpoint)

2. Verify routes in firewall subnet:
   ```bash
   aws ec2 describe-route-tables \
     --filters "Name=route-table-id,Values=rtb-xxxx" \
     --region us-east-1 \
     --query 'Routes'
   ```
   Should show: `0.0.0.0/0 → igw-xxxx` (Internet Gateway)

3. Verify IGW edge route table exists and is associated:
   ```bash
   aws ec2 describe-route-tables \
     --filters "Name=tag:Name,Values=*igw-rt*" \
     --region us-east-1
   ```

4. Check firewall rule group is attached:
   ```bash
   aws network-firewall describe-firewall-policy \
     --firewall-policy-arn arn:aws:network-firewall:us-east-1:ACCOUNT:firewall-policy/nfw-lab-policy
   ```

### Issue: CloudWatch Logs Not Appearing (If Enabled)

**Cause**: Logging not enabled, configuration not applied, or firewall not processing traffic.

**Solution**:
1. Verify logging configuration:
   ```bash
   aws network-firewall describe-logging-configuration \
     --firewall-arn arn:aws:network-firewall:us-east-1:123456789012:firewall/nfw-lab
   ```
2. Ensure traffic is reaching firewall (check route tables)
3. Wait 1-2 minutes for first logs to appear

---

## Security Considerations

- **No Inbound Access**: Instances have no inbound rules except from EIC endpoint
- **No Public IPs**: All communication through VPC endpoints and internal routing
- **Minimal Permissions**: IAM role only needs ec2-instance-connect permissions for EIC
- **Ephemeral Lab**: Resources are temporary; logging retention is configurable if enabled
- **Bidirectional Inspection**: Network Firewall performs deep packet inspection on outbound AND return traffic
- **Firewall Bypass**: SSH access via EIC endpoint bypasses the firewall (intentional for management)

---

## Cost Estimation (30-minute lab)

| Component | Cost | Duration |
|-----------|------|----------|
| Network Firewall | ~$30/region/month | 30 min ≈ $0.02 |
| VPC Endpoints (3 per student) | ~$7.30/region/month per endpoint | 30 min ≈ $0.007 |
| EC2 t3.micro | ~$9.50/month | 30 min ≈ $0.005 |
| CloudWatch Logs (if enabled) | ~$0.50/GB stored | Minimal (~$0.01) |
| **Total per Student/Region** | | **~$0.04** |

For 100 students × 3 Regions = **~$12 total lab cost** (30 minutes).

---

## References

- [AWS Network Firewall Documentation](https://docs.aws.amazon.com/network-firewall/)
- [CloudFormation StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets.html)
- [VPC Endpoint Associations](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)

---

## Support & Questions

For issues or improvements:
1. Review CloudFormation events in AWS Console
2. Check CloudWatch Logs for errors (if enabled)
3. Verify AWS CLI credentials: `aws sts get-caller-identity`
4. Consult AWS Support (if using AWS Support Plan)

---

**Lab Version**: 1.0  
**Last Updated**: March 2026  
**Tested Regions**: us-east-1, eu-west-2, ap-southeast-1  
**Tested with**: AWS CLI v2, CloudFormation v2, Network Firewall GA
