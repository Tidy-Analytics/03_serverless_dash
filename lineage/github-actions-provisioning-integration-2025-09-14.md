# GitHub Actions Provisioning Integration

This document describes the integration of automated provisioning into the 03_serverless_dash GitHub Actions workflow, following the 00_clientinfra pattern.

## Problem Addressed

**Issue**: The 03_serverless_dash implementation had two critical gaps compared to the reference 00_clientinfra pattern:

1. **Missing GitHub Environment Model**: Current implementation created client-prefixed GitHub secrets (e.g., `ZMMR_AZURE_CLIENT_ID`) instead of using GitHub environments with standard secret names
2. **Missing Automated Provisioning**: No way to run the Azure resource provisioning directly from GitHub Actions workflow

**Impact**: Manual provisioning steps required and inconsistent secret management compared to established 00_clientinfra patterns.

## Solution Implemented

### 1. GitHub Environment-Based Secret Management

Updated the secret management system to follow 00_clientinfra patterns:

**Before**: Client-prefixed secrets in repository scope
```bash
gh secret set "${CLIENT_NAME}_AZURE_CLIENT_ID" --body "$value" --repo "$REPO_NAME"
```

**After**: Standard secret names in client-specific environments
```bash
echo "$value" | gh secret set "AZURE_CLIENT_ID" --env "$CLIENT_NAME" -R "$REPO_NAME"
```

#### Key Changes:
- **`scripts/github-secrets-sync.sh`** (Created) - Hierarchical key retrieval system
  - Primary source: Azure Key Vault `${CLIENT_NAME}-kv` secret `client-config`
  - Secondary source: Local `configs/${CLIENT_NAME}.env` file
  - Creates GitHub environment with standard secret names
  - Creates consolidated JSON `CONFIG` secret

- **`scripts/github-fedcred-setup.sh`** (Created) - Environment-scoped federated credentials
  - Subject format: `repo:Tidy-Analytics/03_serverless_dash:environment:${CLIENT_NAME}`
  - Uses client's managed identity and resource group

### 2. Automated Provisioning via GitHub Actions

Created integrated provisioning following 00_clientinfra model:

#### New Provisioning Script
**`scripts/provision-03_serverless_dash.sh`** (Created)
- Loads configuration from CONFIG secret (JSON format)
- Verifies client resource group exists (from 00_clientinfra)
- Creates Azure Static Web App
- Creates Azure AD App Registration for authentication
- Stores secrets in client's Key Vault
- Configures Static Web App settings
- Sets up user permissions

#### GitHub Actions Integration
**`.github/workflows/azure-static-web-apps.yml`** (Updated)

Added new `provision_app` job:
```yaml
provision_app:
  if: github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'provision-app'
  runs-on: ubuntu-latest
  environment: ${{ github.event.inputs.client_name }}
  steps:
    - name: Run Application Provisioning
      run: |
        chmod +x ./scripts/provision-03_serverless_dash.sh
        ./scripts/provision-03_serverless_dash.sh "$CLIENT_NAME"
```

Updated workflow inputs to include `provision-app` action.

Modified `build_and_deploy_job` to work with pre-provisioned apps:
- Gets deployment tokens from existing Static Web App
- Retrieves app registration details from Key Vault
- No longer depends on inline provisioning

### 3. Configuration Standardization

#### Terminology Unification
- Standardized all references to use `CLIENT_NAME`/`client_name`
- Eliminated `client_handle`/`CLIENT_HANDLE` variants
- Updated across all scripts and workflow files

#### Hierarchical Key Retrieval
```bash
# Key Retrieval Hierarchy:
# 1. Primary: Azure Key Vault ${CLIENT_NAME}-kv secret 'client-config'
# 2. Secondary: Local configs/${CLIENT_NAME}.env file (for missing keys only)
```

### 4. Security Improvements

#### `.gitignore` Creation
**`.gitignore`** (Created)
- Excludes `_site/` (Quarto output directory)
- Excludes `/.quarto/` (Quarto cache)
- Excludes entire `configs/` directory (sensitive client configurations)
- Standard exclusions for OS files, IDE files, logs

#### Secret Management Flow
```
Local configs/ → Azure Key Vault → GitHub Environment Secrets → Deployment
```
No sensitive data ever enters git history.

## Workflow Implementation

### Setup Phase (One-time per client)
```bash
# 1. Sync configuration to GitHub environment
./scripts/github-secrets-sync.sh <client_name>

# 2. Set up federated credentials
./scripts/github-fedcred-setup.sh <client_name>
```

### Provisioning Phase (Via GitHub Actions)
1. **Manual Trigger**: GitHub Actions → `provision-app` action
2. **Automated Execution**: Runs `provision-03_serverless_dash.sh` in cloud
3. **Resource Creation**: Static Web App, App Registration, authentication setup

### Deployment Phase (Via GitHub Actions)
1. **Manual Trigger**: GitHub Actions → `deploy-app` action
2. **Automated Process**: SAS token refresh → Quarto build → Static Web App deploy

## Technical Architecture

### Authentication Flow
```yaml
environment: ${{ github.event.inputs.client_name }}
# Uses environment-scoped secrets and federated credentials
```

### Configuration Loading
```bash
# In GitHub Actions:
echo "${{ secrets.CONFIG }}" > config.json
while IFS="=" read -r key value; do
  echo "$key=$value" >> $GITHUB_ENV
done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' config.json)
```

### Resource Naming Conventions
- Static Web App: `${CLIENT_NAME}-serverless-dash`
- App Registration: `${CLIENT_NAME}-serverless-dash-auth`
- Key Vault secrets: `${CLIENT_NAME}-swa-client-id`, `${CLIENT_NAME}-swa-client-secret`

## Benefits

### Operational
- **Fully Automated**: No manual Azure portal steps required
- **Consistent Pattern**: Follows established 00_clientinfra model
- **Environment Isolation**: Each client has dedicated GitHub environment
- **Secure by Default**: No credentials in git history

### Development
- **Standardized Workflow**: Same pattern across all Tidy Analytics apps
- **Error Reduction**: Automated provisioning eliminates manual mistakes
- **Scalable**: Easy to provision new clients
- **Maintainable**: Single source of truth for provisioning logic

## Future Considerations

### Pattern Adoption
This implementation serves as a template for other application repositories:
- Copy provisioning pattern to new app repos
- Adapt resource types (Static Web Apps vs Container Apps vs Function Apps)
- Maintain consistent GitHub environment model

### Monitoring & Alerting
Consider adding:
- Provisioning status notifications
- Resource health monitoring
- Cost tracking per client

## Files Modified

### New Files
- `scripts/provision-03_serverless_dash.sh` - Azure resource provisioning script
- `scripts/github-secrets-sync.sh` - GitHub environment secrets management
- `scripts/github-fedcred-setup.sh` - Federated credential setup
- `.gitignore` - Security exclusions for sensitive files
- `lineage/github-actions-provisioning-integration-2025-09-14.md` - This documentation

### Modified Files
- `.github/workflows/azure-static-web-apps.yml` - Added provision_app job and updated deploy logic
- `scripts/data-fetcher.js` - Standardized CLIENT_NAME terminology

### Removed Files
- `scripts/pre-provision-03_serverless_dash.sh` - Replaced by integrated provisioning

## Related Documentation
- [SAS Token Refresh Integration](./sas-token-integration-2025-09-14.md) - Automated token management
- [Resource Lineage](./resource-lineage.md) - Overall resource dependencies
- [README.md](../README.md) - Updated deployment instructions
- [00_clientinfra workflows](../../00_clientinfra/.github/workflows/) - Reference implementation patterns