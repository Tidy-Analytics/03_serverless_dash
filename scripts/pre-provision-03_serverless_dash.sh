#!/bin/bash

# Pre-provisioning script for 03_serverless_dash
# This script handles federated identity credential creation and GitHub secrets setup
# that need to be done before running the main provisioning script

CLIENT_NAME=${1:-""}
if [ -z "$CLIENT_NAME" ]; then
    echo "Error: Client name is required"
    echo "Usage: $0 <client_name>"
    exit 1
fi

# Load client-specific configuration
SEED_CONFIG="./configs/${CLIENT_NAME}.env"
if [ ! -f "$SEED_CONFIG" ]; then
    echo "Error: Client configuration not found: $SEED_CONFIG"
    echo "Please create the configuration file first using configs/sample.env as a template"
    exit 1
fi

# Load configuration
source "$SEED_CONFIG"

# Validate required variables
if [ -z "$GH_TOKEN" ]; then
    echo "Error: GH_TOKEN is required in configuration"
    exit 1
fi

if [ -z "$REPO_NAME" ]; then
    echo "Error: REPO_NAME is required in configuration"
    exit 1
fi

if [ -z "$AZURE_CLIENT_ID" ]; then
    echo "Error: AZURE_CLIENT_ID is required in configuration"
    exit 1
fi

if [ -z "$AZURE_TENANT_ID" ]; then
    echo "Error: AZURE_TENANT_ID is required in configuration"
    exit 1
fi

if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
    echo "Error: AZURE_SUBSCRIPTION_ID is required in configuration"
    exit 1
fi

echo "Starting pre-provisioning for client: $CLIENT_NAME (03_serverless_dash)"

# Step 1: Authenticate with GitHub
echo "Authenticating with GitHub..."
gh auth login --with-token <<< "$GH_TOKEN"

# Step 2: Check if this is the first client setup or additional client
echo "Checking existing GitHub secrets..."
existing_secrets=$(gh secret list --repo "$REPO_NAME" --json name | jq -r '.[] | select(.name | startswith("'${CLIENT_NAME}'_")) | .name')

if [ -n "$existing_secrets" ]; then
    echo "Found existing secrets for client $CLIENT_NAME:"
    echo "$existing_secrets"
    echo ""
    read -p "Do you want to overwrite existing secrets? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Skipping secret creation for existing client $CLIENT_NAME"
        exit 0
    fi
fi

# Step 3: Create/update GitHub secrets from configuration
echo "Creating GitHub secrets for client: $CLIENT_NAME..."

# Core Azure credentials (from master provisioner)
gh secret set "${CLIENT_NAME}_AZURE_CLIENT_ID" --body "$AZURE_CLIENT_ID" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_AZURE_TENANT_ID" --body "$AZURE_TENANT_ID" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_AZURE_SUBSCRIPTION_ID" --body "$AZURE_SUBSCRIPTION_ID" --repo "$REPO_NAME"

# Client-specific configuration
gh secret set "${CLIENT_NAME}_RESOURCE_GROUP" --body "${CLIENT_NAME}-rg" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_LOCATION" --body "$LOCATION" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_CUSTOM_DOMAIN" --body "$CUSTOM_DOMAIN" --repo "$REPO_NAME"

# App owner information
gh secret set "${CLIENT_NAME}_APP_OWNER" --body "$APP_OWNER" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_APP_OWNER_NAME" --body "$APP_OWNER_NAME" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_ORG_NAME" --body "$ORG_NAME" --repo "$REPO_NAME"

# Storage configuration (will be populated after main provisioning)
gh secret set "${CLIENT_NAME}_STORAGE_ACCOUNT_NAME" --body "${CLIENT_NAME,,}storage" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_BLOB_CONTAINER_NAME" --body "${CLIENT_NAME}-in" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_KEYVAULT_NAME" --body "${CLIENT_NAME}-kv" --repo "$REPO_NAME"

# Placeholder for secrets that will be created during main provisioning
echo "Placeholder secrets (will be updated during main provisioning):"
gh secret set "${CLIENT_NAME}_STORAGE_SAS_TOKEN" --body "placeholder-will-be-updated" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_AZURE_STATIC_WEB_APPS_API_TOKEN" --body "placeholder-will-be-updated" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_SWA_CLIENT_ID" --body "placeholder-will-be-updated" --repo "$REPO_NAME"

echo ""
echo "GitHub secrets created successfully for client: $CLIENT_NAME"

# Step 4: Output next steps
echo "=================================================="
echo "Pre-provisioning Complete!"
echo "=================================================="
echo "Client: $CLIENT_NAME"
echo "Repository: $REPO_NAME"
echo "GitHub secrets configured for client-specific deployment"
echo ""
echo "Next steps:"
echo "1. Run the main provisioning script:"
echo "   ./scripts/provision-03_serverless_dash.sh $CLIENT_NAME"
echo ""
echo "2. After provisioning, test the deployment:"
echo "   - Go to GitHub Actions in the $REPO_NAME repository"
echo "   - Run the 'Azure Static Web Apps CI/CD' workflow"
echo "   - Choose 'deploy-app' action and client handle: $CLIENT_NAME"
echo ""
echo "3. Upload customer data to blob container:"
echo "   - Container: ${CLIENT_NAME}-in"
echo "   - File name: customer_data.json"
echo "   - Storage account: ${CLIENT_NAME,,}storage"

# Save pre-provisioning log
cat > "./configs/${CLIENT_NAME}_pre-provision.log" << EOF
# Pre-provisioning log for $CLIENT_NAME
# Generated on $(date)

CLIENT_NAME=$CLIENT_NAME
REPO_NAME=$REPO_NAME
RESOURCE_GROUP=${CLIENT_NAME}-rg
CUSTOM_DOMAIN=$CUSTOM_DOMAIN
STORAGE_ACCOUNT_NAME=${CLIENT_NAME,,}storage
BLOB_CONTAINER_NAME=${CLIENT_NAME}-in
KEYVAULT_NAME=${CLIENT_NAME}-kv

# GitHub secrets created:
${CLIENT_NAME}_AZURE_CLIENT_ID
${CLIENT_NAME}_AZURE_TENANT_ID
${CLIENT_NAME}_AZURE_SUBSCRIPTION_ID
${CLIENT_NAME}_RESOURCE_GROUP
${CLIENT_NAME}_LOCATION
${CLIENT_NAME}_CUSTOM_DOMAIN
${CLIENT_NAME}_APP_OWNER
${CLIENT_NAME}_APP_OWNER_NAME
${CLIENT_NAME}_ORG_NAME
${CLIENT_NAME}_STORAGE_ACCOUNT_NAME
${CLIENT_NAME}_BLOB_CONTAINER_NAME
${CLIENT_NAME}_KEYVAULT_NAME

# Placeholder secrets (updated during main provisioning):
${CLIENT_NAME}_STORAGE_SAS_TOKEN
${CLIENT_NAME}_AZURE_STATIC_WEB_APPS_API_TOKEN
${CLIENT_NAME}_SWA_CLIENT_ID

Status: Pre-provisioning completed successfully
Next: Run ./scripts/provision-03_serverless_dash.sh $CLIENT_NAME
EOF

echo "Pre-provisioning log saved to: ./configs/${CLIENT_NAME}_pre-provision.log"