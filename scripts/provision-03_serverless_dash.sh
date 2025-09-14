#!/bin/bash

# Required arguments now from config
CLIENT_NAME=${1:-""}
if [ -z "$CLIENT_NAME" ]; then
    echo "Error: Client name is required"
    echo "Usage: $0 <client_name>"
    exit 1
fi

# Load client-specific configuration
SEED_CONFIG="./configs/${CLIENT_NAME}.env"
if [ ! -f "$SEED_CONFIG" ]; then
    echo "Warning: Local client configuration not found: $SEED_CONFIG"
    echo "Attempting to load configuration from GitHub secrets..."

    # Check if we have the GitHub CLI and token
    if ! command -v gh &> /dev/null || [ -z "$GH_TOKEN" ]; then
        echo "Error: GitHub CLI or token not available, cannot retrieve secrets"
        exit 1
    fi

    # Authenticate with GitHub
    gh auth login --with-token <<< "$GH_TOKEN"

    # Get consolidated config from GitHub secrets
    CONFIG_SECRET=${CONFIG}

    if [ -z "$CONFIG_SECRET" ]; then
        echo "Error: GitHub secret $CONFIG_SECRET not found"
        exit 1
    fi

    # Extract values from JSON and export as environment variables
    while IFS="=" read -r key value; do
        if [ -n "$key" ] && [ -n "$value" ]; then
            export "$key"="$value"
            echo "Loaded from GitHub: $key"
        fi
    done < <(echo "$CONFIG_SECRET" | jq -r 'to_entries | map("\(.key)=\(.value)") | .[]')

    echo "Successfully loaded configuration from GitHub secrets"
else
    # Load client-specific configuration from file
    source "$SEED_CONFIG"
fi

# Set defaults for required values - Updated for 03_serverless_dash
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID:-""}
LOCATION=${LOCATION:-"CentralUS"}
REPO_NAME=${REPO_NAME:-"Tidy-Analytics/03_serverless_dash"}
REPO_URL=${REPO_URL:-"https://github.com/Tidy-Analytics/03_serverless_dash"}
ADMIN_EMAIL=${ADMIN_EMAIL:-""}
ADMIN_IP=${ADMIN_IP:-""}
GH_TOKEN="${GH_TOKEN:-}"
CONFIG="${CONFIG:-""}"

APP_OWNER=${APP_OWNER:-""}
APP_OWNER_NAME=${APP_OWNER_NAME:-""}
ORG_NAME=${ORG_NAME:-""}
TEMP_PW=${TEMP_PW:-""}

# Add validation
if [ -z "$APP_OWNER" ]; then
    echo "Error: APP_OWNER email is required in configuration"
    echo "Please ensure APP_OWNER is set in $SEED_CONFIG"
    exit 1
fi

if [ -z "$APP_OWNER_NAME" ]; then
    echo "Error: APP_OWNER_NAME is required in configuration"
    echo "Please ensure APP_OWNER_NAME is set in $SEED_CONFIG"
    exit 1
fi

if [ -z "$ORG_NAME" ]; then
    echo "Error: ORG_NAME is required in configuration"
    echo "Please ensure ORG_NAME is set in $SEED_CONFIG"
    exit 1
fi

if [ -z "$TEMP_PW" ]; then
    echo "Error: TEMP_PW is required in configuration"
    echo "Please ensure TEMP_PW is set in $SEED_CONFIG"
    exit 1
fi

if [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_IP" ]; then
    echo "Error: ADMIN_EMAIL and ADMIN_IP are required in configuration"
    echo "Please ensure these are set in $SEED_CONFIG"
    exit 1
fi

# Create config directory if it doesn't exist
mkdir -p ./configs
config_file="./configs/${CLIENT_NAME}_config.sh"

echo "Starting provisioning for client: $CLIENT_NAME (03_serverless_dash Quarto app)"

# Step 1: Create Resource Group
echo "Creating resource group..."
az group create --name "${CLIENT_NAME}-rg" --location "$LOCATION"

# Step 2: Create Managed Identity for Static Web App
echo "Creating managed identity for Static Web App..."
staticWebAppIdentity=$(az identity create \
  --name "${CLIENT_NAME}-swa-identity" \
  --resource-group "${CLIENT_NAME}-rg" \
  --location "$LOCATION" \
  --output json)
staticWebAppIdentityId=$(echo $staticWebAppIdentity | jq -r '.id')
staticWebAppIdentityClientId=$(echo $staticWebAppIdentity | jq -r '.clientId')
staticWebAppIdentityObjectId=$(echo $staticWebAppIdentity | jq -r '.principalId')

# Step 3: Create federated credentials for the managed identity
echo "Creating federated credentials..."
az identity federated-credential create \
  --name "github-federated-credential" \
  --identity-name "${CLIENT_NAME}-swa-identity" \
  --resource-group "${CLIENT_NAME}-rg" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:${REPO_NAME}:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange"

# Also create credential for master branch (common pattern)
az identity federated-credential create \
  --name "github-federated-credential-master" \
  --identity-name "${CLIENT_NAME}-swa-identity" \
  --resource-group "${CLIENT_NAME}-rg" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:${REPO_NAME}:ref:refs/heads/master" \
  --audiences "api://AzureADTokenExchange"

# Step 4: Assign Roles to Managed Identity
echo "Assigning roles to managed identity..."
az role assignment create \
   --assignee-object-id $staticWebAppIdentityObjectId \
   --assignee-principal-type ServicePrincipal \
   --role "Contributor" \
   --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/${CLIENT_NAME}-rg"

# Step 5: Create Azure Static Web App
echo "Creating Azure Static Web App..."
staticWebAppName="${CLIENT_NAME}-dashboard"
az staticwebapp create \
  --name $staticWebAppName \
  --resource-group "${CLIENT_NAME}-rg" \
  --location "$LOCATION" \
  --source "$REPO_URL" \
  --branch "main" \
  --app-location "/" \
  --output-location "_site" \
  --login-with-github

# Get the Static Web App details
staticWebAppDetails=$(az staticwebapp show \
  --name $staticWebAppName \
  --resource-group "${CLIENT_NAME}-rg" \
  --output json)
staticWebAppUrl=$(echo $staticWebAppDetails | jq -r '.defaultHostName')
staticWebAppId=$(echo $staticWebAppDetails | jq -r '.id')

echo "Static Web App created: https://$staticWebAppUrl"

# Step 6: Retrieve existing storage account info from 00_clientinfra setup
# This assumes the client already has storage set up from 00_clientinfra
echo "Retrieving existing storage account information..."
storageAccountName="${CLIENT_NAME,,}storage"
storageKey=$(az storage account keys list \
  --account-name $storageAccountName \
  --resource-group "${CLIENT_NAME}-rg" \
  --query '[0].value' -o tsv)

if [ -z "$storageKey" ]; then
    echo "Warning: Storage account not found. Creating new storage account..."
    az storage account create \
      --name $storageAccountName \
      --resource-group "${CLIENT_NAME}-rg" \
      --location "$LOCATION" \
      --sku Standard_LRS \
      --default-action Allow \
      --allow-blob-public-access false

    # Create the input container if it doesn't exist
    az storage container create \
      --account-key $storageKey \
      --account-name $storageAccountName \
      --name "${CLIENT_NAME}-in"

    storageKey=$(az storage account keys list \
      --account-name $storageAccountName \
      --resource-group "${CLIENT_NAME}-rg" \
      --query '[0].value' -o tsv)
fi

# Step 7: Create Key Vault (if not exists)
echo "Creating/updating Key Vault..."
vault_name="${CLIENT_NAME}-kv"
az keyvault create \
  --name $vault_name \
  --resource-group "${CLIENT_NAME}-rg" \
  --location "$LOCATION" || echo "Key Vault may already exist"

# Step 8: Generate SAS token for blob access
echo "Generating SAS token for blob access..."
EXPIRY_DATE=$(date -u -d '+7 days' '+%Y-%m-%dT%H:%MZ')

sas_token_read=$(az storage account generate-sas \
  --account-name $storageAccountName \
  --account-key $storageKey \
  --services b \
  --resource-types sco \
  --permissions rl \
  --expiry $EXPIRY_DATE \
  --output tsv)

# Step 9: Store configuration in Key Vault
echo "Storing configuration in Key Vault..."

# Store all the important configuration values
az keyvault secret set --vault-name $vault_name --name "storage-account-name" --value $storageAccountName
az keyvault secret set --vault-name $vault_name --name "storage-sas-token" --value $sas_token_read
az keyvault secret set --vault-name $vault_name --name "static-web-app-name" --value $staticWebAppName
az keyvault secret set --vault-name $vault_name --name "static-web-app-url" --value $staticWebAppUrl
az keyvault secret set --vault-name $vault_name --name "blob-container-name" --value "${CLIENT_NAME}-in"
az keyvault secret set --vault-name $vault_name --name "custom-domain" --value "${CLIENT_NAME}.tidyanalytics.com"

# Step 10: Create GitHub secrets for the workflow
echo "Creating GitHub secrets..."
gh secret set "${CLIENT_NAME}_AZURE_CLIENT_ID" --body "$staticWebAppIdentityClientId" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_AZURE_TENANT_ID" --body "$AZURE_TENANT_ID" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_AZURE_SUBSCRIPTION_ID" --body "$AZURE_SUBSCRIPTION_ID" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_RESOURCE_GROUP" --body "${CLIENT_NAME}-rg" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_LOCATION" --body "$LOCATION" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_CUSTOM_DOMAIN" --body "${CLIENT_NAME}.tidyanalytics.com" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_STORAGE_ACCOUNT_NAME" --body "$storageAccountName" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_STORAGE_SAS_TOKEN" --body "$sas_token_read" --repo "$REPO_NAME"
gh secret set "${CLIENT_NAME}_BLOB_CONTAINER_NAME" --body "${CLIENT_NAME}-in" --repo "$REPO_NAME"

# Step 11: Output summary
echo "=================================================="
echo "03_serverless_dash Provisioning Complete!"
echo "=================================================="
echo "Client: $CLIENT_NAME"
echo "Resource Group: ${CLIENT_NAME}-rg"
echo "Static Web App: $staticWebAppName"
echo "Static Web App URL: https://$staticWebAppUrl"
echo "Custom Domain: ${CLIENT_NAME}.tidyanalytics.com"
echo "Storage Account: $storageAccountName"
echo "Blob Container: ${CLIENT_NAME}-in"
echo "Key Vault: $vault_name"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Configure custom domain in Azure Static Web Apps"
echo "2. Upload customer data to blob container: ${CLIENT_NAME}-in"
echo "3. Run GitHub Actions workflow to deploy the Quarto app"
echo "4. Set up Microsoft authentication (if needed)"
echo ""
echo "GitHub secrets have been configured for client: $CLIENT_NAME"

# Save configuration to local file
cat > "$config_file" << EOF
# 03_serverless_dash Configuration for $CLIENT_NAME
# Generated on $(date)

CLIENT_NAME=$CLIENT_NAME
RESOURCE_GROUP=${CLIENT_NAME}-rg
STATIC_WEB_APP_NAME=$staticWebAppName
STATIC_WEB_APP_URL=https://$staticWebAppUrl
STATIC_WEB_APP_IDENTITY_CLIENT_ID=$staticWebAppIdentityClientId
STORAGE_ACCOUNT_NAME=$storageAccountName
BLOB_CONTAINER_NAME=${CLIENT_NAME}-in
KEY_VAULT_NAME=$vault_name
CUSTOM_DOMAIN=${CLIENT_NAME}.tidyanalytics.com
REPO_NAME=$REPO_NAME
REPO_URL=$REPO_URL
EOF

echo "Configuration saved to: $config_file"