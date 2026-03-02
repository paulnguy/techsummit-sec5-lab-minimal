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
STUDENT_ID="student001"           # Replace with your actual student username/ID/Okta login
STUDENT_ID="jsmith"               # Example: your name or initials
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
- Student VPC (10.1.0.0/16) with 2 subnets for bidirectional inspection
- Protected Subnet (10.1.1.0/24) with EC2 instance
- Firewall Subnet (10.1.2.0/24) with firewall endpoint association
- EC2 Instance Connect (EIC) Endpoint for browser-based SSH access
- Internet Gateway for egress + IGW edge routes for return traffic inspection
- EC2 t3.micro test instance (curl, dig, wget pre-installed)
- Security groups for EIC and instance communication

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
# - ProtectedSubnet (10.1.1.0/24)
# - FirewallSubnet (10.1.2.0/24)
# - Firewall Endpoint Association
# - Internet Gateway
# - Route Tables (Protected, Firewall, IGW Edge)
# - EIC Endpoint
# - EC2 Instance
# - Security Groups (Instance, EIC)
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

### Option A: Via EC2 Instance Connect (EIC) - Recommended

1. **Open AWS Console** → Sign in with your student account
2. **Go to**: EC2 → Instances
3. **Find your instance**: Look for `nfw-lab-student-001-instance` (with your Student ID)
4. **Click**: Select instance → **Connect** button (top right)
5. **Go to**: **EC2 Instance Connect** tab
6. **Click**: **Connect** button
7. **Result**: Browser-based terminal opens (no SSH keys needed!)

### Option B: Via Systems Manager Session Manager (Alternative)

```bash
# Start a Session Manager session to your instance
aws ssm start-session \
  --target ${INSTANCE_ID} \
  --region ${REGION}

# You'll see a prompt like:
# sh-4.2$ 
# You're now connected to your EC2 instance!
```

### Why Two Methods?

- **EIC**: Browser-based, faster connection, uses EC2 Instance Connect Endpoint
- **Session Manager**: Alternative method, requires SSM role (both enable secure access)
- **Both bypass the firewall** (SSH port 22 goes directly via EIC/SSM, not inspected)

---

## 🧪 Step 7: Run Lab Exercises

Once connected to your instance, try these commands:

### About Bidirectional Inspection

Your traffic is inspected in BOTH directions:
- **Outbound**: EC2 instance → Firewall → Internet Gateway → Internet
- **Return**: Internet → Internet Gateway → Firewall (via IGW edge route table) → EC2 instance

The firewall evaluates rules on outbound traffic (curl/dig requests) AND return responses (HTTP success, DNS replies).

### Exercise 1: DNS Query (UDP 53 - Allowed)
```bash
# Query Google's DNS servers - this OUTBOUND goes through the firewall
dig @8.8.8.8 amazon.com

# Expected output: Query successful (shows amazon.com IP addresses)
# Both the request (outbound) and response (return) are inspected!
```

### Exercise 2: HTTPS Connectivity Test (TCP 443 - Allowed)
```bash
# Test HTTPS to Google
curl -I https://www.google.com

# Expected output: HTTP/2 200 OK (or similar)
# Shows successful HTTPS connection through firewall
# Return traffic is also inspected via IGW edge route table
```

### Exercise 3: HTTP Test (TCP 80 - Allowed)
```bash
# Test HTTP to example.com
curl -I http://example.com

# Expected output: HTTP/1.1 200 OK
```

### Exercise 4: ICMP Test (Ping - Allowed)
```bash
# Test ICMP (ping)
ping -c 3 8.8.8.8

# Expected output: Ping replies from 8.8.8.8
# ICMP is allowed by the firewall
```

### Exercise 5: Test Blocked Traffic (Port 3306 - Blocked)
```bash
# Test connection to a blocked port (MySQL)
timeout 3 curl telnet://10.0.0.1:3306 2>&1 || echo "Connection blocked (expected)"

# Expected: Connection timeout or rejection
# This port is blocked by the firewall's denial rules
```

### Exercise 6: Check Instance Metadata
```bash
# Verify your instance can reach AWS metadata service
curl http://169.254.169.254/latest/meta-data/

# Shows instance metadata is accessible
# Note: Metadata requests bypass the firewall (not routed to firewall)
```

---

## 📊 Step 8: Monitor Traffic in CloudWatch (Optional)

### View Firewall Logs

Logging is not enabled by default in the instructor template. If your instructor
has enabled CloudWatch logging, you can see YOUR traffic:

```bash
# View alert logs (if enabled)
aws logs tail /aws/network-firewall/alert \
  --follow \
  --region ${REGION}

# View flow logs (all traffic, bidirectional)
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
- Your VPC and subnets
- Network interfaces
- Route tables (including firewall and IGW edge routes)
- Internet Gateway
- EC2 instance
- EIC Endpoint
- Security groups
- All endpoint associations

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

### Issue: EC2 Instance Connect Won't Connect

**Cause**: Instance still initializing or EIC endpoint not ready

**Solution**:
```bash
# Wait 2-3 minutes after stack creation completes
# Check instance status
aws ec2 describe-instance-status --instance-ids ${INSTANCE_ID} --region ${REGION}

# Wait for Status Checks: 2/2 passed

# Verify EIC endpoint exists and is available
aws ec2 describe-instance-connect-endpoints \
  --region ${REGION} \
  --query 'InstanceConnectEndpoints[*].[InstanceConnectEndpointId,State]'

# Should show: State = available
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
# Method 1: EC2 Instance Connect (Recommended)
# Use AWS Console: EC2 → Instances → Select instance → Connect → EC2 Instance Connect

# Method 2: AWS CLI with EIC
INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query 'Stacks[0].Outputs[?OutputKey==`TestInstanceId`].OutputValue' --output text)
aws ec2-instance-connect open-tunnel --instance-id ${INSTANCE_ID} --region ${REGION}

# Method 3: Session Manager (Alternative)
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
✅ EC2 Instance Connect (browser-based secure access)  
✅ AWS Session Manager (alternative secure shell-less access)  
✅ Bidirectional firewall inspection (outbound + return traffic)  
✅ IGW edge route tables for return traffic inspection  
✅ VPC security and network isolation  
✅ Optional CloudWatch monitoring of traffic  
✅ How to name resources uniquely across 300+ students  

---

## 📞 Getting Help

**Problem**: Template won't deploy  
**Solution**: Check syntax in nfw-student-min.yaml, verify FirewallArn format and region

**Problem**: Instance won't connect via EIC  
**Solution**: Wait 3 minutes, check EIC endpoint status = available

**Problem**: Firewall tests fail (curl/dig hang or timeout)  
**Solution**: Verify route tables point to firewall endpoint, check firewall rule group is attached

**Problem**: All traffic blocked  
**Solution**: Check protected route table has 0.0.0.0/0 → firewall endpoint route

**Problem**: CloudWatch logs empty (logging enabled)  
**Solution**: Wait 1-2 minutes for logs to appear, verify traffic flowing through firewall

**Contact**: Your instructor (provide stack name, region, and error message)

---

## ✨ Success Checklist

- [ ] Created your unique STUDENT_ID
- [ ] Got FirewallArn from instructor
- [ ] Downloaded nfw-student-min.yaml
- [ ] Ran CloudFormation deploy command
- [ ] Stack shows CREATE_COMPLETE
- [ ] EC2 instance status = running (2/2 checks passed)
- [ ] Connected via EC2 Instance Connect Endpoint (or Session Manager)
- [ ] Ran lab exercises (dig, curl, ping)
- [ ] Tested both allowed (HTTP/HTTPS/DNS) and blocked traffic
- [ ] (Optional) Viewed CloudWatch logs for bidirectional inspection
- [ ] Cleaned up stack when done

**You're ready to begin!** 🚀

---

**Version**: 1.0  
**Last Updated**: March 1, 2026  
**Lab Duration**: ~45 minutes total  
**Difficulty**: Beginner-Intermediate
