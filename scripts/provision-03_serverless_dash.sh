#!/bin/bash

# Required arguments
CLIENT_NAME=${1:-""}
if [ -z "$CLIENT_NAME" ]; then
    echo "Error: Client name is required"
    echo "Usage: $0 <client_name>"
    exit 1
fi

echo "Starting 03_serverless_dash provisioning for client: $CLIENT_NAME"

# Load configuration from CONFIG secret (JSON format)
if [ -n "$CONFIG" ]; then
    echo "Loading configuration from CONFIG secret..."
    while IFS="=" read -r key value; do
        if [ -n "$key" ] && [ -n "$value" ]; then
            export "$key"="$value"
            echo "Loaded: $key"
        fi
    done < <(echo "$CONFIG" | jq -r 'to_entries | map("\(.key)=\(.value)") | .[]')
else
    echo "Warning: No CONFIG secret available"
fi

# Set defaults for required values
RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-"${CLIENT_NAME}-rg"}
LOCATION=${LOCATION:-"CentralUS"}
CUSTOM_DOMAIN=${CUSTOM_DOMAIN:-"${CLIENT_NAME}.tidyanalytics.com"}
VAULT_NAME=${VAULT_NAME:-"${CLIENT_NAME}-kv"}
APP_REPO=${APP_REPO:-"Tidy-Analytics/03_serverless_dash"}

# Validate required configuration
if [ -z "$AZURE_SUBSCRIPTION_ID" ] || [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_TENANT_ID" ]; then
    echo "Error: Azure credentials are required"
    exit 1
fi

if [ -z "$APP_OWNER" ]; then
    echo "Error: APP_OWNER email is required"
    exit 1
fi

echo ""
echo "Configuration summary:"
echo "  Client: $CLIENT_NAME"
echo "  Resource Group: $RESOURCE_GROUP_NAME"
echo "  Location: $LOCATION"
echo "  Custom Domain: $CUSTOM_DOMAIN"
echo "  Key Vault: $VAULT_NAME"
echo "  Repository: $APP_REPO"
echo "  App Owner: $APP_OWNER"

# Set derived resource names
SWA_NAME="${CLIENT_NAME}-serverless-dash"
APP_REG_NAME="${CLIENT_NAME}-serverless-dash-auth"

echo ""
echo "=== Step 1: Verify Resource Group exists ==="
if ! az group show --name "$RESOURCE_GROUP_NAME" >/dev/null 2>&1; then
    echo "Error: Resource group $RESOURCE_GROUP_NAME does not exist"
    echo "Please run 00_clientinfra provisioning first to create client infrastructure"
    exit 1
fi
echo "✓ Resource group $RESOURCE_GROUP_NAME exists"

echo ""
echo "=== Step 2: Create Azure Static Web App ==="
if az staticwebapp show --name "$SWA_NAME" --resource-group "$RESOURCE_GROUP_NAME" >/dev/null 2>&1; then
    echo "Static Web App $SWA_NAME already exists"
    DEPLOYMENT_TOKEN=$(az staticwebapp secrets list --name "$SWA_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "properties.apiKey" -o tsv)
else
    echo "Creating Static Web App: $SWA_NAME"
    az staticwebapp create \
      --name "$SWA_NAME" \
      --resource-group "$RESOURCE_GROUP_NAME" \
      --source "https://github.com/$APP_REPO" \
      --location "$LOCATION" \
      --branch "master" \
      --app-location "_site" \
      --output-location "" \
      --login-with-github

    if [ $? -eq 0 ]; then
        echo "✓ Static Web App created successfully"
        DEPLOYMENT_TOKEN=$(az staticwebapp secrets list --name "$SWA_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "properties.apiKey" -o tsv)
    else
        echo "❌ Failed to create Static Web App"
        exit 1
    fi
fi

echo ""
echo "=== Step 3: Create/Update Azure AD App Registration ==="
SWA_URL="https://${SWA_NAME}.azurestaticapps.net"

# Check if app registration exists
if APP_ID=$(az ad app list --display-name "$APP_REG_NAME" --query "[0].appId" -o tsv) && [ -n "$APP_ID" ]; then
    echo "App registration $APP_REG_NAME already exists with ID: $APP_ID"
else
    echo "Creating app registration: $APP_REG_NAME"
    APP_ID=$(az ad app create \
      --display-name "$APP_REG_NAME" \
      --web-redirect-uris "$SWA_URL/.auth/login/aad/callback" \
      --query "appId" -o tsv)

    if [ $? -eq 0 ]; then
        echo "✓ Created app registration with ID: $APP_ID"
    else
        echo "❌ Failed to create app registration"
        exit 1
    fi
fi

# Create/reset client secret
echo "Creating new client secret..."
CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --query "password" -o tsv)

if [ $? -eq 0 ]; then
    echo "✓ Client secret created"
else
    echo "❌ Failed to create client secret"
    exit 1
fi

echo ""
echo "=== Step 4: Store secrets in Key Vault ==="
# Store application secrets in Key Vault
echo "Storing SWA secrets in Key Vault: $VAULT_NAME"

az keyvault secret set --vault-name "$VAULT_NAME" --name "${CLIENT_NAME}-swa-client-id" --value "$APP_ID" >/dev/null
az keyvault secret set --vault-name "$VAULT_NAME" --name "${CLIENT_NAME}-swa-client-secret" --value "$CLIENT_SECRET" >/dev/null
az keyvault secret set --vault-name "$VAULT_NAME" --name "${CLIENT_NAME}-swa-deployment-token" --value "$DEPLOYMENT_TOKEN" >/dev/null

if [ $? -eq 0 ]; then
    echo "✓ Secrets stored in Key Vault"
else
    echo "❌ Failed to store secrets in Key Vault"
    exit 1
fi

echo ""
echo "=== Step 5: Configure Static Web App Settings ==="
# Set application settings for authentication
echo "Setting Static Web App application settings..."
az staticwebapp appsettings set \
  --name "$SWA_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --setting-names "AZURE_CLIENT_ID=$APP_ID" "AZURE_CLIENT_SECRET=$CLIENT_SECRET"

if [ $? -eq 0 ]; then
    echo "✓ Application settings configured"
else
    echo "❌ Failed to configure application settings"
    exit 1
fi

echo ""
echo "=== Step 6: Set up user permissions ==="
# Get Static Web App resource ID for role assignment
SWA_ID=$(az staticwebapp show --name "$SWA_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "id" -o tsv)

# Assign Contributor role to app owner
echo "Assigning Static Web App Contributor role to $APP_OWNER..."
az role assignment create \
  --assignee "$APP_OWNER" \
  --role "Static Web App Contributor" \
  --scope "$SWA_ID" 2>/dev/null

# Invite user to the Static Web App (this might fail if user doesn't exist in tenant yet)
echo "Inviting user to Static Web App..."
az staticwebapp users invite \
  --name "$SWA_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --authentication-provider "AAD" \
  --user-details "$APP_OWNER" \
  --roles "authenticated" \
  --invitation-expiration-in-hours 24 2>/dev/null || echo "Note: User invitation may require manual setup"

echo ""
echo "===== Provisioning Complete ====="
echo "✅ Static Web App: $SWA_NAME"
echo "✅ App Registration: $APP_REG_NAME (ID: $APP_ID)"
echo "✅ Static Web App URL: $SWA_URL"
echo "✅ Authentication configured"
echo "✅ Secrets stored in Key Vault: $VAULT_NAME"
echo ""
echo "Next steps:"
echo "1. The Static Web App is ready for deployment"
echo "2. Run the deploy-app action to build and deploy the application"
echo "3. Configure custom domain if needed: $CUSTOM_DOMAIN"
echo "4. Test authentication and data access"

# Store outputs for potential use by other jobs
echo "SWA_NAME=$SWA_NAME" >> "$GITHUB_OUTPUT" 2>/dev/null || true
echo "APP_ID=$APP_ID" >> "$GITHUB_OUTPUT" 2>/dev/null || true
echo "SWA_URL=$SWA_URL" >> "$GITHUB_OUTPUT" 2>/dev/null || true
echo "DEPLOYMENT_TOKEN=$DEPLOYMENT_TOKEN" >> "$GITHUB_OUTPUT" 2>/dev/null || true

echo "====================================="