# AWS Network Firewall Multi-Account Lab - TechSummit Sec5

## Overview

This lab demonstrates a **scalable, multi-account AWS Network Firewall deployment** designed for instructor-led training with minimal infrastructure footprint. It showcases how to deploy a shared Network Firewall that serves multiple student accounts via VPC Endpoint Associations, with centralized logging and control.

### Key Features

- **Shared Infrastructure**: One Network Firewall per Region per account, serving multiple students via VPC Endpoint Associations
- **No EC2 Quota Issues**: Uses efficient VPC endpoint architecture instead of individual endpoints per student
- **Secure Access**: Session Manager for instance access (no SSH keys, no public IPs required)
- **Multi-Region**: Deployable across us-east-1, eu-west-2, ap-southeast-1
- **Automated Cleanup**: Scripted teardown of all resources
- **30-Minute Deployment**: Fully operational lab in under 30 minutes

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
│  │  │  │  │  - ALERT on DNS │    │         │                     │ │ │  │
│  │  │  │  └─────────────────┘    │         │                     │ │ │  │
│  │  │  └─────────────────────────┘         └─────────────────────┘ │ │  │
│  │  │                                                                │  │ │
│  │  └────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                      │ │
│  │  Logging:                                                            │ │
│  │  ┌─────────────────────────┐  ┌──────────────────────────────┐       │ │
│  │  │  CloudWatch Log Group   │  │  CloudWatch Log Group        │       │ │
│  │  │  /aws/network-firewall/ │  │  /aws/network-firewall/flow  │       │ │
│  │  │  alert                  │  │                              │       │ │
│  │  └─────────────────────────┘  └──────────────────────────────┘       │ │
│  │                                                                      │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │  Student Account(s)                                                  │ │
│  │                                                                      │ │
│  │  ┌─────────────────────────────────────────────────────────────┐     │ │
│  │  │  Student VPC (10.1.0.0/16) - Availability Zone A            │   │ │
│  │  │                                                             │   │ │
│  │  │  ┌──────────────────────────────────────────────────────┐   │   │ │
│  │  │  │  Student Subnet (10.1.1.0/24)                        │   │   │ │
│  │  │  │                                                      │   │   │ │
│  │  │  │  ┌────────────────────────────────────────────────┐  │   │   │ │
│  │  │  │  │  Route Table                                   │  │   │   │ │
│  │  │  │  │  0.0.0.0/0 ──► VPC Endpoint Association (FW)   │  │   │   │ │
│  │  │  │  └────────────────────────────────────────────────┘  │   │   │ │
│  │  │  │                                                      │   │   │ │
│  │  │  │  ┌──────────────┐                    ┌───────────┐   │   │   │ │
│  │  │  │  │  EC2 Test    │                    │  SSM VPC  │   │   │   │ │
│  │  │  │  │  Instance    │◄──────────────────►│  Endpoints│   │   │   │ │
│  │  │  │  │  (t3.micro)  │  Session Manager   │  - ssm    │   │   │   │ │
│  │  │  │  │              │                    │  - ec2msg │   │   │   │ │
│  │  │  │  └──────────────┘                    │  - ssmmsg │   │   │   │ │
│  │  │  │                                      └───────────┘   │   │   │ │
│  │  │  └──────────────────────────────────────────────────────┘   │   │ │
│  │  │                                                             │   │ │
│  │  │  VPC Endpoint Association to Shared Network Firewall        │   │ │
│  │  │  (Connected to Instructor's Firewall Endpoint)              │   │ │
│  │  │                                                             │   │ │
│  │  └─────────────────────────────────────────────────────────┘   │   │
│  │                                                                    │ │
│  │  [Multiple student accounts can be deployed with identical setup]  │ │
│  │                                                                      │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow

```
Student EC2           DNS Query (UDP/53)        Shared Network Firewall
   │                        │                           │
   ├──► dig @8.8.8.8 ────────┤                          │
   │    amazon.com           │◄─────────────────────────┤
   │                         │  VPC Endpoint Association │
   │                         │  (Stateful Inspection)    │
   │                         │  Action: ALERT            │
   │◄────── Response ────────┤                          │  CloudWatch
   │                         │                          │◄──── ALERT Logs
   │                         │                          │      (UDP/53)
   │                         │                          │─► Flow Logs
```

---

## Components

### 1. **nfw-instructor.yaml** - Shared Network Firewall Infrastructure

Deployed once **per account per Region** (management overhead = minimal).

**Resources Created:**
- **Firewall VPC** (10.0.0.0/16, single-AZ)
  - Subnet in AZ-a for firewall placement
  - Route to Internet Gateway
  - Network Firewall with stateful rule group
- **Stateful Rule**: ALERT on UDP/53 (DNS queries)
- **CloudWatch Log Groups**:
  - `/aws/network-firewall/alert` - Rule hits
  - `/aws/network-firewall/flow` - All traffic flows

**Parameters:**
- `FirewallName`: Name of the firewall (default: `nfw-lab`)
- `FirewallVpcCIDR`: VPC CIDR block (default: `10.0.0.0/16`)
- `FirewallSubnetCIDR`: Firewall subnet CIDR (default: `10.0.1.0/24`)

**Outputs:**
- `FirewallArn`: Used by student templates
- `FirewallEndpointId`: Firewall endpoint identifier
- `AlertLogGroupName` / `FlowLogGroupName`: CloudWatch log group names

---

### 2. **nfw-student-min.yaml** - Per-Student Lab Environment

Deployed via **CloudFormation StackSets** (service-managed) across target accounts and Regions.

**Resources Created per Student:**
- **Student VPC** (10.1.0.0/16, configurable)
  - Single-AZ subnet (AZ-a) aligned with firewall
  - Route to firewall via VPC Endpoint Association
- **VPC Endpoint Association**: Connects to shared firewall
- **SSM Interface Endpoints** (no public IPs needed):
  - `com.amazonaws.region.ssm`
  - `com.amazonaws.region.ec2messages`
  - `com.amazonaws.region.ssmmessages`
- **EC2 Test Instance** (t3.micro):
  - Pre-installed: `curl`, `dig`, `wget`
  - Accessible via Session Manager only

**Parameters:**
- `FirewallArn`: ARN from instructor stack
- `LabName`: Lab identifier (default: `nfw-lab-student`)
- `StudentVpcCIDR`: Student VPC CIDR (default: `10.1.0.0/16`)
- `InstanceType`: EC2 type (default: `t3.micro`)

**Scalability:**
- Default quota: 300 VPC Endpoint Associations per Region per firewall
- Supports 300+ students per Region on a single firewall

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

1. **Login to AWS Console** in your assigned student account
2. Navigate to **Systems Manager** → **Fleet Manager** → **Nodes**
3. Select your instance (e.g., `nfw-lab-student-instance`)
4. Click **Start session** (no SSH keys needed!)

### Lab Exercise: Trigger Network Firewall Rules

Once connected to your EC2 instance via Session Manager:

```bash
# Test DNS query (UDP/53) - triggers ALERT rule
dig @8.8.8.8 amazon.com

# Test HTTPS connectivity
curl -I https://www.google.com

# Test HTTP connectivity
curl -I http://example.com

# Monitor rules in real-time
# (In a separate window/terminal)
aws logs tail /aws/network-firewall/alert --follow --region us-east-1
aws logs tail /aws/network-firewall/flow --follow --region us-east-1
```

### Viewing Firewall Logs

**In AWS Console** or **CLI**:

```bash
# View recent alert logs
aws logs tail /aws/network-firewall/alert \
  --region us-east-1 \
  --since 5m \
  --format short

# View flow logs (all traffic)
aws logs tail /aws/network-firewall/flow \
  --region us-east-1 \
  --since 5m \
  --max-items 10

# Search for specific traffic patterns
aws logs filter-log-events \
  --log-group-name /aws/network-firewall/alert \
  --filter-pattern "UDP" \
  --region us-east-1
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

### Issue: Session Manager Won't Connect

**Cause**: Missing SSM endpoints or IAM role issue.

**Solution**:
1. Verify SSM endpoints exist in student VPC:
   ```bash
   aws ec2 describe-vpc-endpoints --region us-east-1 \
     --filters "Name=vpc-id,Values=vpc-xxxx"
   ```
2. Verify instance IAM role has `AmazonSSMManagedInstanceCore` policy
3. Check instance health: Systems Manager → Fleet Manager → Nodes

### Issue: CloudWatch Logs Not Appearing

**Cause**: Logging configuration not applied or firewall not processing traffic.

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

- **No Inbound Access**: Instances have no inbound rules; only Session Manager access
- **No Public IPs**: All communication through VPC endpoints (no Internet-facing services)
- **Minimal Permissions**: IAM roles grant only SSM permissions
- **Ephemeral Lab**: Resources are temporary; CloudWatch Logs retention = 30 days
- **Stateful Inspection**: Network Firewall performs deep packet inspection on all traffic

---

## Cost Estimation (30-minute lab)

| Component | Cost | Duration |
|-----------|------|----------|
| Network Firewall | ~$30/region/month | 30 min ≈ $0.02 |
| VPC Endpoints (3 per student) | ~$7.30/region/month per endpoint | 30 min ≈ $0.007 |
| EC2 t3.micro | ~$9.50/month | 30 min ≈ $0.005 |
| CloudWatch Logs | ~$0.50/GB stored | Minimal (~$0.01) |
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
2. Check CloudWatch Logs for errors
3. Verify AWS CLI credentials: `aws sts get-caller-identity`
4. Consult AWS Support (if using AWS Support Plan)

---

**Lab Version**: 1.0  
**Last Updated**: March 2026  
**Tested Regions**: us-east-1, eu-west-2, ap-southeast-1  
**Tested with**: AWS CLI v2, CloudFormation v2, Network Firewall GA
