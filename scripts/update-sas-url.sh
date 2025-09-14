#!/bin/bash

set -e

# Script to update SAS URL for a client
# Usage: ./update-sas-url.sh <client_name> [days_to_expiry]

# Function to display usage
show_usage() {
    echo "Usage: $0 <client_name> [days_to_expiry]"
    echo "  client_name: Name of the client to update SAS URL for"
    echo "  days_to_expiry: Number of days until expiry (default: 7)"
    echo ""
    echo "Example: $0 dmdk 14"
    exit 1
}

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if client name is provided
if [ -z "$1" ]; then
    echo "Error: Client name is required"
    show_usage
fi

CLIENT_NAME="$1"
DAYS_TO_EXPIRY="${2:-7}"

log "Starting SAS URL update for client: $CLIENT_NAME"
log "Setting expiry to $DAYS_TO_EXPIRY days from now"

# Set storage account name (lowercase client name + storage)
STORAGE_ACCOUNT="${CLIENT_NAME,,}storage"

# Get storage account key
log "Getting storage account key for: $STORAGE_ACCOUNT"
STORAGE_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "${CLIENT_NAME}-rg" \
  --query '[0].value' -o tsv)

if [ -z "$STORAGE_KEY" ]; then
    echo "Error: Failed to get storage account key"
    exit 1
fi

# Generate new expiry date
EXPIRY_DATE=$(date -u -d "+${DAYS_TO_EXPIRY} days" '+%Y-%m-%dT%H:%MZ')
log "New expiry date: $EXPIRY_DATE"

# Generate multiple SAS tokens with different permissions
log "Generating SAS tokens with different permission levels"

# Full permissions token (existing functionality)
SAS_TOKEN_FULL=$(az storage account generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$STORAGE_KEY" \
  --services b \
  --resource-types sco \
  --permissions racwdl \
  --expiry "$EXPIRY_DATE" \
  --output tsv)

# Read-only token
SAS_TOKEN_READ=$(az storage account generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$STORAGE_KEY" \
  --services b \
  --resource-types sco \
  --permissions rl \
  --expiry "$EXPIRY_DATE" \
  --output tsv)

# List-only token
SAS_TOKEN_LIST=$(az storage account generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$STORAGE_KEY" \
  --services b \
  --resource-types sco \
  --permissions l \
  --expiry "$EXPIRY_DATE" \
  --output tsv)

# Validate all tokens were generated
if [ -z "$SAS_TOKEN_FULL" ] || [ -z "$SAS_TOKEN_READ" ] || [ -z "$SAS_TOKEN_LIST" ]; then
    echo "Error: Failed to generate one or more SAS tokens"
    exit 1
fi

# Build new SAS URLs for main storage
SAS_URL_FULL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CLIENT_NAME}-in?${SAS_TOKEN_FULL}"
SAS_URL_READ="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CLIENT_NAME}-in?${SAS_TOKEN_READ}"
SAS_URL_LIST="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CLIENT_NAME}-in?${SAS_TOKEN_LIST}"

# Generate web storage SAS tokens
WEB_STORAGE_ACCOUNT="${CLIENT_NAME,,}web"
log "Generating web storage SAS tokens for: $WEB_STORAGE_ACCOUNT"

# Get web storage account key
WEB_STORAGE_KEY=$(az storage account keys list \
  --account-name "$WEB_STORAGE_ACCOUNT" \
  --resource-group "${CLIENT_NAME}-rg" \
  --query '[0].value' -o tsv)

if [ -z "$WEB_STORAGE_KEY" ]; then
    echo "Error: Failed to get web storage account key"
    exit 1
fi

# Web storage full permissions token
WEB_SAS_TOKEN_FULL=$(az storage account generate-sas \
  --account-name "$WEB_STORAGE_ACCOUNT" \
  --account-key "$WEB_STORAGE_KEY" \
  --services b \
  --resource-types sco \
  --permissions racwdl \
  --expiry "$EXPIRY_DATE" \
  --output tsv)

# Web storage read-only token
WEB_SAS_TOKEN_READ=$(az storage account generate-sas \
  --account-name "$WEB_STORAGE_ACCOUNT" \
  --account-key "$WEB_STORAGE_KEY" \
  --services b \
  --resource-types sco \
  --permissions rl \
  --expiry "$EXPIRY_DATE" \
  --output tsv)

# Web storage list-only token
WEB_SAS_TOKEN_LIST=$(az storage account generate-sas \
  --account-name "$WEB_STORAGE_ACCOUNT" \
  --account-key "$WEB_STORAGE_KEY" \
  --services b \
  --resource-types sco \
  --permissions l \
  --expiry "$EXPIRY_DATE" \
  --output tsv)

# Validate all web tokens were generated
if [ -z "$WEB_SAS_TOKEN_FULL" ] || [ -z "$WEB_SAS_TOKEN_READ" ] || [ -z "$WEB_SAS_TOKEN_LIST" ]; then
    echo "Error: Failed to generate one or more web storage SAS tokens"
    exit 1
fi

# Build web storage SAS URLs
WEB_SAS_URL_FULL="https://${WEB_STORAGE_ACCOUNT}.blob.core.windows.net/?${WEB_SAS_TOKEN_FULL}"
WEB_SAS_URL_READ="https://${WEB_STORAGE_ACCOUNT}.blob.core.windows.net/?${WEB_SAS_TOKEN_READ}"
WEB_SAS_URL_LIST="https://${WEB_STORAGE_ACCOUNT}.blob.core.windows.net/?${WEB_SAS_TOKEN_LIST}"

# Maintain backward compatibility
SAS_TOKEN="$SAS_TOKEN_FULL"
NEW_SAS_URL="$SAS_URL_FULL"

log "All SAS tokens and URLs generated successfully"

# Update Azure KeyVault
log "Updating Azure KeyVault"
VAULT_NAME="${CLIENT_NAME}-kv"

# Update individual secrets in KeyVault for 03_serverless_dash
az keyvault secret set --vault-name "$VAULT_NAME" --name "storage-sas-token" --value "$SAS_TOKEN_READ"
az keyvault secret set --vault-name "$VAULT_NAME" --name "sas-token-read" --value "$SAS_TOKEN_READ"
az keyvault secret set --vault-name "$VAULT_NAME" --name "sas-token-full" --value "$SAS_TOKEN_FULL"
az keyvault secret set --vault-name "$VAULT_NAME" --name "sas-token-list" --value "$SAS_TOKEN_LIST"
az keyvault secret set --vault-name "$VAULT_NAME" --name "expiry-date" --value "$EXPIRY_DATE"

log "KeyVault updated successfully"

# Update GitHub Secrets for 03_serverless_dash (only if running in GitHub Actions or if GH_TOKEN is set)
if [ -n "$GITHUB_ACTIONS" ] || [ -n "$GH_TOKEN" ]; then
    log "Updating GitHub repository secrets for 03_serverless_dash"

    # Determine repository name - default to 03_serverless_dash repo
    REPO_NAME="${GITHUB_REPOSITORY:-Tidy-Analytics/03_serverless_dash}"

    if [ -z "$REPO_NAME" ]; then
        echo "Warning: Could not determine repository name, skipping GitHub secrets update"
    else
        # Update the specific client's secrets with new SAS tokens
        gh secret set "${CLIENT_NAME}_STORAGE_SAS_TOKEN" --body "$SAS_TOKEN_READ" --repo "$REPO_NAME"
        gh secret set "${CLIENT_NAME}_SAS_TOKEN_FULL" --body "$SAS_TOKEN_FULL" --repo "$REPO_NAME"
        gh secret set "${CLIENT_NAME}_SAS_TOKEN_READ" --body "$SAS_TOKEN_READ" --repo "$REPO_NAME"
        gh secret set "${CLIENT_NAME}_SAS_TOKEN_LIST" --body "$SAS_TOKEN_LIST" --repo "$REPO_NAME"
        gh secret set "${CLIENT_NAME}_EXPIRY_DATE" --body "$EXPIRY_DATE" --repo "$REPO_NAME"

        log "GitHub secrets updated successfully for client: $CLIENT_NAME"
    fi
else
    log "Skipping GitHub secrets update (not in GitHub Actions and no GH_TOKEN set)"
fi

# Note: 03_serverless_dash uses Static Web Apps, not Container Apps, so we skip the container app update

# Summary
log "SAS URL update completed successfully for client: $CLIENT_NAME"
log "New expiry date: $EXPIRY_DATE"
log "Updated components:"
log "  - Azure KeyVault ($VAULT_NAME)"
if [ -n "$GITHUB_ACTIONS" ] || [ -n "$GH_TOKEN" ]; then
    log "  - GitHub Repository Secrets (${CLIENT_NAME}_*)"
fi
log "  - Static Web App will use updated tokens on next deployment"