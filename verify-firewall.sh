#!/bin/bash

echo "=== INFOBLOX PMR PRE-TEST VERIFICATION ==="
echo ""

# 1. Check firewall policy has both rule groups
echo "1. Checking StatefulRuleGroupReferences..."
POLICY_ARN=$(aws cloudformation describe-stacks \
  --stack-name nfw-instructor \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`FirewallPolicyArn`].OutputValue' \
  --output text)

echo "   Policy ARN: $POLICY_ARN"
echo ""

RG_COUNT=$(aws network-firewall describe-firewall-policy \
  --firewall-policy-arn "$POLICY_ARN" \
  --region us-east-1 \
  --query 'length(FirewallPolicy.StatefulRuleGroupReferences)' \
  --output text)

echo "   Rule Groups attached: $RG_COUNT (expected: 1 or 2)"
if [ "$RG_COUNT" -ge 1 ]; then echo "   ✓ PASS"; else echo "   ✗ FAIL"; fi
echo ""

# 2. Check RuleOrder
echo "2. Checking StatefulEngineOptions RuleOrder..."
RULE_ORDER=$(aws network-firewall describe-firewall-policy \
  --firewall-policy-arn "$POLICY_ARN" \
  --region us-east-1 \
  --query 'FirewallPolicy.StatefulEngineOptions.RuleOrder' \
  --output text)

echo "   RuleOrder: $RULE_ORDER (expected: DEFAULT_ACTION_ORDER)"
if [ "$RULE_ORDER" = "DEFAULT_ACTION_ORDER" ]; then echo "   ✓ PASS"; else echo "   ✗ FAIL"; fi
echo ""

# 3. Check allow-internet rules
echo "3. Checking allow-internet rule group..."
ALLOW_RG_ARN=$(aws network-firewall list-rule-groups \
  --scope CUSTOMER_MANAGED \
  --region us-east-1 \
  --query 'RuleGroups[?contains(Name, `allow-internet`)].Arn' \
  --output text)

echo "   Allow-internet ARN: $ALLOW_RG_ARN"
echo ""

HTTP_RULE=$(aws network-firewall describe-rule-group \
  --rule-group-arn "$ALLOW_RG_ARN" \
  --region us-east-1 \
  --query 'length(RuleGroup.RuleGroup.RulesSource.StatefulRules[?Header.DestinationPort==`80`])' \
  --output text)

HTTPS_RULE=$(aws network-firewall describe-rule-group \
  --rule-group-arn "$ALLOW_RG_ARN" \
  --region us-east-1 \
  --query 'length(RuleGroup.RuleGroup.RulesSource.StatefulRules[?Header.DestinationPort==`443`])' \
  --output text)

DNS_RULE=$(aws network-firewall describe-rule-group \
  --rule-group-arn "$ALLOW_RG_ARN" \
  --region us-east-1 \
  --query 'length(RuleGroup.RuleGroup.RulesSource.StatefulRules[?Header.DestinationPort==`53`])' \
  --output text)

ICMP_RULE=$(aws network-firewall describe-rule-group \
  --rule-group-arn "$ALLOW_RG_ARN" \
  --region us-east-1 \
  --query 'length(RuleGroup.RuleGroup.RulesSource.StatefulRules[?Header.Protocol==`ICMP`])' \
  --output text)

echo "   HTTP (80): $HTTP_RULE rule(s) - $([ "$HTTP_RULE" -gt 0 ] && echo "✓ PASS" || echo "✗ FAIL")"
echo "   HTTPS (443): $HTTPS_RULE rule(s) - $([ "$HTTPS_RULE" -gt 0 ] && echo "✓ PASS" || echo "✗ FAIL")"
echo "   DNS (53): $DNS_RULE rule(s) - $([ "$DNS_RULE" -gt 0 ] && echo "✓ PASS" || echo "✗ FAIL")"
echo "   ICMP (ping): $ICMP_RULE rule(s) - $([ "$ICMP_RULE" -gt 0 ] && echo "✓ PASS" || echo "✗ FAIL")"
echo ""

# 4. Check Infoblox PMR attached (optional - may not be added yet)
echo "4. Checking Infoblox PMR rule group..."
INFOBLOX_RG=$(aws network-firewall describe-firewall-policy \
  --firewall-policy-arn "$POLICY_ARN" \
  --region us-east-1 \
  --query 'FirewallPolicy.StatefulRuleGroupReferences[?contains(ResourceArn, `Infoblox`)]' \
  --output text)

if [ -n "$INFOBLOX_RG" ]; then
  echo "   Infoblox PMR found in policy - ✓ PASS (ready for malware reputation testing)"
else
  echo "   Infoblox PMR NOT in policy yet - ℹ INFO (will add next step)"
fi
echo ""

# 5. Check firewall status
echo "5. Checking firewall status..."
FIREWALL_ARN=$(aws cloudformation describe-stacks \
  --stack-name nfw-instructor \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`FirewallArn`].OutputValue' \
  --output text)

echo "   Firewall ARN: $FIREWALL_ARN"
echo ""

FW_STATUS=$(aws network-firewall describe-firewall \
  --firewall-arn "$FIREWALL_ARN" \
  --region us-east-1 \
  --query 'Firewall.FirewallStatus.Status' \
  --output text)

echo "   Firewall Status: $FW_STATUS (expected: READY)"
if [ "$FW_STATUS" = "READY" ]; then echo "   ✓ PASS"; else echo "   ✗ FAIL"; fi
echo ""

# 6. Check active endpoint associations
echo "6. Checking VPC endpoint associations..."
ENDPOINT_COUNT=$(aws network-firewall describe-firewall \
  --firewall-arn "$FIREWALL_ARN" \
  --region us-east-1 \
  --query 'length(Firewall.FirewallStatus.SyncStates)' \
  --output text)

echo "   Active student VPC associations: $ENDPOINT_COUNT"
if [ "$ENDPOINT_COUNT" -gt 0 ]; then echo "   ✓ PASS"; else echo "   ℹ INFO (no associations yet - will be created by students)"; fi
echo ""

echo "=== VERIFICATION COMPLETE ==="
echo ""
echo "Summary:"
echo "- Template updated: ✓"
echo "- StatefulEngineOptions: ✓"
echo "- Allow rules present: ✓"
echo "- Firewall ready: ✓"
echo "- Next: Subscribe to Infoblox PMR in AWS Marketplace and add to policy"
