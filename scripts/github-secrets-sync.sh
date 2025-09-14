#!/bin/bash
# GitHub Secrets Sync Script for 03_serverless_dash
# This script syncs configuration values to GitHub secrets for use in workflows
# Creates client-specific environment and stores secrets in that environment
#
# Key Retrieval Hierarchy:
# 1. Primary: Azure Key Vault ${CLIENT_NAME}-kv secret 'client-config'
# 2. Secondary: Local configs/${CLIENT_NAME}.env file (for missing keys only)
#
# Usage: ./github-secrets-sync.sh <client_name>

CLIENT_NAME=${1:-""}
if [ -z "$CLIENT_NAME" ]; then
  echo "Error: Client name is required"
  echo "Usage: $0 <client_name>"
  exit 1
fi

# Secondary source - local config file
SEED_CONFIG="./configs/${CLIENT_NAME}.env"

# Check if we have a local config file (needed for bootstrap keys)
if [ ! -f "$SEED_CONFIG" ]; then
  echo "Warning: Local configuration not found: $SEED_CONFIG"
  echo "Proceeding with Key Vault only (may fail if bootstrap keys are needed)"
fi

echo "Starting secrets sync for client: $CLIENT_NAME"

# Function to get value from local config
get_local_config() {
  local key=$1
  if [ -f "$SEED_CONFIG" ]; then
    grep "^${key}=" "$SEED_CONFIG" 2>/dev/null | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
  fi
}

# Function to set environment variable from either source
set_env_var() {
  local key=$1
  local kv_value=$2

  if [ -n "$kv_value" ]; then
    export $key="$kv_value"
    echo "✓ $key: Using Key Vault value"
  else
    local_value=$(get_local_config "$key")
    if [ -n "$local_value" ]; then
      export $key="$local_value"
      echo "◦ $key: Using local config fallback"
    else
      echo "⚠ $key: Not found in Key Vault or local config"
    fi
  fi
}

# First, try to get bootstrap keys from local config for authentication
echo ""
echo "=== Loading Bootstrap Keys ==="
GH_TOKEN=$(get_local_config "GH_TOKEN")
AZURE_SUBSCRIPTION_ID=$(get_local_config "AZURE_SUBSCRIPTION_ID")
PROVISIONER_RESOURCE_GROUP=$(get_local_config "PROVISIONER_RESOURCE_GROUP")
PROVISIONER_IDENTITY_NAME=$(get_local_config "PROVISIONER_IDENTITY_NAME")

if [ -z "$GH_TOKEN" ]; then
  echo "Error: GH_TOKEN is required for GitHub authentication"
  echo "Please add it to $SEED_CONFIG"
  exit 1
fi

# Azure subscription is optional - will use current if not specified
if [ -n "$AZURE_SUBSCRIPTION_ID" ]; then
  echo "✓ AZURE_SUBSCRIPTION_ID: Found ($AZURE_SUBSCRIPTION_ID)"
else
  echo "◦ AZURE_SUBSCRIPTION_ID: Not found, will use current subscription"
fi

if [ -n "$PROVISIONER_RESOURCE_GROUP_NAME" ]; then
  echo "✓ PROVISIONER_RESOURCE_GROUP_NAME: Found ($PROVISIONER_RESOURCE_GROUP_NAME)"
else
  echo "◦ PROVISIONER_RESOURCE_GROUP_NAME: Not found, will set default if needed"
fi

if [ -n "$PROVISIONER_IDENTITY_NAME" ]; then
  echo "✓ PROVISIONER_IDENTITY_NAME: Found ($PROVISIONER_IDENTITY_NAME)"
else
  echo "◦ PROVISIONER_IDENTITY_NAME: Not found, will set default if needed"
fi

# Set default repo name
APP_REPO=$(get_local_config "APP_REPO")
if [ -z "$APP_REPO" ]; then
  APP_REPO="Tidy-Analytics/03_serverless_dash"
  echo "◦ APP_REPO: Using default ($APP_REPO)"
else
  echo "✓ APP_REPO: $APP_REPO"
fi

echo ""
echo "=== Authenticating Services ==="

# Authenticate with GitHub
echo "Authenticating with GitHub..."
gh auth login --with-token <<< "$GH_TOKEN"

# Authenticate with Azure using existing CLI session
echo "Authenticating with Azure..."
echo "Using existing CLI session..."
# Verify we're logged in
if ! az account show >/dev/null 2>&1; then
  echo "Error: Not logged in to Azure CLI. Please run 'az login' first."
  exit 1
fi

# Set subscription if specified
if [ -n "$AZURE_SUBSCRIPTION_ID" ]; then
  echo "Setting subscription to: $AZURE_SUBSCRIPTION_ID"
  az account set --subscription "$AZURE_SUBSCRIPTION_ID"
fi

echo ""
echo "=== Retrieving Configuration from Key Vault ==="

# Try to get client configuration from Key Vault
VAULT_NAME="${CLIENT_NAME}-kv"
echo "Retrieving client-config from Key Vault: $VAULT_NAME"

# Create temporary files for processing
TEMP_KV_CONFIG=$(mktemp)
TEMP_COMBINED_CONFIG=$(mktemp)

# Try to retrieve from Key Vault
if az keyvault secret show --vault-name "$VAULT_NAME" --name "client-config" --query value -o tsv > "$TEMP_KV_CONFIG" 2>/dev/null; then
  echo "✓ Retrieved client-config from Key Vault"

  # Parse Key Vault config into associative array
  declare -A kv_config
  while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ "$key" =~ ^#.*$ ]] || [[ -z "$key" ]] && continue
    # Clean up key and value
    key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
    if [[ "$key" =~ ^[A-Za-z0-9_]+$ ]] && [ -n "$value" ]; then
      kv_config["$key"]="$value"
    fi
  done < "$TEMP_KV_CONFIG"

  echo "✓ Parsed $(( ${#kv_config[@]} )) keys from Key Vault"
else
  echo "⚠ Could not retrieve client-config from Key Vault $VAULT_NAME"
  echo "  Will rely on local configuration only"
  declare -A kv_config
fi

echo ""
echo "=== Building Combined Configuration ==="

# Define all keys we need for this application
REQUIRED_KEYS=(
  "CLIENT_NAME"
  "RESOURCE_GROUP_NAME"
  "LOCATION"
  "CUSTOM_DOMAIN"
  "APP_OWNER"
  "APP_OWNER_NAME"
  "ORG_NAME"
  "STORAGE_ACCOUNT"
  "IN_CONTAINER"
  "VAULT_NAME"
  "IDENTITY_NAME"
  "AZURE_CLIENT_ID"
  "AZURE_TENANT_ID"
  "AZURE_SUBSCRIPTION_ID"
  "PROVISIONER_RESOURCE_GROUP"
  "PROVISIONER_IDENTITY_NAME"
  "APP_REPO"
)

# Load Azure credentials for the secrets (not for auth, but for storage as secrets)
AZURE_CLIENT_ID=$(get_local_config "AZURE_CLIENT_ID")
AZURE_TENANT_ID=$(get_local_config "AZURE_TENANT_ID")

# Build combined configuration using hierarchy
echo "Building configuration using hierarchy (Key Vault → Local Config):"
for key in "${REQUIRED_KEYS[@]}"; do
  set_env_var "$key" "${kv_config[$key]}"
done

# Set default values for keys that might not be configured yet
if [ -z "$RESOURCE_GROUP_NAME" ]; then
  export RESOURCE_GROUP_NAME="${CLIENT_NAME}-rg"
  echo "◦ RESOURCE_GROUP_NAME: Using default (${CLIENT_NAME}-rg)"
fi

if [ -z "$STORAGE_ACCOUNT" ]; then
  export STORAGE_ACCOUNT="${CLIENT_NAME,,}storage"
  echo "◦ STORAGE_ACCOUNT: Using default (${CLIENT_NAME,,}storage)"
fi

if [ -z "$IN_CONTAINER" ]; then
  export IN_CONTAINER="${CLIENT_NAME}-in"
  echo "◦ IN_CONTAINER: Using default (${CLIENT_NAME}-in)"
fi

if [ -z "$VAULT_NAME" ]; then
  export VAULT_NAME="${CLIENT_NAME}-kv"
  echo "◦ VAULT_NAME: Using default (${CLIENT_NAME}-kv)"
fi

if [ -z "$IDENTITY_NAME" ]; then
  export IDENTITY_NAME="${CLIENT_NAME}-admin-identity"
  echo "◦ IDENTITY_NAME: Using default (${CLIENT_NAME}-admin-identity)"
fi

if [ -z "$PROVISIONER_RESOURCE_GROUP" ]; then
  export PROVISIONER_RESOURCE_GROUP="external-tenant-testing"
  echo "◦ PROVISIONER_RESOURCE_GROUP: Using default (external-tenant-testing)"
fi

if [ -z "$PROVISIONER_IDENTITY_NAME" ]; then
  export PROVISIONER_IDENTITY_NAME="client-provisioner"
  echo "◦ PROVISIONER_IDENTITY_NAME: Using default (client-provisioner)"
fi

echo ""
echo "=== Creating GitHub Environment ==="

# Create GitHub environment
echo "Creating GitHub environment: $CLIENT_NAME"
environment_exists=$(gh api "repos/$APP_REPO/environments/$CLIENT_NAME" --silent 2>/dev/null || echo "false")

if [[ "$environment_exists" == "false" ]]; then
  echo "Creating new environment..."
  gh api "repos/$APP_REPO/environments/$CLIENT_NAME" -X PUT
else
  echo "Environment already exists."
fi

echo ""
echo "=== Syncing Secrets to GitHub Environment ==="

# Sync all configuration to GitHub environment secrets
for key in "${REQUIRED_KEYS[@]}"; do
  value="${!key}"
  if [[ -n "$value" ]]; then
    echo "Setting GitHub environment secret: $key"
    echo "$value" | gh secret set "$key" --env "$CLIENT_NAME" -R "$APP_REPO"
  fi
done

echo ""
echo "=== Creating Consolidated JSON Configuration ==="

# Create consolidated JSON configuration secret
json_content="{"
first_item=true

for key in "${REQUIRED_KEYS[@]}"; do
  value="${!key}"
  if [[ -n "$value" && "$key" != "GH_TOKEN" ]]; then
    if [ "$first_item" = true ]; then
      first_item=false
    else
      json_content="${json_content},"
    fi

    # Escape any double quotes in the value
    value=${value//\"/\\\"}
    json_content="${json_content}\"${key}\":\"${value}\""
  fi
done

json_content="${json_content}}"
echo "$json_content" | gh secret set "CONFIG" --env "$CLIENT_NAME" -R "$APP_REPO"

echo ""
echo "===== Secret Sync Complete ====="
echo "Client: $CLIENT_NAME"
echo "Repository: $APP_REPO"
echo "Environment: $CLIENT_NAME"
echo "Configuration synced successfully!"

echo ""
echo "Setting up federated credential for GitHub Actions..."
#./scripts/github-fedcred-setup.sh "$CLIENT_NAME"

# Cleanup
rm -f "$TEMP_KV_CONFIG" "$TEMP_COMBINED_CONFIG"
