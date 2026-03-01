# Student Lab Deployment Guide
## AWS Network Firewall VPC Endpoint Association Lab

---

## 📋 Before You Start

**Your instructor has set up a shared AWS Network Firewall** that will inspect all your lab traffic. You'll now deploy your own **isolated student VPC** that routes through this shared firewall via VPC Endpoint Association.

### What You'll Receive from Your Instructor

1. **AWS Account Access**: A dedicated student AWS account (or sub-account)
2. **FirewallArn**: The ARN of the instructor's shared Network Firewall (example below)
3. **Target Regions**: us-east-1, eu-west-2, or ap-southeast-1 (your instructor specifies)
4. **Lab Template**: `nfw-student-min.yaml` (CloudFormation template)

---

## 🔑 Step 1: Identify Your Unique Student ID

**CRITICAL**: Each student MUST use a unique identifier to avoid resource conflicts with other students.

### Option A: Use Your Student Username (Recommended)
```bash
STUDENT_ID="student001"           # Replace with your actual student username/ID
STUDENT_ID="jsmith"               # Example: your name or initials
STUDENT_ID="user-123456"          # Example: your assigned user ID
```

### Option B: Use Your Email (First Part)
```bash
STUDENT_ID="john.smith"           # From john.smith@example.com
STUDENT_ID="jsmith"               # Shortened version
```

### naming Rules
- Use **alphanumerics and hyphens only** (a-z, 0-9, -)
- NO spaces, underscores, or special characters
- 3-20 characters recommended
- All lowercase

**Example Valid Student IDs**:
```
student-001
jsmith
lab-user-42
john-s
aws-student-1
```

---

## 🏗️ Step 2: Get the Instructor's Firewall ARN

Your instructor will provide this in one of these formats:

### From Your Instructor (Email/Chat)
```
FirewallArn: arn:aws:network-firewall:us-east-1:123456789012:firewall/nfw-lab-us-east-1
```

### Or Query It Yourself (If You Have Access)
```bash
# List all firewalls in the shared instructor account
aws network-firewall list-firewalls \
  --region us-east-1

# Copy the FirewallArn from the output
# Example output: arn:aws:network-firewall:us-east-1:123456789012:firewall/nfw-lab
```

**Save this value**, you'll need it for Step 4.

---

## 📄 Step 3: Download the Student Template

Your instructor provides: `nfw-student-min.yaml`

**Location**: Same repository/folder where you found these instructions

**File Contents**: Contains all the CloudFormation resources needed:
- Student VPC (10.1.0.0/16)
- Subnet in AZ-a (10.1.1.0/24)
- Route Table connected to Firewall
- 3 SSM VPC Endpoints (for secure access)
- EC2 t3.micro test instance
- IAM role with SSM permissions
- Security groups

---

## 🚀 Step 4: Deploy Your Student Stack

### 4a. Set Your Variables

```bash
# YOUR STUDENT ID (use your unique identifier from Step 1)
STUDENT_ID="student-001"          # ← REPLACE WITH YOUR ID!

# INSTRUCTOR'S FIREWALL ARN (from Step 2)
FIREWALL_ARN="arn:aws:network-firewall:us-east-1:123456789012:firewall/nfw-lab"
# ↑ REPLACE WITH ACTUAL ARN FROM YOUR INSTRUCTOR

# YOUR REGION (choose one)
REGION="us-east-1"               # ← Pick your region

# OPTIONAL: Custom VPC CIDR (advanced, leave default if unsure)
STUDENT_VPC_CIDR="10.1.0.0/16"
```

### 4b. Validate Your Credentials

```bash
# Verify you can access AWS
aws sts get-caller-identity --region ${REGION}

# Expected output shows your AWS account ID and user/role name
# If error: Check your AWS credentials are configured
```

### 4c. Deploy the CloudFormation Stack

```bash
# Build your unique stack name using your Student ID
STACK_NAME="nfw-lab-${STUDENT_ID}"

# Deploy the stack
aws cloudformation deploy \
  --region ${REGION} \
  --stack-name ${STACK_NAME} \
  --template-file nfw-student-min.yaml \
  --parameter-overrides \
    LabName=${STUDENT_ID} \
    FirewallArn=${FIREWALL_ARN} \
    StudentVpcCIDR=${STUDENT_VPC_CIDR} \
  --capabilities CAPABILITY_NAMED_IAM

# Expected output:
# Waiting for changeset to be created..
# Waiting for stack creation to complete
# Successfully created/updated stack - nfw-lab-student-001 in region us-east-1
```

**Deployment Time**: ~5-10 minutes (mostly waiting for EC2 instance)

---

## ✅ Step 5: Verify Your Deployment

### 5a. Check Stack Status in AWS Console

```bash
# Get stack status from AWS CLI
aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'Stacks[0].StackStatus' \
  --output text

# Expected output: CREATE_COMPLETE
```

### 5b. List Your Resources

```bash
aws cloudformation list-stack-resources \
  --stack-name ${STACK_NAME} \
  --region ${REGION}

# Should show:
# - StudentVpc
# - StudentSubnet
# - StudentRouteTable
# - FirewallEndpointAssociation
# - SsmEndpoint (3 of these)
# - StudentTestInstance
# - InstanceSecurityGroup
# - SsmInstanceRole
```

### 5c. Get Your EC2 Instance ID

```bash
# Retrieve outputs from your stack
aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'Stacks[0].Outputs' \
  --output table

# Look for "TestInstanceId" - this is your lab instance
# Example: i-0123456789abcdef0
```

### 5d. Verify Instance is Running

```bash
# Get your instance details
INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'Stacks[0].Outputs[?OutputKey==`TestInstanceId`].OutputValue' \
  --output text)

# Check instance status
aws ec2 describe-instance-status \
  --instance-ids ${INSTANCE_ID} \
  --region ${REGION}

# Expected Status Checks: 2/2 passed
```

---

## 🔐 Step 6: Access Your Lab Instance

### Option A: Via AWS Console (Easiest for Beginners)

1. **Open AWS Console** → Sign in with your student account
2. **Go to**: Systems Manager → Fleet Manager → Nodes
3. **Find your instance**: Look for `nfw-lab-student-001-instance` (with your Student ID)
4. **Click**: Select instance → **Start Session** button
5. **Result**: Browser-based terminal opens (no SSH keys needed!)

### Option B: Via AWS CLI

```bash
# Start a Session Manager session to your instance
aws ssm start-session \
  --target ${INSTANCE_ID} \
  --region ${REGION}

# You'll see a prompt like:
# sh-4.2$ 
# You're now connected to your EC2 instance!
```

---

## 🧪 Step 7: Run Lab Exercises

Once connected to your instance, try these commands:

### Exercise 1: DNS Query (Triggers Firewall)
```bash
# Query Google's DNS servers - this goes through the firewall
dig @8.8.8.8 amazon.com

# Expected output: Query successful (shows amazon.com IP addresses)
# Firewall is monitoring this traffic!
```

### Exercise 2: HTTPS Connectivity Test
```bash
# Test HTTPS to Google
curl -I https://www.google.com

# Expected output: HTTP/2 200 OK (or similar)
# Shows successful HTTPS connection through firewall
```

### Exercise 3: HTTP Test
```bash
# Test HTTP to example.com
curl -I http://example.com

# Expected output: HTTP/1.1 200 OK
```

### Exercise 4: Check Instance Metadata
```bash
# Verify your instance can reach AWS metadata service
curl http://169.254.169.254/latest/meta-data/

# Shows instance metadata is accessible
```

---

## 📊 Step 8: Monitor Traffic in CloudWatch (Optional)

### View Firewall Logs

Logging is not enabled by default in the instructor template. If your instructor
has enabled CloudWatch logging, you can see YOUR traffic:

```bash
# View alert logs (rule violations)
aws logs tail /aws/network-firewall/alert \
  --follow \
  --region ${REGION}

# View flow logs (all traffic)
aws logs tail /aws/network-firewall/flow \
  --follow \
  --region ${REGION}
```

### Filter for Your Traffic Only

```bash
# Search for traffic from your VPC's subnet
STUDENT_SUBNET_CIDR="10.1.1.0/24"

aws logs filter-log-events \
  --log-group-name /aws/network-firewall/flow \
  --filter-pattern "{$.srcaddr = 10.1.1.*}" \
  --region ${REGION}
```

---

## 🗑️ Step 9: Clean Up (When Lab is Done)

### Delete Your Stack

```bash
# Remove all your resources when you're finished
aws cloudformation delete-stack \
  --stack-name ${STACK_NAME} \
  --region ${REGION}

# Verify deletion
aws cloudformation wait stack-delete-complete \
  --stack-name ${STACK_NAME} \
  --region ${REGION}

echo "Stack deleted successfully!"
```

**What Gets Deleted**:
- Your VPC and subnet
- Network interfaces
- Route tables
- EC2 instance
- Security groups
- IAM role
- All CloudWatch endpoints

**What Stays** (Instructor's Resources):
- Shared Network Firewall (used by other students)
- Firewall policy

---

## 📋 Parameter Reference

### What Each Parameter Does

| Parameter | Default | Your Value | Notes |
|-----------|---------|-----------|-------|
| **LabName** | nfw-lab-student | YOUR_STUDENT_ID | MUST be unique! |
| **FirewallArn** | (required) | From instructor | Shared firewall ARN |
| **StudentVpcCIDR** | 10.1.0.0/16 | (can keep default) | Your VPC network |
| **StudentSubnetCIDR** | 10.1.1.0/24 | (can keep default) | Subnet within VPC |
| **InstanceType** | t3.micro | (can keep default) | EC2 instance size |

### Example Parameter Override

```bash
aws cloudformation deploy \
  --region us-east-1 \
  --stack-name nfw-lab-student-001 \
  --template-file nfw-student-min.yaml \
  --parameter-overrides \
    LabName=student-001 \
    FirewallArn=arn:aws:network-firewall:us-east-1:123456789012:firewall/nfw-lab \
    StudentVpcCIDR=10.1.0.0/16 \
    StudentSubnetCIDR=10.1.1.0/24 \
    InstanceType=t3.micro \
  --capabilities CAPABILITY_NAMED_IAM
```

---

## ⚠️ Important: Why Your Student ID Matters

### Naming Ensures Isolation

Each student gets UNIQUE resources to prevent conflicts:

```
Student 001 (student-001):
├─ nfw-lab-student-001-vpc
├─ nfw-lab-student-001-subnet
├─ nfw-lab-student-001-instance
└─ nfw-lab-student-001-sg

Student 002 (student-002):
├─ nfw-lab-student-002-vpc          ← Different!
├─ nfw-lab-student-002-subnet       ← Different!
├─ nfw-lab-student-002-instance     ← Different!
└─ nfw-lab-student-002-sg           ← Different!
```

### What Happens If You Don't Use Unique IDs

❌ **BAD**: Two students use same LabName
```
CloudFormation Error: Stack with name nfw-lab-student already exists
Network Firewall Error: VPC Endpoint Association conflict
Resource Conflict: Cannot create duplicate security groups
```

✅ **GOOD**: Every student has unique LabName
```
Student 001: Stack nfw-lab-student-001 created ✓
Student 002: Stack nfw-lab-student-002 created ✓
Student 003: Stack nfw-lab-student-003 created ✓
(All 300 students can deploy simultaneously!)
```

---

## 🆘 Troubleshooting

### Issue: Instance Won't Connect via Session Manager

**Cause**: EC2 instance still initializing

**Solution**:
```bash
# Wait 2-3 minutes after stack creation completes
# Check instance status
aws ec2 describe-instance-status --instance-ids ${INSTANCE_ID} --region ${REGION}

# Wait for Status Checks: 2/2 passed
```

### Issue: "FirewallArn is invalid"

**Cause**: Incorrect ARN format or wrong account

**Solution**:
```bash
# Verify your FirewallArn matches this format:
# arn:aws:network-firewall:REGION:ACCOUNT_ID:firewall/NAME

# Ask your instructor for the exact ARN
# Check it has correct region (us-east-1, eu-west-2, or ap-southeast-1)
```

### Issue: "Stack with name already exists"

**Cause**: You used same LabName as another student

**Solution**:
```bash
# Choose a NEW, UNIQUE LabName (your Student ID should be different)
# Delete the conflicting stack first:
aws cloudformation delete-stack --stack-name nfw-lab-student --region ${REGION}

# Then redeploy with unique LabName:
aws cloudformation deploy \
  ... \
  --parameter-overrides LabName=YOUR-UNIQUE-ID \
  ...
```

### Issue: CloudFormation Stack Creation Failed

**Check the events**:
```bash
aws cloudformation describe-stack-events \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# Shows which resource failed and why
```

---

## 📝 Quick Reference: All Commands

### Setup
```bash
STUDENT_ID="YOUR_STUDENT_ID"
FIREWALL_ARN="arn:aws:network-firewall:REGION:ACCOUNT:firewall/NAME"
REGION="us-east-1"
STACK_NAME="nfw-lab-${STUDENT_ID}"
```

### Deploy
```bash
aws cloudformation deploy \
  --region ${REGION} \
  --stack-name ${STACK_NAME} \
  --template-file nfw-student-min.yaml \
  --parameter-overrides LabName=${STUDENT_ID} FirewallArn=${FIREWALL_ARN} \
  --capabilities CAPABILITY_NAMED_IAM
```

### Verify
```bash
aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION}
aws cloudformation list-stack-resources --stack-name ${STACK_NAME} --region ${REGION}
```

### Connect
```bash
INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query 'Stacks[0].Outputs[?OutputKey==`TestInstanceId`].OutputValue' --output text)
aws ssm start-session --target ${INSTANCE_ID} --region ${REGION}
```

### Monitor (If Logging Enabled)
```bash
aws logs tail /aws/network-firewall/alert --follow --region ${REGION}
```

### Cleanup
```bash
aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${REGION}
```

---

## 🎓 What You've Learned

After completing this lab, you understand:

✅ VPC Endpoint Associations (shared firewall access)  
✅ Multi-account AWS deployments  
✅ CloudFormation stack automation  
✅ AWS Session Manager (secure shell-less access)  
✅ VPC security and network isolation  
✅ CloudWatch monitoring of traffic  
✅ How to name resources uniquely across 300+ students  

---

## 📞 Getting Help

**Problem**: Template won't deploy  
**Solution**: Check syntax in nfw-student-min.yaml, verify FirewallArn

**Problem**: Instance won't connect  
**Solution**: Wait 3 minutes, check instance status checks = 2/2

**Problem**: CloudWatch logs empty (logging enabled)  
**Solution**: Wait 1-2 minutes for logs to appear, verify traffic flowing through firewall

**Contact**: Your instructor (provide stack name and region)

---

## ✨ Success Checklist

- [ ] Created your unique STUDENT_ID
- [ ] Got FirewallArn from instructor
- [ ] Downloaded nfw-student-min.yaml
- [ ] Ran CloudFormation deploy command
- [ ] Stack shows CREATE_COMPLETE
- [ ] EC2 instance status = running (2/2 checks passed)
- [ ] Connected via Session Manager
- [ ] Ran lab exercises (dig, curl)
- [ ] (Optional) Viewed CloudWatch logs
- [ ] Cleaned up stack when done

**You're ready to begin!** 🚀

---

**Version**: 1.0  
**Last Updated**: March 1, 2026  
**Lab Duration**: ~45 minutes total  
**Difficulty**: Beginner-Intermediate
