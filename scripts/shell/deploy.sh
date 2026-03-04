#!/bin/bash
# deploy.sh - Deploy the Omni-Channel Social Messaging app to a Salesforce org
#
# Prerequisites:
#   - Salesforce CLI (sf) installed
#   - Authenticated org: sf org login web --alias my-org
#
# Usage:
#   ./scripts/shell/deploy.sh [org-alias]

set -euo pipefail

ORG_ALIAS="${1:-my-org}"

echo "╔══════════════════════════════════════════════════════╗"
echo "║   Omni-Channel Social Messaging - Deployment         ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Target org alias: $ORG_ALIAS"
echo ""

# 1. Validate (dry run)
echo "► Step 1/3: Validating deployment..."
sf project deploy start \
    --source-dir force-app \
    --target-org "$ORG_ALIAS" \
    --dry-run \
    --ignore-warnings

echo ""
echo "► Step 2/3: Deploying metadata..."
sf project deploy start \
    --source-dir force-app \
    --target-org "$ORG_ALIAS" \
    --ignore-warnings

echo ""
echo "► Step 3/3: Running Apex tests..."
sf apex run test \
    --target-org "$ORG_ALIAS" \
    --test-level RunLocalTests \
    --result-format human \
    --output-dir test-results \
    --wait 10

echo ""
echo "✓ Deployment complete!"
echo ""
echo "Next steps:"
echo "  1. Run sample data setup:"
echo "     sf apex run --file scripts/apex/setup-sample-data.apex --target-org $ORG_ALIAS"
echo ""
echo "  2. Configure Named Credentials:"
echo "     Setup → Security → Named Credentials → Facebook Graph API"
echo "     Setup → Security → Named Credentials → Instagram Graph API"
echo ""
echo "  3. Register Facebook webhook:"
echo "     URL: https://YOUR_SALESFORCE_SITE_URL/services/apexrest/social/webhook"
echo "     Verify Token: (value from Social_Channel_Config__c.Webhook_Verify_Token__c)"
echo ""
echo "  4. Assign permission sets to users:"
echo "     sf org assign permset --name OmniChannelSocialAgent --target-org $ORG_ALIAS --on-behalf-of user@example.com"
echo "     sf org assign permset --name OmniChannelSocialAdmin --target-org $ORG_ALIAS --on-behalf-of admin@example.com"
echo ""
echo "  5. Add socialMessagingDashboard LWC to a Lightning App Page in App Builder"
