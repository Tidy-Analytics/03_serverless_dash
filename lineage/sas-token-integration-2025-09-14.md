# SAS Token Refresh Integration

This document describes the integration of automated SAS token refresh into the 03_serverless_dash deployment pipeline.

## Problem Addressed

**Issue**: SAS tokens created during initial client provisioning (00_clientinfra) expire after 7 days. Since there can be weeks or months between client setup and app deployment, the tokens are often expired when the 03_serverless_dash application is first deployed.

**Impact**: Deployment failures and inability to load customer data from blob storage at runtime.

## Solution Implemented

### Integration of update-sas-url.sh

The `update-sas-url.sh` script from 00_clientinfra has been copied and adapted for 03_serverless_dash:

**Source**: `/home/joel/00_clientinfra/scripts/update-sas-url.sh`
**Destination**: `/home/joel/03_serverless_dash/scripts/update-sas-url.sh`

#### Key Adaptations:
- **Removed Container App updates** - 03_serverless_dash uses Static Web Apps, not Container Apps
- **Updated KeyVault secret naming** - Uses 03_serverless_dash specific secret names
- **GitHub secrets pattern** - Uses `{CLIENT_NAME}_*` pattern for repository secrets
- **Default repository** - Targets `Tidy-Analytics/03_serverless_dash` repo

### GitHub Actions Integration

Added automated SAS token refresh as part of the deployment pipeline:

```yaml
- name: Refresh SAS Tokens
  run: |
    CLIENT_NAME="${{ env.CLIENT_HANDLE }}"
    echo "Refreshing SAS tokens for client: $CLIENT_NAME"

    # Run with 30-day expiry for app deployments
    ./scripts/update-sas-url.sh "$CLIENT_NAME" 30
```

**Placement**: Runs before Quarto build process to ensure fresh tokens are available for runtime configuration.

### Runtime Configuration Update

Modified runtime configuration step to use refreshed tokens:

```yaml
- name: Create Runtime Configuration
  run: |
    # Get the refreshed SAS token from KeyVault
    KEYVAULT_NAME="${CLIENT_NAME}-kv"
    STORAGE_SAS_TOKEN=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "storage-sas-token" --query "value" -o tsv)
```

## Workflow Changes

### Before Integration
1. Deploy app → Use potentially expired 7-day token → **FAILURE**
2. Manual intervention required to refresh tokens

### After Integration
1. **Refresh SAS tokens** (30-day expiry) → Update KeyVault & GitHub secrets
2. **Create runtime config** → Pull fresh token from KeyVault
3. **Deploy app** → Success with valid long-lived token

## Technical Details

### Token Lifecycle
- **Initial Setup** (00_clientinfra): 7-day tokens
- **App Deployment** (03_serverless_dash): 30-day tokens (refreshed automatically)
- **Manual Refresh**: `./scripts/update-sas-url.sh {CLIENT_NAME} [days]`

### Storage Resources Updated
- **Main Storage**: `{CLIENT_NAME,,}storage` - Customer data access
- **Web Storage**: `{CLIENT_NAME,,}web` - Web assets (inherited pattern)
- **KeyVault Secrets**: Read-only and full-access tokens stored separately

### GitHub Secrets Updated
- `{CLIENT_NAME}_STORAGE_SAS_TOKEN` - Read-only token for runtime data access
- `{CLIENT_NAME}_SAS_TOKEN_FULL` - Full-access token for administrative operations
- `{CLIENT_NAME}_EXPIRY_DATE` - Token expiration tracking

## Benefits

### Operational
- **Zero manual intervention** - Fully automated token refresh
- **Extended validity** - 30-day tokens vs 7-day default
- **Deployment reliability** - No failures due to expired tokens

### Development
- **Consistent pattern** - Same script can be used across app repos
- **Standard integration** - Template for future application deployments
- **Maintainability** - Single source of truth for SAS token management

## Future Considerations

### Standardization
This pattern should be adopted across other application repositories that depend on 00_clientinfra storage resources:
- Copy `update-sas-url.sh` to each app repo
- Integrate refresh step into deployment workflows
- Update documentation with token refresh patterns

### Monitoring
Consider adding:
- Token expiration alerts in Azure Monitor
- Automated renewal before expiration (e.g., cron job)
- Deployment logs showing token refresh status

## Files Modified

### New Files
- `scripts/update-sas-url.sh` - SAS token refresh script (adapted from 00_clientinfra)
- `lineage/sas-token-integration.md` - This documentation

### Modified Files
- `.github/workflows/azure-static-web-apps.yml` - Added refresh step and updated runtime config
- `README.md` - Updated deployment instructions and troubleshooting
- `lineage/resource-lineage.md` - References to token refresh integration

## Related Documentation
- [Resource Lineage](./resource-lineage.md) - Overall resource dependencies
- [README.md](../README.md) - Deployment instructions
- [00_clientinfra scripts](../../00_clientinfra/scripts/) - Source of SAS token management patterns