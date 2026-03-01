Ready‑to‑run lab bundle that matches your constraints:

Regions: us-east-1, eu-west-2, ap-southeast-1
Connectivity: SSM Session Manager (no NAT, no public IPs) via VPC Interface Endpoints
No EC2 quota checks (kept out as requested)

What you get:

Instructor stack (per Region/per account) – Builds the shared Network Firewall VPC (single‑AZ), policy, a stateful “ALERT on UDP/53” rule, firewall subnet & route to IGW. Logging is optional and can be enabled post‑deploy.
Student StackSet template – For each student: VPC + subnet + route table, VPC Endpoint Association to your shared firewall, default route → firewall endpoint, SSM interface endpoints (ssm, ec2messages, ssmmessages) and a t3.micro test instance with SSM only.
Runbook + cleanup – Step‑by‑step instructions to deploy across 3 accounts / 3 Regions with CloudFormation StackSets (service‑managed), plus an AWS CLI cleanup script.

Why this scales & fits 30 minutes

You deploy one firewall per Region per account (under the default quota of 5 per Region). Students share that firewall via VPC endpoint associations (default 300 per Region, enough for 300 learners).
Student VPCs route 0.0.0.0/0 to the firewall endpoint (supported by AWS::EC2::Route with VpcEndpointId).
ALERT + FLOW logging is optional and can be enabled post‑deploy if desired.,, 
Session Manager requires only the three SSM interface endpoints (or NAT) and the SSM instance role—no SSH keys or inbound ports. 
VPC Endpoint Associations are the supported way to put firewall endpoints into other VPCs, as long as the firewall already has a primary endpoint in that AZ. We standardize on AZ‑a for simplicity. 
1) Instructor stack – nfw-instructor.yaml

Deploy once per account per Region (us-east-1, eu-west-2, ap-southeast-1).
This stack creates:

A firewall VPC with a firewall subnet (AZ‑a) + route to IGW
Network Firewall with a stateful rule that ALERTs on UDP/53
Optional CloudWatch logging (enable post‑deploy)
Outputs: FirewallArn, FirewallId, FirewallAzName, FirewallVpcId

AWSTemplateFormatVersion: '2010-09-09'

Description: Instructor shared Network Firewall (single-AZ) + logging for lab

Parameters:

FirewallName:

Type: String

Default: nfw-lab

AllowedPattern: '^[A-Za-z0-9-]+

Notes

We pick the first AZ in each Region so you can keep student subnets in the same AZ (a requirement for placing the association/endpoint in that AZ). 
Network Firewall logging is optional and can be enabled post‑deploy if needed. 
2) Student StackSet template – nfw-student-min.yaml

Deployed via CloudFormation StackSets (service‑managed) into target accounts & Regions.
Creates one mini‑lab per student: VPC, subnet (AZ‑a), RT, VPC Endpoint Association to your shared firewall, default route → firewall endpoint, SSM VPC endpoints, and an EC2 instance with SSM only.

AWSTemplateFormatVersion: '2010-09-09'

Description: Minimal per-student VPC + EC2 + SSM endpoints + NFW endpoint association (single-AZ)

Parameters:

LabName:

Type: String

Default: nfw-lab-student

AllowedPattern: '^[A-Za-z0-9-]+

Notes

AWS::NetworkFirewall::VpcEndpointAssociation returns EndpointId, and AWS::EC2::Route supports using VpcEndpointId as the route target—so we can wire 0.0.0.0/0 → vpce‑… cleanly in CFN. 
We create the three SSM interface endpoints to use Session Manager without NAT/public IPs, per the documented prerequisites/endpoints.
3) Runbook (multi‑account / multi‑Region in ~30 minutes)
A) Prereqs (once)
You have AWS Organizations and can use CloudFormation StackSets (service‑managed) from the management or delegated admin account. Enable trusted access and (optionally) register a delegated admin. 
Create or pick three student accounts and organize them under an OU.
Access: students will use Session Manager from the console—no SSH keys. 
B) Deploy the Instructor stack in each account/Region

For each lab account in us-east-1, eu-west-2, ap-southeast-1:

aws cloudformation deploy </span>

--region us-east-1 </span>

--stack-name nfw-instructor </span>

--template-file nfw-instructor.yaml </span>

--capabilities CAPABILITY_NAMED_IAM </span>

--parameter-overrides FirewallName=nfw-lab-east

# Repeat in eu-west-2, ap-southeast-1 (change FirewallName if you like)

Record the FirewallArn output (per Region/account).

If each Region has its own dedicated lab account, repeat these steps in each account/Region pair.

C) Create the Student StackSet (service‑managed)

From the management (or delegated admin) account:

Create StackSet named nfw-student-min with template nfw-student-min.yaml.
Parameters: set LabName (e.g., nfw-lab), FirewallArn per Region (StackSets lets you override parameters per stack instance/Region). 
Targets: choose the OU that holds the 3 lab accounts (or list the three accounts).
Regions: us-east-1, eu-west-2, ap-southeast-1.
Operation preferences:
Failure tolerance: small (e.g., 5)
Max concurrent accounts: moderate (e.g., 25–50)
Region order: your preference

Within a few minutes, each student account/Region will have a VPC + EC2 that routes egress via your shared firewall endpoint.

D) Student instructions (2 lines)

Console → Systems Manager → Fleet Manager → Nodes → select your instance → Start session (or EC2 → Instance → Connect → Session Manager).

Run:

dig @8.8.8.8 amazon.com      # triggers ALERT (UDP/53)

curl -I https://www.google.com

Optional: If logging is enabled post‑deploy, use CloudWatch Logs to see rule hits/flows. 

4) Cleanup script – lab-cleanup.sh (AWS CLI)
Deletes StackSet instances (student side) and optionally deletes the instructor stacks.
Run this from your management/delegated admin account.

#!/usr/bin/env bash

set -euo pipefail

STACKSET_NAME="nfw-student-min"

REGIONS=("us-east-1" "eu-west-2" "ap-southeast-1")

OU_ID="<YOUR_OU_ID>"        # or leave empty and list account IDs

ACCOUNT_IDS=("111111111111" "222222222222" "333333333333")  # optional if not using OU

DELETE_INSTRUCTOR=${DELETE_INSTRUCTOR:-false}

echo "[1/3] Deleting StackSet instances (students)..."

if [[ -n "${OU_ID}" ]]; then

aws cloudformation delete-stack-instances </span>

--stack-set-name "${STACKSET_NAME}" </span>

--regions "${REGIONS[@]}" </span>

--deployment-targets OrganizationalUnitIds="${OU_ID}" </span>

--no-retain-stacks

else

aws cloudformation delete-stack-instances </span>

--stack-set-name "${STACKSET_NAME}" </span>

--regions "${REGIONS[@]}" </span>

--deployment-targets Accounts=$(IFS=, ; echo "${ACCOUNT_IDS[*]}") </span>

--no-retain-stacks

fi

aws cloudformation wait stack-set-operation-complete </span>

--stack-set-name "${STACKSET_NAME}" </span>

--operation-id "$(aws cloudformation list-stack-set-operations --stack-set-name "${STACKSET_NAME}" </span>

--query 'Summaries[0].OperationId' --output text)"

echo "[2/3] Deleting StackSet..."

aws cloudformation delete-stack-set --stack-set-name "${STACKSET_NAME}" || true

if [[ "${DELETE_INSTRUCTOR}" == "true" ]]; then

echo "[3/3] Deleting instructor stacks in each Region..."

for r in "${REGIONS[@]}"; do

aws cloudformation delete-stack --region "$r" --stack-name nfw-instructor || true

aws cloudformation wait stack-delete-complete --region "$r" --stack-name nfw-instructor || true

done

else

echo "Instructor stacks preserved (set DELETE_INSTRUCTOR=true to remove)."

fi

echo "Cleanup complete."

Implementation guidance & references
Quotas: default 5 firewalls/Region/account, 300 VPC endpoint associations/Region/account. This design stays within defaults for 300 learners by sharing one firewall per Region and creating one association per student VPC.
VPC Endpoint Association is the supported way to place additional firewall endpoints in other VPCs/AZs (including student VPCs), provided the firewall has a primary endpoint in that AZ.
Routing to the firewall: AWS::EC2::Route supports VpcEndpointId as a target, so 0.0.0.0/0 → vpce-… is valid.
Logging: Optional, enable via Network Firewall console or API after deployment if desired.,
Session Manager: use AmazonSSMManagedInstanceCore and the three interface endpoints (ssm, ec2messages, ssmmessages) to avoid NAT/public IPs.
StackSets: use service‑managed mode (trusted access with Organizations), OU targeting, and per‑Region parameter overrides (for each Region’s FirewallArn). ,
Want me to hand you “paste‑ready” StackSets CLI commands?

I can generate exact create-stack-set + create-stack-instances commands with your OU ID and the three FirewallArn values you’ll get after deploying nfw-instructor.yaml in each Region/account. If you share those ARNs (or want me to parameterize with SSM Parameter Store), I’ll add the commands to your bundle.

VpcCidr:

Type: String

Default: 10.100.0.0/16

FirewallSubnetCidr:

Type: String

Default: 10.100.1.0/24

LogRetentionDays:

Type: Number

Default: 3

MinValue: 1

MaxValue: 3653

Resources:

VPC:

Type: AWS::EC2::VPC

Properties:

CidrBlock: !Ref VpcCidr

EnableDnsSupport: true

EnableDnsHostnames: true

Tags: [{ Key: Name, Value: nfw-lab-vpc }]

IGW:

Type: AWS::EC2::InternetGateway

Properties:

Tags: [{ Key: Name, Value: nfw-lab-igw }]

VpcIgwAttach:

Type: AWS::EC2::VPCGatewayAttachment

Properties:

VpcId: !Ref VPC

InternetGatewayId: !Ref IGW

FirewallSubnet:

Type: AWS::EC2::Subnet

Properties:

VpcId: !Ref VPC

AvailabilityZone: !Select [0, !GetAZs '']

CidrBlock: !Ref FirewallSubnetCidr

Tags: [{ Key: Name, Value: nfw-lab-fw-subnet }]

FirewallRT:

Type: AWS::EC2::RouteTable

Properties:

VpcId: !Ref VPC

Tags: [{ Key: Name, Value: nfw-lab-fw-rt }]

FirewallSubnetAssoc:

Type: AWS::EC2::SubnetRouteTableAssociation

Properties:

SubnetId: !Ref FirewallSubnet

RouteTableId: !Ref FirewallRT

FirewallRTDefault:

Type: AWS::EC2::Route

DependsOn: VpcIgwAttach

Properties:

RouteTableId: !Ref FirewallRT

DestinationCidrBlock: 0.0.0.0/0

GatewayId: !Ref IGW

# Stateful rule group: ALERT on any UDP→53

StatefulDnsAlertRG:

Type: AWS::NetworkFirewall::RuleGroup

Properties:

Capacity: 100

RuleGroupName: !Sub '${FirewallName}-stateful-dns-alert'

Type: STATEFUL

RuleGroup:

RulesSource:

RulesString: |

alert udp any any -> any 53 (msg:"LAB ALERT: UDP DNS"; sid:1000001; rev:1;)

Tags: [{ Key: Name, Value: nfw-lab-stateful-dns-alert }]

FirewallPolicy:

Type: AWS::NetworkFirewall::FirewallPolicy

Properties:

FirewallPolicyName: !Sub '${FirewallName}-policy'

FirewallPolicy:

StatelessDefaultActions:

- aws:forward_to_sfe

StatelessFragmentDefaultActions:

- aws:forward_to_sfe

StatefulRuleGroupReferences:

- ResourceArn: !Ref StatefulDnsAlertRG

Tags: [{ Key: Name, Value: nfw-lab-firewall-policy }]

Firewall:

Type: AWS::NetworkFirewall::Firewall

Properties:

FirewallName: !Ref FirewallName

FirewallPolicyArn: !Ref FirewallPolicy

VpcId: !Ref VPC

SubnetMappings:

- SubnetId: !Ref FirewallSubnet

DeleteProtection: false

FirewallPolicyChangeProtection: false

SubnetChangeProtection: false

Tags: [{ Key: Name, Value: nfw-lab-firewall }]

# Optional logging can be enabled post-deploy (not shown here)

Outputs:

FirewallArn:

Value: !GetAtt Firewall.FirewallArn

Description: ARN of the Network Firewall

FirewallAzName:

Value: !GetAtt FirewallSubnet.AvailabilityZone

Description: AZ used for the firewall endpoints (students must use same AZ)

FirewallId:

Value: !Ref Firewall

FirewallVpcId:

Value: !Ref VPC

Notes

We pick the first AZ in each Region so you can keep student subnets in the same AZ (a requirement for placing the association/endpoint in that AZ).
Network Firewall logging to CloudWatch uses the documented LoggingConfiguration and the log group key logGroup.,
2) Student StackSet template – nfw-student-min.yaml

Deployed via CloudFormation StackSets (service‑managed) into target accounts & Regions.
Creates one mini‑lab per student: VPC, subnet (AZ‑a), RT, VPC Endpoint Association to your shared firewall, default route → firewall endpoint, SSM VPC endpoints, and an EC2 instance with SSM only.

{{1-raw-markdown-db638e6b-0223-4f65-bfc1-df79117d04c5}}

Notes

AWS::NetworkFirewall::VpcEndpointAssociation returns EndpointId, and AWS::EC2::Route supports using VpcEndpointId as the route target—so we can wire 0.0.0.0/0 → vpce‑… cleanly in CFN. ,
We create the three SSM interface endpoints to use Session Manager without NAT/public IPs, per the documented prerequisites/endpoints.
3) Runbook (multi‑account / multi‑Region in ~30 minutes)
A) Prereqs (once)
You have AWS Organizations and can use CloudFormation StackSets (service‑managed) from the management or delegated admin account. Enable trusted access and (optionally) register a delegated admin. ,
Create or pick three student accounts and organize them under an OU.
Access: students will use Session Manager from the console—no SSH keys.
B) Deploy the Instructor stack in each account/Region

For each lab account in us-east-1, eu-west-2, ap-southeast-1:

{{2-raw-markdown-db638e6b-0223-4f65-bfc1-df79117d04c5}}

Record the FirewallArn output (per Region/account).

If each Region has its own dedicated lab account, repeat these steps in each account/Region pair.

C) Create the Student StackSet (service‑managed)

From the management (or delegated admin) account:

Create StackSet named nfw-student-min with template nfw-student-min.yaml.
Parameters: set LabName (e.g., nfw-lab), FirewallArn per Region (StackSets lets you override parameters per stack instance/Region).
Targets: choose the OU that holds the 3 lab accounts (or list the three accounts).
Regions: us-east-1, eu-west-2, ap-southeast-1.
Operation preferences:
Failure tolerance: small (e.g., 5)
Max concurrent accounts: moderate (e.g., 25–50)
Region order: your preference

Within a few minutes, each student account/Region will have a VPC + EC2 that routes egress via your shared firewall endpoint.

D) Student instructions (2 lines)
Console → Systems Manager → Fleet Manager → Nodes → select your instance → Start session (or EC2 → Instance → Connect → Session Manager).
Run: {{3-raw-markdown-db638e6b-0223-4f65-bfc1-df79117d04c5}}
CloudWatch Logs → /aws/network-firewall/alert & /aws/network-firewall/flow to see rule hits/flows.
4) Cleanup script – lab-cleanup.sh (AWS CLI)
Deletes StackSet instances (student side) and optionally deletes the instructor stacks.
Run this from your management/delegated admin account.

{{4-raw-markdown-db638e6b-0223-4f65-bfc1-df79117d04c5}}

Implementation guidance & references
Quotas: default 5 firewalls/Region/account, 300 VPC endpoint associations/Region/account. This design stays within defaults for 300 learners by sharing one firewall per Region and creating one association per student VPC.
VPC Endpoint Association is the supported way to place additional firewall endpoints in other VPCs/AZs (including student VPCs), provided the firewall has a primary endpoint in that AZ.
Routing to the firewall: AWS::EC2::Route supports VpcEndpointId as a target, so 0.0.0.0/0 → vpce-… is valid.
Logging: Network Firewall → CloudWatch Logs via AWS::NetworkFirewall::LoggingConfiguration with logGroup destinations for ALERT and FLOW types.,
Session Manager: use AmazonSSMManagedInstanceCore and the three interface endpoints (ssm, ec2messages, ssmmessages) to avoid NAT/public IPs.
StackSets: use service‑managed mode (trusted access with Organizations), OU targeting, and per‑Region parameter overrides (for each Region’s FirewallArn). ,
Want me to hand you “paste‑ready” StackSets CLI commands?

I can generate exact create-stack-set + create-stack-instances commands with your OU ID and the three FirewallArn values you’ll get after deploying nfw-instructor.yaml in each Region/account. If you share those ARNs (or want me to parameterize with SSM Parameter Store), I’ll add the commands to your bundle.

VpcCidr:

Type: String

Default: 10.10.0.0/24

AppSubnetCidr:

Type: String

Default: 10.10.0.0/25

FirewallArn:

Type: String

Description: ARN from the instructor stack output for this Region

InstanceType:

Type: String

Default: t3.micro

LogRetentionDays:

Type: Number

Default: 1

Resources:

VPC:

Type: AWS::EC2::VPC

Properties:

CidrBlock: !Ref VpcCidr

EnableDnsSupport: true

EnableDnsHostnames: true

Tags: [{ Key: Name, Value: !Sub '${LabName}-vpc' }]

AppSubnet:

Type: AWS::EC2::Subnet

Properties:

VpcId: !Ref VPC

AvailabilityZone: !Select [0, !GetAZs '']

CidrBlock: !Ref AppSubnetCidr

Tags: [{ Key: Name, Value: !Sub '${LabName}-subnet' }]

AppRT:

Type: AWS::EC2::RouteTable

Properties:

VpcId: !Ref VPC

Tags: [{ Key: Name, Value: !Sub '${LabName}-rt' }]

AppSubnetAssoc:

Type: AWS::EC2::SubnetRouteTableAssociation

Properties:

SubnetId: !Ref AppSubnet

RouteTableId: !Ref AppRT

# Interface endpoint security group: allow TLS from the VPC

EndpointSG:

Type: AWS::EC2::SecurityGroup

Properties:

GroupDescription: Allow TLS from VPC to Interface Endpoints

VpcId: !Ref VPC

SecurityGroupIngress:

- IpProtocol: tcp

FromPort: 443

ToPort: 443

CidrIp: !Ref VpcCidr

SecurityGroupEgress:

- IpProtocol: -1

FromPort: 0

ToPort: 0

CidrIp: 0.0.0.0/0

Tags: [{ Key: Name, Value: !Sub '${LabName}-vpce-sg' }]

# SSM interface endpoints (no NAT, no public IPs)

VPCEssm:

Type: AWS::EC2::VPCEndpoint

Properties:

ServiceName: !Sub 'com.amazonaws.${AWS::Region}.ssm'

VpcId: !Ref VPC

VpcEndpointType: Interface

PrivateDnsEnabled: true

SubnetIds: [ !Ref AppSubnet ]

SecurityGroupIds: [ !Ref EndpointSG ]

VPCDec2messages:

Type: AWS::EC2::VPCEndpoint

Properties:

ServiceName: !Sub 'com.amazonaws.${AWS::Region}.ec2messages'

VpcId: !Ref VPC

VpcEndpointType: Interface

PrivateDnsEnabled: true

SubnetIds: [ !Ref AppSubnet ]

SecurityGroupIds: [ !Ref EndpointSG ]

VPCEssmmessages:

Type: AWS::EC2::VPCEndpoint

Properties:

ServiceName: !Sub 'com.amazonaws.${AWS::Region}.ssmmessages'

VpcId: !Ref VPC

VpcEndpointType: Interface

PrivateDnsEnabled: true

SubnetIds: [ !Ref AppSubnet ]

SecurityGroupIds: [ !Ref EndpointSG ]

# Associate a firewall endpoint in this subnet/AZ (must match the firewall's AZ)

AppVpcEndpointAssoc:

Type: AWS::NetworkFirewall::VpcEndpointAssociation

Properties:

FirewallArn: !Ref FirewallArn

VpcId: !Ref VPC

SubnetMapping:

SubnetId: !Ref AppSubnet

Tags: [{ Key: Name, Value: !Sub '${LabName}-assoc' }]

# Default route to the firewall endpoint created by the association (supports VpcEndpointId)

DefaultRouteToNfw:

Type: AWS::EC2::Route

DependsOn: AppVpcEndpointAssoc

Properties:

RouteTableId: !Ref AppRT

DestinationCidrBlock: 0.0.0.0/0

VpcEndpointId: !GetAtt AppVpcEndpointAssoc.EndpointId

# EC2 with SSM only (no public IP; no inbound rules)

InstanceSG:

Type: AWS::EC2::SecurityGroup

Properties:

GroupDescription: Egress only for student instance

VpcId: !Ref VPC

SecurityGroupEgress:

- IpProtocol: -1

FromPort: 0

ToPort: 0

CidrIp: 0.0.0.0/0

Tags: [{ Key: Name, Value: !Sub '${LabName}-sg' }]

SsmRole:

Type: AWS::IAM::Role

Properties:

AssumeRolePolicyDocument:

Version: '2012-10-17'

Statement:

- Effect: Allow

Principal: { Service: ec2.amazonaws.com }

Action: 'sts:AssumeRole'

ManagedPolicyArns:

- arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

SsmInstanceProfile:

Type: AWS::IAM::InstanceProfile

Properties:

Roles: [ !Ref SsmRole ]

AMI:

Type: "AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>"

Default: /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64

EC2:

Type: AWS::EC2::Instance

Properties:

ImageId: !Ref AMI

InstanceType: !Ref InstanceType

IamInstanceProfile: !Ref SsmInstanceProfile

NetworkInterfaces:

- DeviceIndex: 0

SubnetId: !Ref AppSubnet

GroupSet: [ !Ref InstanceSG ]

AssociatePublicIpAddress: false

Tags: [{ Key: Name, Value: !Sub '${LabName}-ec2' }]

UserData:

Fn::Base64: !Sub |

#!/bin/bash

(dnf -y install bind-utils curl || yum -y install bind-utils curl) || true

echo "Try: dig @8.8.8.8 amazon.com ; curl -I https://www.google.com" > /etc/motd

Outputs:

StudentVpcId:

Value: !Ref VPC

StudentSubnetId:

Value: !Ref AppSubnet

FirewallEndpointId:

Value: !GetAtt AppVpcEndpointAssoc.EndpointId

InstanceId:

Value: !Ref EC2

Notes

AWS::NetworkFirewall::VpcEndpointAssociation returns EndpointId, and AWS::EC2::Route supports using VpcEndpointId as the route target—so we can wire 0.0.0.0/0 → vpce‑… cleanly in CFN. ,
We create the three SSM interface endpoints to use Session Manager without NAT/public IPs, per the documented prerequisites/endpoints.
3) Runbook (multi‑account / multi‑Region in ~30 minutes)
A) Prereqs (once)
You have AWS Organizations and can use CloudFormation StackSets (service‑managed) from the management or delegated admin account. Enable trusted access and (optionally) register a delegated admin. ,
Create or pick three student accounts and organize them under an OU.
Access: students will use Session Manager from the console—no SSH keys.
B) Deploy the Instructor stack in each account/Region

For each lab account in us-east-1, eu-west-2, ap-southeast-1:

{{2-raw-markdown-db638e6b-0223-4f65-bfc1-df79117d04c5}}

Record the FirewallArn output (per Region/account).

If each Region has its own dedicated lab account, repeat these steps in each account/Region pair.

C) Create the Student StackSet (service‑managed)

From the management (or delegated admin) account:

Create StackSet named nfw-student-min with template nfw-student-min.yaml.
Parameters: set LabName (e.g., nfw-lab), FirewallArn per Region (StackSets lets you override parameters per stack instance/Region).
Targets: choose the OU that holds the 3 lab accounts (or list the three accounts).
Regions: us-east-1, eu-west-2, ap-southeast-1.
Operation preferences:
Failure tolerance: small (e.g., 5)
Max concurrent accounts: moderate (e.g., 25–50)
Region order: your preference

Within a few minutes, each student account/Region will have a VPC + EC2 that routes egress via your shared firewall endpoint.

D) Student instructions (2 lines)
Console → Systems Manager → Fleet Manager → Nodes → select your instance → Start session (or EC2 → Instance → Connect → Session Manager).
Run: {{3-raw-markdown-db638e6b-0223-4f65-bfc1-df79117d04c5}}
CloudWatch Logs → /aws/network-firewall/alert & /aws/network-firewall/flow to see rule hits/flows.
4) Cleanup script – lab-cleanup.sh (AWS CLI)
Deletes StackSet instances (student side) and optionally deletes the instructor stacks.
Run this from your management/delegated admin account.

{{4-raw-markdown-db638e6b-0223-4f65-bfc1-df79117d04c5}}

Implementation guidance & references
Quotas: default 5 firewalls/Region/account, 300 VPC endpoint associations/Region/account. This design stays within defaults for 300 learners by sharing one firewall per Region and creating one association per student VPC.
VPC Endpoint Association is the supported way to place additional firewall endpoints in other VPCs/AZs (including student VPCs), provided the firewall has a primary endpoint in that AZ.
Routing to the firewall: AWS::EC2::Route supports VpcEndpointId as a target, so 0.0.0.0/0 → vpce-… is valid.
Logging: Network Firewall → CloudWatch Logs via AWS::NetworkFirewall::LoggingConfiguration with logGroup destinations for ALERT and FLOW types.,
Session Manager: use AmazonSSMManagedInstanceCore and the three interface endpoints (ssm, ec2messages, ssmmessages) to avoid NAT/public IPs.
StackSets: use service‑managed mode (trusted access with Organizations), OU targeting, and per‑Region parameter overrides (for each Region’s FirewallArn). ,
Want me to hand you “paste‑ready” StackSets CLI commands?

I can generate exact create-stack-set + create-stack-instances commands with your OU ID and the three FirewallArn values you’ll get after deploying nfw-instructor.yaml in each Region/account. If you share those ARNs (or want me to parameterize with SSM Parameter Store), I’ll add the commands to your bundle.

VpcCidr:

Type: String

Default: 10.100.0.0/16

FirewallSubnetCidr:

Type: String

Default: 10.100.1.0/24

LogRetentionDays:

Type: Number

Default: 3

MinValue: 1

MaxValue: 3653

Resources:

VPC:

Type: AWS::EC2::VPC

Properties:

CidrBlock: !Ref VpcCidr

EnableDnsSupport: true

EnableDnsHostnames: true

Tags: [{ Key: Name, Value: nfw-lab-vpc }]

IGW:

Type: AWS::EC2::InternetGateway

Properties:

Tags: [{ Key: Name, Value: nfw-lab-igw }]

VpcIgwAttach:

Type: AWS::EC2::VPCGatewayAttachment

Properties:

VpcId: !Ref VPC

InternetGatewayId: !Ref IGW

FirewallSubnet:

Type: AWS::EC2::Subnet

Properties:

VpcId: !Ref VPC

AvailabilityZone: !Select [0, !GetAZs '']

CidrBlock: !Ref FirewallSubnetCidr

Tags: [{ Key: Name, Value: nfw-lab-fw-subnet }]

FirewallRT:

Type: AWS::EC2::RouteTable

Properties:

VpcId: !Ref VPC

Tags: [{ Key: Name, Value: nfw-lab-fw-rt }]

FirewallSubnetAssoc:

Type: AWS::EC2::SubnetRouteTableAssociation

Properties:

SubnetId: !Ref FirewallSubnet

RouteTableId: !Ref FirewallRT

FirewallRTDefault:

Type: AWS::EC2::Route

DependsOn: VpcIgwAttach

Properties:

RouteTableId: !Ref FirewallRT

DestinationCidrBlock: 0.0.0.0/0

GatewayId: !Ref IGW

# Stateful rule group: ALERT on any UDP→53

StatefulDnsAlertRG:

Type: AWS::NetworkFirewall::RuleGroup

Properties:

Capacity: 100

RuleGroupName: !Sub '${FirewallName}-stateful-dns-alert'

Type: STATEFUL

RuleGroup:

RulesSource:

RulesString: |

alert udp any any -> any 53 (msg:"LAB ALERT: UDP DNS"; sid:1000001; rev:1;)

Tags: [{ Key: Name, Value: nfw-lab-stateful-dns-alert }]

FirewallPolicy:

Type: AWS::NetworkFirewall::FirewallPolicy

Properties:

FirewallPolicyName: !Sub '${FirewallName}-policy'

FirewallPolicy:

StatelessDefaultActions:

- aws:forward_to_sfe

StatelessFragmentDefaultActions:

- aws:forward_to_sfe

StatefulRuleGroupReferences:

- ResourceArn: !Ref StatefulDnsAlertRG

Tags: [{ Key: Name, Value: nfw-lab-firewall-policy }]

Firewall:

Type: AWS::NetworkFirewall::Firewall

Properties:

FirewallName: !Ref FirewallName

FirewallPolicyArn: !Ref FirewallPolicy

VpcId: !Ref VPC

SubnetMappings:

- SubnetId: !Ref FirewallSubnet

DeleteProtection: false

FirewallPolicyChangeProtection: false

SubnetChangeProtection: false

Tags: [{ Key: Name, Value: nfw-lab-firewall }]

# CloudWatch Log Groups for ALERT & FLOW

AlertLogGroup:

Type: AWS::Logs::LogGroup

Properties:

LogGroupName: /aws/network-firewall/alert

RetentionInDays: !Ref LogRetentionDays

FlowLogGroup:

Type: AWS::Logs::LogGroup

Properties:

LogGroupName: /aws/network-firewall/flow

RetentionInDays: !Ref LogRetentionDays

NfwLogging:

Type: AWS::NetworkFirewall::LoggingConfiguration

Properties:

FirewallArn: !GetAtt Firewall.FirewallArn

LoggingConfiguration:

LogDestinationConfigs:

- LogType: ALERT

LogDestinationType: CloudWatchLogs

LogDestination: { logGroup: !Ref AlertLogGroup }

- LogType: FLOW

LogDestinationType: CloudWatchLogs

LogDestination: { logGroup: !Ref FlowLogGroup }

Outputs:

FirewallArn:

Value: !GetAtt Firewall.FirewallArn

Description: ARN of the Network Firewall

FirewallAzName:

Value: !GetAtt FirewallSubnet.AvailabilityZone

Description: AZ used for the firewall endpoints (students must use same AZ)

AlertLogGroupName:

Value: !Ref AlertLogGroup

FlowLogGroupName:

Value: !Ref FlowLogGroup

Notes

We pick the first AZ in each Region so you can keep student subnets in the same AZ (a requirement for placing the association/endpoint in that AZ).
Network Firewall logging to CloudWatch uses the documented LoggingConfiguration and the log group key logGroup.,
2) Student StackSet template – nfw-student-min.yaml

Deployed via CloudFormation StackSets (service‑managed) into target accounts & Regions.
Creates one mini‑lab per student: VPC, subnet (AZ‑a), RT, VPC Endpoint Association to your shared firewall, default route → firewall endpoint, SSM VPC endpoints, and an EC2 instance with SSM only.

{{1-raw-markdown-db638e6b-0223-4f65-bfc1-df79117d04c5}}

Notes

AWS::NetworkFirewall::VpcEndpointAssociation returns EndpointId, and AWS::EC2::Route supports using VpcEndpointId as the route target—so we can wire 0.0.0.0/0 → vpce‑… cleanly in CFN. ,
We create the three SSM interface endpoints to use Session Manager without NAT/public IPs, per the documented prerequisites/endpoints.
3) Runbook (multi‑account / multi‑Region in ~30 minutes)
A) Prereqs (once)
You have AWS Organizations and can use CloudFormation StackSets (service‑managed) from the management or delegated admin account. Enable trusted access and (optionally) register a delegated admin. ,
Create or pick three student accounts and organize them under an OU.
Access: students will use Session Manager from the console—no SSH keys.
B) Deploy the Instructor stack in each account/Region

For each lab account in us-east-1, eu-west-2, ap-southeast-1:

{{2-raw-markdown-db638e6b-0223-4f65-bfc1-df79117d04c5}}

Record the FirewallArn output (per Region/account).

If each Region has its own dedicated lab account, repeat these steps in each account/Region pair.

C) Create the Student StackSet (service‑managed)

From the management (or delegated admin) account:

Create StackSet named nfw-student-min with template nfw-student-min.yaml.
Parameters: set LabName (e.g., nfw-lab), FirewallArn per Region (StackSets lets you override parameters per stack instance/Region).
Targets: choose the OU that holds the 3 lab accounts (or list the three accounts).
Regions: us-east-1, eu-west-2, ap-southeast-1.
Operation preferences:
Failure tolerance: small (e.g., 5)
Max concurrent accounts: moderate (e.g., 25–50)
Region order: your preference

Within a few minutes, each student account/Region will have a VPC + EC2 that routes egress via your shared firewall endpoint.

D) Student instructions (2 lines)
Console → Systems Manager → Fleet Manager → Nodes → select your instance → Start session (or EC2 → Instance → Connect → Session Manager).
Run: {{3-raw-markdown-db638e6b-0223-4f65-bfc1-df79117d04c5}}
CloudWatch Logs → /aws/network-firewall/alert & /aws/network-firewall/flow to see rule hits/flows.
4) Cleanup script – lab-cleanup.sh (AWS CLI)
Deletes StackSet instances (student side) and optionally deletes the instructor stacks.
Run this from your management/delegated admin account.

{{4-raw-markdown-db638e6b-0223-4f65-bfc1-df79117d04c5}}

Implementation guidance & references
Quotas: default 5 firewalls/Region/account, 300 VPC endpoint associations/Region/account. This design stays within defaults for 300 learners by sharing one firewall per Region and creating one association per student VPC.
VPC Endpoint Association is the supported way to place additional firewall endpoints in other VPCs/AZs (including student VPCs), provided the firewall has a primary endpoint in that AZ.
Routing to the firewall: AWS::EC2::Route supports VpcEndpointId as a target, so 0.0.0.0/0 → vpce-… is valid.
Logging: Network Firewall → CloudWatch Logs via AWS::NetworkFirewall::LoggingConfiguration with logGroup destinations for ALERT and FLOW types.,
Session Manager: use AmazonSSMManagedInstanceCore and the three interface endpoints (ssm, ec2messages, ssmmessages) to avoid NAT/public IPs.
StackSets: use service‑managed mode (trusted access with Organizations), OU targeting, and per‑Region parameter overrides (for each Region’s FirewallArn). ,

