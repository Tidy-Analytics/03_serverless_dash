#!/bin/bash

# GitHub Federated Credentials Setup Script
# This script creates a federated credential for GitHub Actions to use with Azure identity
# Should be run after setting up GitHub secrets

# Check if client name was provided
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
    exit 1
fi

# Load client-specific configuration
source "$SEED_CONFIG"

# Check for required variables
if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
    echo "Error: Azure subscription ID (AZURE_SUBSCRIPTION_ID) is required in $SEED_CONFIG"
    exit 1
fi

if [ -z "$PROVISIONER_RESOURCE_GROUP" ]; then
    echo "Error: Azure provisioner resource group name (PROVISIONER_RESOURCE_GROUP) is required in $SEED_CONFIG"
    exit 1
fi

if [ -z "$PROVISIONER_IDENTITY_NAME" ]; then
    echo "Error: Azure provisioner identity name (PROVISIONER_IDENTITY_NAME) is required in $SEED_CONFIG"
    exit 1
fi

if [ -z "$APP_REPO" ]; then
    echo "Error: GitHub repository name (APP_REPO) is required in $SEED_CONFIG"
    echo "Please add the repository name (format: owner/repo) to the configuration file"
    exit 1
fi

if [ -z "$AZURE_CLIENT_ID" ]; then
    echo "Error: Azure client ID (AZURE_CLIENT_ID) is required in $SEED_CONFIG"
    exit 1
fi

if [ -z "$AZURE_TENANT_ID" ]; then
    echo "Error: Azure tenant ID (AZURE_TENANT_ID) is required in $SEED_CONFIG"
    exit 1
fi

echo "Creating federated credential for GitHub Actions..."

# Create federated credential
FED_CRED_NAME="github-${CLIENT_NAME}-fedcred"

# Full identity resource ID
IDENTITY_ID="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourcegroups/${PROVISIONER_RESOURCE_GROUP}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${PROVISIONER_IDENTITY_NAME}"

# Set up the subject based on repo and environment
SUBJECT="repo:${APP_REPO}:environment:${CLIENT_NAME}"

# Create the federated credential
echo "Creating federated credential: $FED_CRED_NAME"
az identity federated-credential create \
  --name "$FED_CRED_NAME" \
  --resource-group "$PROVISIONER_RESOURCE_GROUP" \
  --identity-name "$PROVISIONER_IDENTITY_NAME" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "$SUBJECT" \
  --audiences "api://AzureADTokenExchange"

if [ $? -eq 0 ]; then
    echo "===== Federated Credential Setup Complete ====="
    echo "Client: $CLIENT_NAME"
    echo "Identity: $IDENTITY_NAME"
    echo "Repository: $APP_REPO"
    echo "Environment: $CLIENT_NAME"
    echo "Federated credential created successfully!"
else
    echo "Error: Failed to create federated credential"
    exit 1
fi