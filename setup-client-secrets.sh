#!/bin/bash

# Setup Client Secrets for 03_serverless_dash
# This script copies client secrets from 00_clientinfra configs to GitHub secrets for this repository

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <client_handle>"
    echo "Available clients: bxyz, drby, mmyy, zmmr"
    exit 1
fi

CLIENT_HANDLE=$1
CONFIG_FILE="../00_clientinfra/configs/${CLIENT_HANDLE}.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file $CONFIG_FILE not found"
    exit 1
fi

echo "Setting up GitHub secrets for client: $CLIENT_HANDLE"
echo "Reading from: $CONFIG_FILE"

# Load the .env file
source "$CONFIG_FILE"

# Set GitHub secrets using gh CLI
gh secret set "${CLIENT_HANDLE}_AZURE_CLIENT_ID" --body "$AZURE_CLIENT_ID"
gh secret set "${CLIENT_HANDLE}_AZURE_TENANT_ID" --body "$AZURE_TENANT_ID"
gh secret set "${CLIENT_HANDLE}_AZURE_SUBSCRIPTION_ID" --body "$AZURE_SUBSCRIPTION_ID"
gh secret set "${CLIENT_HANDLE}_RESOURCE_GROUP" --body "$RESOURCE_GROUP"
gh secret set "${CLIENT_HANDLE}_LOCATION" --body "$LOCATION"
gh secret set "${CLIENT_HANDLE}_CUSTOM_DOMAIN" --body "$CUSTOM_DOMAIN"
gh secret set "${CLIENT_HANDLE}_APP_OWNER" --body "$APP_OWNER"

# Optional: Set KeyVault name if it exists in the config
if [ ! -z "$KEYVAULT_NAME" ]; then
    gh secret set "${CLIENT_HANDLE}_KEYVAULT_NAME" --body "$KEYVAULT_NAME"
else
    # Use a convention-based KeyVault name
    KEYVAULT_NAME="${CLIENT_HANDLE}-vault"
    gh secret set "${CLIENT_HANDLE}_KEYVAULT_NAME" --body "$KEYVAULT_NAME"
fi

echo "✅ GitHub secrets configured for client: $CLIENT_HANDLE"
echo ""
echo "You can now run the workflow with:"
echo "gh workflow run azure-static-web-apps.yml -f action=deploy-app -f client_handle=$CLIENT_HANDLE"
echo ""
echo "Or manually deploy via GitHub Actions web interface."