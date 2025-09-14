#!/bin/bash

# GitHub Federated Credentials Setup Script for 03_serverless_dash
# This script creates a federated credential for GitHub Actions to use with Azure identity
# Should be run after setting up GitHub secrets
#
# Creates environment-scoped federated credential:
# Subject: repo:Tidy-Analytics/03_serverless_dash:environment:${CLIENT_NAME}

# Check if client name was provided
CLIENT_NAME=${1:-""}
if [ -z "$CLIENT_NAME" ]; then
    echo "Error: Client name is required"
    echo "Usage: $0 <client_name>"
    exit 1
fi

echo "Setting up federated credential for client: $CLIENT_NAME"

# Function to get value from local config if available
get_local_config() {
  local key=$1
  local config_file="./configs/${CLIENT_NAME}.env"
  if [ -f "$config_file" ]; then
    grep "^${key}=" "$config_file" 2>/dev/null | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
  fi
}

# Try to get configuration from multiple sources
echo "Retrieving configuration..."

# Try Key Vault first, then fall back to local config
KEYVAULT_NAME="${CLIENT_NAME}-kv"
if az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "client-config" --query value -o tsv > /tmp/kv_config 2>/dev/null; then
    echo "✓ Retrieved configuration from Key Vault: $KEYVAULT_NAME"

    # Parse Key Vault config
    AZURE_SUBSCRIPTION_ID=$(grep "^AZURE_SUBSCRIPTION_ID=" /tmp/kv_config | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//')
    PROVISIONER_RESOURCE_GROUP=$(grep "^PROVISIONER_RESOURCE_GROUP=" /tmp/kv_config | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//')
    PROVISIONER_IDENTITY_NAME=$(grep "^PROVISIONER_IDENTITY_NAME=" /tmp/kv_config | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//')
    AZURE_CLIENT_ID=$(grep "^AZURE_CLIENT_ID=" /tmp/kv_config | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//')
    AZURE_TENANT_ID=$(grep "^AZURE_TENANT_ID=" /tmp/kv_config | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//')

    rm -f /tmp/kv_config
else
    echo "⚠ Could not retrieve from Key Vault, trying local config..."

    # Fall back to local config
    AZURE_SUBSCRIPTION_ID=$(get_local_config "AZURE_SUBSCRIPTION_ID")
    PROVISIONER_RESOURCE_GROUP=$(get_local_config "PROVISIONER_RESOURCE_GROUP")
    PROVISIONER_IDENTITY_NAME=$(get_local_config "PROVISIONER_IDENTITY_NAME")
    AZURE_CLIENT_ID=$(get_local_config "AZURE_CLIENT_ID")
    AZURE_TENANT_ID=$(get_local_config "AZURE_TENANT_ID")
fi

# Set defaults if not found
if [ -z "$PROVISIONER_RESOURCE_GROUP" ]; then
    PROVISIONER_RESOURCE_GROUP="external-tenant-testing"
    echo "◦ PROVISIONER_RESOURCE_GROUP: Using default ($PROVISIONER_RESOURCE_GROUP)"
fi

if [ -z "$PROVISIONER_IDENTITY_NAME" ]; then
    PROVISIONER_IDENTITY_NAME="client-provisioner"
    echo "◦ PROVISIONER_IDENTITY_NAME: Using default ($PROVISIONER_IDENTITY_NAME)"
fi

# Set default repo name
REPO_NAME="Tidy-Analytics/03_serverless_dash"

# Validate required variables
if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
    echo "Error: Azure subscription ID (AZURE_SUBSCRIPTION_ID) is required"
    exit 1
fi

if [ -z "$AZURE_CLIENT_ID" ]; then
    echo "Error: Azure client ID (AZURE_CLIENT_ID) is required"
    exit 1
fi

if [ -z "$AZURE_TENANT_ID" ]; then
    echo "Error: Azure tenant ID (AZURE_TENANT_ID) is required"
    exit 1
fi

echo ""
echo "Configuration summary:"
echo "  Client: $CLIENT_NAME"
echo "  Subscription: $AZURE_SUBSCRIPTION_ID"
echo "  Provisioner Resource Group: $PROVISIONER_RESOURCE_GROUP"
echo "  Provisioner Identity: $PROVISIONER_IDENTITY_NAME"
echo "  Repository: $REPO_NAME"

echo ""
echo "Creating federated credential for GitHub Actions..."

# Create federated credential name
FED_CRED_NAME="github-${CLIENT_NAME}-03-serverless-dash"

# Full identity resource ID
IDENTITY_ID="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourcegroups/${PROVISIONER_RESOURCE_GROUP}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${PROVISIONER_IDENTITY_NAME}"

# Set up the subject based on repo and environment
SUBJECT="repo:${REPO_NAME}:environment:${CLIENT_NAME}"

echo "Creating federated credential: $FED_CRED_NAME"
echo "Subject: $SUBJECT"

# Check if federated credential already exists
if az identity federated-credential show \
  --resource-group "$PROVISIONER_RESOURCE_GROUP" \
  --identity-name "$PROVISIONER_IDENTITY_NAME" \
  --name "$FED_CRED_NAME" >/dev/null 2>&1; then

    echo "Federated credential already exists, updating..."

    # Update existing credential
    az identity federated-credential update \
      --name "$FED_CRED_NAME" \
      --resource-group "$PROVISIONER_RESOURCE_GROUP" \
      --identity-name "$PROVISIONER_IDENTITY_NAME" \
      --issuer "https://token.actions.githubusercontent.com" \
      --subject "$SUBJECT" \
      --audiences "api://AzureADTokenExchange"
else
    echo "Creating new federated credential..."

    # Create new federated credential
    az identity federated-credential create \
      --name "$FED_CRED_NAME" \
      --resource-group "$PROVISIONER_RESOURCE_GROUP" \
      --identity-name "$PROVISIONER_IDENTITY_NAME" \
      --issuer "https://token.actions.githubusercontent.com" \
      --subject "$SUBJECT" \
      --audiences "api://AzureADTokenExchange"
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "===== Federated Credential Setup Complete ====="
    echo "Client: $CLIENT_NAME"
    echo "Identity: $PROVISIONER_IDENTITY_NAME ($PROVISIONER_RESOURCE_GROUP)"
    echo "Repository: $REPO_NAME"
    echo "Environment: $CLIENT_NAME"
    echo "Credential: $FED_CRED_NAME"
    echo "Subject: $SUBJECT"
    echo "✅ Federated credential configured successfully!"
    echo ""
    echo "GitHub Actions workflows can now authenticate using:"
    echo "  environment: $CLIENT_NAME"
    echo "  client-id: \${{ secrets.AZURE_CLIENT_ID }}"
    echo "  tenant-id: \${{ secrets.AZURE_TENANT_ID }}"
    echo "  subscription-id: \${{ secrets.AZURE_SUBSCRIPTION_ID }}"
else
    echo "❌ Error: Failed to create federated credential"
    exit 1
fi