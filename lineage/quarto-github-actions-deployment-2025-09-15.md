# Quarto GitHub Actions Deployment Integration

**Date:** September 15, 2025
**Scope:** Complete GitHub Actions workflow for automated Quarto app deployment to Azure Static Web Apps

## Problem Statement

The 03_serverless_dash project lacked automated deployment capabilities for the Quarto-based dashboard application. Key issues included:

1. **No Automated Build Process**: The Quarto site build (`./_site/`) was in `.gitignore`, requiring manual builds
2. **Missing GitHub Actions Integration**: No CI/CD pipeline for automated deployment to Azure Static Web Apps
3. **Incomplete User Provisioning**: The provisioning script didn't handle user creation/invitation in Entra tenant
4. **Manual Deployment Steps**: Required manual intervention for building and deploying the static site

## Solution Implemented

### 1. Enhanced Provisioning Script

**File Modified:** `scripts/provision-03_serverless_dash.sh`

#### Added User Creation/Invitation Logic
```bash
echo ""
echo "=== Step 3: Create/Invite App Owner User ==="
if [ -n "$APP_OWNER" ]; then
    echo "Checking if user $APP_OWNER exists in tenant..."
    
    # Check if user exists in the tenant
    USER_EXISTS=$(az ad user show --id "$APP_OWNER" --query "id" -o tsv 2>/dev/null || echo "")
    
    if [ -z "$USER_EXISTS" ]; then
        echo "User $APP_OWNER not found in tenant. Attempting to invite as guest user..."
        
        # Invite user as guest (requires Global Administrator or Guest Inviter role)
        INVITATION_RESULT=$(az ad user invite \
          --invited-user-email-address "$APP_OWNER" \
          --invite-redirect-url "https://${CLIENT_NAME}.tidyanalytics.com" \
          --send-invitation-message true \
          --query "id" -o tsv 2>/dev/null || echo "")
```

**Key Features:**
- **Non-interactive User Invitation**: Uses `--send-invitation-message true` for automated guest user invitation
- **Graceful Fallback**: Handles cases where user invitation may fail due to permissions
- **User Validation**: Checks if user already exists before attempting invitation
- **Role Assignment Logic**: Only assigns roles if valid user ID is available

### 2. Complete GitHub Actions Workflow

**File Created:** `.github/workflows/deploy-quarto-app.yml`

#### Workflow Architecture
```yaml
name: Deploy Quarto App to Azure Static Web Apps

on:
  push:
    branches:
      - master
  pull_request:
    types: [opened, synchronize, reopened, closed]
    branches:
      - master
  workflow_dispatch:
    inputs:
      client_name:
        description: 'Client name for deployment'
        required: true
        type: string
```

#### Build Environment Setup
- **Node.js 18**: For JavaScript dependencies and tooling
- **R 4.3.2**: With comprehensive data analysis packages:
  - `knitr`, `rmarkdown` for document rendering
  - `plotly`, `DT`, `htmlwidgets` for interactive visualizations
  - `jsonlite`, `dplyr`, `ggplot2` for data processing
- **Quarto 1.4.549**: Official Quarto GitHub action for site building

#### Security & Authentication
- **OIDC Authentication**: Uses federated credentials for Azure login
- **Environment-based Secrets**: Leverages GitHub environments for client-specific configuration
- **Key Vault Integration**: Retrieves deployment tokens and auth credentials securely
- **Masked Secrets**: Properly masks sensitive values in workflow logs

#### Deployment Process
1. **Infrastructure Provisioning**: Automated execution of `provision-03_serverless_dash.sh`
2. **Quarto Site Build**: `quarto render` generates static assets to `_site/`
3. **Build Verification**: Validates `_site/` directory exists and contains content
4. **Azure SWA Deployment**: Uses `Azure/static-web-apps-deploy@v1` action
5. **Authentication Configuration**: Sets up Microsoft AAD auth from Key Vault credentials

#### Pull Request Support
- **Staging Deployments**: Automatic staging environments for PR reviews
- **Environment Cleanup**: Automated cleanup on PR close
- **Branch Protection**: Only deploys from master for production

### 3. Configuration Integration

#### Environment Variables Structure
```bash
env:
  NODE_VERSION: '18'
  QUARTO_VERSION: '1.4.549'
```

#### Dynamic Configuration Loading
```bash
- name: Load Configuration
  id: config
  run: |
    # Load configuration from environment or secrets
    echo "CLIENT_NAME=${{ github.event.inputs.client_name || secrets.CLIENT_NAME }}" >> $GITHUB_OUTPUT
    echo "RESOURCE_GROUP_NAME=${{ secrets.RESOURCE_GROUP_NAME }}" >> $GITHUB_OUTPUT
    echo "LOCATION=${{ secrets.LOCATION }}" >> $GITHUB_OUTPUT
```

**Features:**
- **Fallback Logic**: Manual input overrides environment secrets
- **Validation**: Required parameters validation with clear error messages
- **Output Propagation**: Configuration values passed between workflow steps

### 4. Deployment Token Management

#### Multi-source Token Retrieval
```bash
# Try to get from Key Vault first
DEPLOYMENT_TOKEN=$(az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name "${{ steps.config.outputs.CLIENT_NAME }}-swa-deployment-token" \
  --query value -o tsv 2>/dev/null || echo "")

# If not in Key Vault, get directly from SWA
if [ -z "$DEPLOYMENT_TOKEN" ]; then
  echo "Getting deployment token directly from Static Web App..."
  DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
    --name "$SWA_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query "properties.apiKey" -o tsv)
fi
```

**Benefits:**
- **Resilient Token Retrieval**: Falls back to direct SWA API if Key Vault unavailable
- **Security**: Tokens are masked in logs using `::add-mask::`
- **Consistency**: Same token retrieval logic for both build and close jobs

## Technical Implementation Details

### Quarto Build Process
```bash
- name: Build Quarto Site
  run: |
    echo "Building Quarto site..."
    quarto render
    
    # Verify build output
    if [ ! -d "_site" ]; then
      echo "Error: _site directory not found after Quarto render"
      exit 1
    fi
    
    echo "Quarto build completed successfully"
    ls -la _site/
```

### Authentication Configuration
```bash
- name: Configure Authentication Settings
  run: |
    # Get app credentials from Key Vault
    VAULT_NAME="${{ steps.config.outputs.VAULT_NAME }}"
    CLIENT_NAME="${{ steps.config.outputs.CLIENT_NAME }}"
    
    AZURE_CLIENT_ID_VALUE=$(az keyvault secret show \
      --vault-name "$VAULT_NAME" \
      --name "${CLIENT_NAME}-swa-client-id" \
      --query value -o tsv)
    
    AZURE_CLIENT_SECRET_VALUE=$(az keyvault secret show \
      --vault-name "$VAULT_NAME" \
      --name "${CLIENT_NAME}-swa-client-secret" \
      --query value -o tsv)
    
    # Configure Static Web App settings
    az staticwebapp appsettings set \
      --name "${{ steps.config.outputs.SWA_NAME }}" \
      --resource-group "${{ steps.config.outputs.RESOURCE_GROUP_NAME }}" \
      --setting-names "AZURE_CLIENT_ID=$AZURE_CLIENT_ID_VALUE" "AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET_VALUE"
```

## Integration Points

### Existing Infrastructure Dependencies
- **Prerequisite**: `00_clientinfra` provisioning must be completed first
- **Key Vault Integration**: Relies on client-specific Key Vault for credential storage
- **Federated Credentials**: Uses existing `github-fedcred-setup.sh` for OIDC authentication
- **Secret Management**: Integrates with `github-secrets-sync.sh` for environment setup

### File Structure Impact
```
03_serverless_dash/
├── .github/
│   └── workflows/
│       └── deploy-quarto-app.yml        # New workflow file
├── scripts/
│   └── provision-03_serverless_dash.sh  # Enhanced with user creation
├── _quarto.yml                          # Existing Quarto config
├── staticwebapp.config.json             # Existing SWA auth config
└── _site/                               # Build output (gitignored)
```

## Usage Instructions

### Automated Deployment (Recommended)
1. **Setup Phase**: Run `github-secrets-sync.sh` and `github-fedcred-setup.sh`
2. **Trigger Deployment**: Push to master branch or use workflow dispatch
3. **Monitor Progress**: Check GitHub Actions for build and deployment status

### Manual Deployment
1. **Workflow Dispatch**: Use GitHub UI to trigger with specific client name
2. **Environment Selection**: Workflow automatically uses client-specific environment
3. **Status Verification**: Check deployment URL in workflow output

### Pull Request Workflow
1. **Staging Creation**: PR automatically creates staging deployment
2. **Review Process**: Test changes on staging URL
3. **Cleanup**: Staging environment cleaned up on PR merge/close

## Error Handling & Monitoring

### Build Validation
- **Quarto Render Check**: Verifies `_site` directory creation
- **Content Validation**: Lists generated files for verification
- **Dependency Check**: Validates R packages and Quarto installation

### Deployment Verification
- **Token Validation**: Ensures deployment token is available
- **Authentication Setup**: Confirms AAD credentials are configured
- **URL Output**: Provides final deployment URL for verification

### Troubleshooting Guide
- **Missing Secrets**: Verify `github-secrets-sync.sh` has been run
- **Authentication Failures**: Check federated credential setup
- **Build Failures**: Review Quarto dependencies and R package installation
- **Deployment Issues**: Validate Azure permissions and Static Web App configuration

## Future Enhancements

### Potential Improvements
1. **Custom Domain Setup**: Automated custom domain configuration
2. **Multi-environment Support**: Dev/staging/prod environment patterns
3. **Monitoring Integration**: Application Insights setup
4. **Performance Optimization**: Build caching for faster deployments
5. **Testing Integration**: Automated testing before deployment

### Monitoring & Maintenance
- **Quarto Version Updates**: Monitor for new Quarto releases
- **Dependency Updates**: Regular R package and Node.js updates
- **Security Updates**: Azure action and authentication library updates
- **Performance Monitoring**: Build time and deployment speed tracking

## Conclusion

This implementation provides a complete automated deployment pipeline for Quarto-based dashboard applications to Azure Static Web Apps, following established patterns from the 00_clientinfra framework while addressing the specific needs of R/Quarto applications.

The solution enables:
- **Zero-touch Deployments**: Fully automated from code push to live application
- **Environment Consistency**: Standardized deployment across client environments
- **Security Best Practices**: OIDC authentication and secure credential management
- **Developer Experience**: Clear feedback and troubleshooting information
- **Scalability**: Template for additional Quarto application deployments