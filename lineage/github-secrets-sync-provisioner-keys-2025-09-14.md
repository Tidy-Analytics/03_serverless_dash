# GitHub Secrets Sync Script Update - PROVISIONER Keys Integration

**Date:** September 14, 2025
**Scope:** Enhanced `scripts/github-secrets-sync.sh` to include PROVISIONER_* configuration keys

## Problem Statement

The `github-secrets-sync.sh` script was missing the new `PROVISIONER_*` keys that are defined in the configuration files. These keys are critical for the federated credential setup process but were not being extracted and synchronized to GitHub secrets, making them invisible to the GitHub Actions workflows.

## Changes Made

### 1. Updated REQUIRED_KEYS Array
Added the following keys to the `REQUIRED_KEYS` array in `scripts/github-secrets-sync.sh:163-181`:
- `PROVISIONER_RESOURCE_GROUP`
- `PROVISIONER_IDENTITY_NAME`

### 2. Enhanced Bootstrap Keys Loading
Modified the bootstrap keys loading section (`scripts/github-secrets-sync.sh:57-66`) to include:
```bash
PROVISIONER_RESOURCE_GROUP=$(get_local_config "PROVISIONER_RESOURCE_GROUP")
PROVISIONER_IDENTITY_NAME=$(get_local_config "PROVISIONER_IDENTITY_NAME")
```

### 3. Added Validation and Logging
Enhanced the validation section (`scripts/github-secrets-sync.sh:87-97`) to provide feedback on whether these keys were found:
- Logs success when keys are found with their values
- Provides informative messages when keys are missing and defaults will be used

### 4. Implemented Default Value Assignment
Added default value logic (`scripts/github-secrets-sync.sh:229-237`) to ensure proper fallback values:
- `PROVISIONER_RESOURCE_GROUP`: defaults to `"external-tenant-testing"`
- `PROVISIONER_IDENTITY_NAME`: defaults to `"client-provisioner"`

## Configuration Sources

The keys are sourced from the configuration hierarchy defined in the script:
1. **Primary Source**: Azure Key Vault `${CLIENT_NAME}-kv` secret named `client-config`
2. **Secondary Source**: Local `configs/${CLIENT_NAME}.env` file
3. **Fallback**: Hard-coded default values matching the sample configuration

## Impact

These changes ensure that:
- The provisioner identity configuration is properly synchronized to GitHub secrets
- The federated credential setup script (`github-fedcred-setup.sh`) has access to the required provisioner details
- GitHub Actions workflows can authenticate with the correct provisioner identity
- The bootstrap process has all necessary credentials for proper Azure resource provisioning

## Files Modified

- `scripts/github-secrets-sync.sh` - Enhanced to include PROVISIONER_* keys in synchronization process

## Testing Notes

The script maintains backward compatibility through:
- Graceful handling of missing keys with default values
- Clear logging of configuration sources used
- Preservation of existing key loading patterns