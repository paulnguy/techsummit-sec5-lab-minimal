#!/usr/bin/env bash

################################################################################
# Lab Cleanup Script - AWS Network Firewall TechSummit Lab
#
# Deletes StackSet instances (student side) and optionally deletes instructor
# stacks across multiple AWS Regions.
#
# Usage:
#   ./lab-cleanup.sh [--delete-instructor] [--ou-id <OU_ID>]
#
# Environment Variables:
#   DELETE_INSTRUCTOR     Set to 'true' to also delete instructor stacks
#   STACKSET_NAME         StackSet name (default: nfw-student-min)
#   REGIONS              Space-separated regions (default: us-east-1 eu-west-2 ap-southeast-1)
#   OU_ID                Organizational Unit ID (if using OU-based targeting)
#   ACCOUNT_IDS          Space-separated account IDs (if not using OU)
#
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STACKSET_NAME="${STACKSET_NAME:-nfw-student-min}"
REGIONS="${REGIONS:-us-east-1 eu-west-2 ap-southeast-1}"
OU_ID="${OU_ID:-}"
ACCOUNT_IDS="${ACCOUNT_IDS:-}"
DELETE_INSTRUCTOR="${DELETE_INSTRUCTOR:-false}"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --delete-instructor)
            DELETE_INSTRUCTOR=true
            shift
            ;;
        --ou-id)
            OU_ID=$2
            shift 2
            ;;
        --stackset-name)
            STACKSET_NAME=$2
            shift 2
            ;;
        --regions)
            REGIONS=$2
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --delete-instructor     Also delete instructor stacks"
            echo "  --ou-id <OU_ID>         Organizational Unit ID for targeting"
            echo "  --stackset-name <NAME>  StackSet name (default: nfw-student-min)"
            echo "  --regions <REGIONS>     Space-separated regions (default: us-east-1 eu-west-2 ap-southeast-1)"
            echo "  --help                  Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate configuration
if [[ -z "${OU_ID}" && -z "${ACCOUNT_IDS}" ]]; then
    echo -e "${YELLOW}[!] Warning: Neither OU_ID nor ACCOUNT_IDS provided.${NC}"
    echo "    Please set OU_ID or ACCOUNT_IDS environment variable."
    echo "    Example: export OU_ID='ou-xxxx-yyyyyyyy'"
    echo "    Or:      export ACCOUNT_IDS='111111111111 222222222222 333333333333'"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Network Firewall Lab Cleanup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "StackSet Name:  ${YELLOW}${STACKSET_NAME}${NC}"
echo -e "Regions:        ${YELLOW}${REGIONS}${NC}"
echo -e "Delete Instructor: ${YELLOW}${DELETE_INSTRUCTOR}${NC}"
if [[ -n "${OU_ID}" ]]; then
    echo -e "OU ID:          ${YELLOW}${OU_ID}${NC}"
else
    echo -e "Account IDs:    ${YELLOW}${ACCOUNT_IDS}${NC}"
fi
echo ""

# Function to validate AWS CLI
validate_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}[ERROR] AWS CLI not found. Please install it first.${NC}"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}[ERROR] AWS credentials not configured or invalid.${NC}"
        exit 1
    fi

    echo -e "${GREEN}[✓] AWS CLI validation passed${NC}"
}

# Function to delete StackSet instances
delete_stackset_instances() {
    echo ""
    echo -e "${YELLOW}[1/3] Deleting StackSet instances (students)...${NC}"
    
    local deployment_targets=""
    
    if [[ -n "${OU_ID}" ]]; then
        deployment_targets="OrganizationalUnitIds=${OU_ID}"
    else
        # Convert ACCOUNT_IDS to comma-separated format
        local accounts
        accounts=$(echo ${ACCOUNT_IDS} | tr ' ' ',')
        deployment_targets="Accounts=${accounts}"
    fi

    # Check if StackSet exists
    if ! aws cloudformation describe-stack-set \
        --stack-set-name "${STACKSET_NAME}" &> /dev/null; then
        echo -e "${YELLOW}[!] StackSet '${STACKSET_NAME}' not found. Skipping deletion.${NC}"
        return 0
    fi

    echo -e "Deleting instances with deployment targets: ${deployment_targets}"
    
    # Delete instances
    aws cloudformation delete-stack-instances \
        --stack-set-name "${STACKSET_NAME}" \
        --regions ${REGIONS} \
        --deployment-targets "${deployment_targets}" \
        --no-retain-stacks \
        --region "${AWS_REGION:-us-east-1}" || {
        echo -e "${RED}[ERROR] Failed to delete StackSet instances${NC}"
        return 1
    }

    # Wait for operation to complete (with timeout handling)
    echo "Waiting for deletion operation to complete (this may take a few minutes)..."
    local retry_count=0
    local max_retries=120  # 10 minutes with 5-second intervals
    
    while [[ ${retry_count} -lt ${max_retries} ]]; do
        local operation_status
        operation_status=$(aws cloudformation list-stack-set-operations \
            --stack-set-name "${STACKSET_NAME}" \
            --query 'Summaries[0].Status' \
            --output text \
            --region "${AWS_REGION:-us-east-1}" 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "${operation_status}" == "SUCCEEDED" ]] || [[ "${operation_status}" == "FAILED" ]]; then
            break
        fi
        
        sleep 5
        ((retry_count++))
        echo -n "."
    done
    echo ""
    
    if [[ ${retry_count} -ge ${max_retries} ]]; then
        echo -e "${YELLOW}[!] Operation timeout. Continuing anyway...${NC}"
    else
        echo -e "${GREEN}[✓] StackSet instances deleted${NC}"
    fi
}

# Function to delete StackSet
delete_stackset() {
    echo ""
    echo -e "${YELLOW}[2/3] Deleting StackSet...${NC}"
    
    aws cloudformation delete-stack-set \
        --stack-set-name "${STACKSET_NAME}" \
        --region "${AWS_REGION:-us-east-1}" || {
        echo -e "${YELLOW}[!] Failed to delete StackSet (may not exist)${NC}"
        return 0
    }
    
    echo -e "${GREEN}[✓] StackSet deleted${NC}"
}

# Function to delete instructor stacks
delete_instructor_stacks() {
    if [[ "${DELETE_INSTRUCTOR}" != "true" ]]; then
        echo ""
        echo -e "${YELLOW}[3/3] Instructor stacks preserved (set --delete-instructor to remove)${NC}"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}[3/3] Deleting instructor stacks in each Region...${NC}"
    
    local failed_stacks=()
    
    for region in ${REGIONS}; do
        echo -e "Deleting instructor stack in ${YELLOW}${region}${NC}..."
        
        if aws cloudformation describe-stacks \
            --region "${region}" \
            --stack-name nfw-instructor &> /dev/null; then
            
            aws cloudformation delete-stack \
                --region "${region}" \
                --stack-name nfw-instructor || {
                failed_stacks+=("${region}")
            }
            
            # Wait for deletion
            echo "Waiting for deletion in ${region}..."
            aws cloudformation wait stack-delete-complete \
                --region "${region}" \
                --stack-name nfw-instructor 2>/dev/null || {
                echo -e "${YELLOW}[!] Timeout waiting for stack deletion in ${region}${NC}"
            }
        else
            echo -e "${YELLOW}[!] Instructor stack not found in ${region}${NC}"
        fi
    done
    
    if [[ ${#failed_stacks[@]} -eq 0 ]]; then
        echo -e "${GREEN}[✓] All instructor stacks deleted${NC}"
    else
        echo -e "${YELLOW}[!] Some stacks had issues: ${failed_stacks[*]}${NC}"
    fi
}

# Main execution
main() {
    validate_aws_cli
    
    delete_stackset_instances
    delete_stackset
    delete_instructor_stacks
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Cleanup Complete${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# Run main function
main "$@"
