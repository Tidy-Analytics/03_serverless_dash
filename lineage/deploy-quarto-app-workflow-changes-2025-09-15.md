# Deploy Quarto App Workflow Changes

**Date:** September 15, 2025  
**File Modified:** `/03_serverless_dash/.github/workflows/deploy-quarto-app.yml`  
**Author:** GitHub Copilot  

## Problem Statement

The original `deploy-quarto-app.yml` workflow was failing with an Azure authentication error:

```
Login failed with Error: Using auth-type: SERVICE_PRINCIPAL. Not all values are present. 
Ensure 'client-id' and 'tenant-id' are supplied.
```

Despite having the required secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) configured at the organization level, the workflow was failing during the Azure Login step.

## Root Cause Analysis

The primary issues identified were:

1. **Environment Configuration Mismatch**: The workflow used `environment: ${{ github.event.inputs.client_name || 'default' }}`, which defaulted to a `'default'` environment when triggered by push events (where `github.event.inputs.client_name` is null).

2. **Automatic Deployment on Push**: The workflow was configured to deploy automatically on every push to master, without requiring an explicit client name specification.

3. **Version Inconsistency**: The close pull request job was using `azure/login@v1` while the main job used `azure/login@v2`.

4. **Business Logic Violation**: The application architecture requires that deployments are always tied to a specific 4-character client identifier, but the workflow allowed deployments without this constraint.

## Solution Implemented

### 1. Removed Automatic Push Deployments

**Before:**
```yaml
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

**After:**
```yaml
on:
  workflow_dispatch:
    inputs:
      client_name:
        description: 'Client name for deployment (4-character identifier)'
        required: true
        type: string
```

**Rationale:** Prevents accidental deployments and ensures every deployment is intentional and client-specific.

### 2. Simplified Job Conditions

**Before:**
```yaml
build_and_deploy_job:
  if: github.event_name == 'push' || github.event_name == 'workflow_dispatch' || (github.event_name == 'pull_request' && github.event.action != 'closed')
```

**After:**
```yaml
build_and_deploy_job:
  if: github.event_name == 'workflow_dispatch'
```

**Rationale:** Since only `workflow_dispatch` is supported, the condition becomes simple and explicit.

### 3. Fixed Environment Configuration

**Before:**
```yaml
environment: ${{ github.event.inputs.client_name || 'default' }}
```

**After:**
```yaml
environment: ${{ github.event.inputs.client_name }}
```

**Rationale:** Eliminates the fallback to a non-existent `'default'` environment that was causing authentication failures.

### 4. Enhanced Configuration Validation

**Before:**
```yaml
CLIENT_NAME="${{ github.event.inputs.client_name || secrets.CLIENT_NAME }}"
if [ -z "$CLIENT_NAME" ]; then
  echo "Error: CLIENT_NAME is required"
  exit 1
fi
```

**After:**
```yaml
CLIENT_NAME="${{ github.event.inputs.client_name }}"
if [ -z "$CLIENT_NAME" ]; then
  echo "Error: CLIENT_NAME is required. This workflow can only be run via workflow_dispatch with a client_name input."
  exit 1
fi
```

**Rationale:** Provides clearer error messaging and removes dependency on `secrets.CLIENT_NAME` which may not exist.

### 5. Removed Pull Request Support

**Removed:** Entire `close_pull_request_job` and all pull request-related functionality.

**Rationale:** 
- Pull request deployments don't align with the client-specific deployment model
- Eliminates complexity and potential authentication issues
- Prevents preview deployments that could confuse the client-specific architecture

## Usage Instructions

### Via GitHub UI
1. Navigate to the Actions tab in the repository
2. Select "Deploy Quarto App to Azure Static Web Apps"
3. Click "Run workflow"
4. Enter the 4-character client name
5. Click "Run workflow"

### Via GitHub CLI
```bash
gh workflow run deploy-quarto-app.yml -f client_name=YOUR_CLIENT_NAME
```

## Benefits of Changes

1. **Elimination of Authentication Errors**: By removing the fallback to `'default'` environment, the workflow now uses the correct environment where secrets are configured.

2. **Enforced Business Logic**: Every deployment now requires an explicit client name, preventing accidental or incorrect deployments.

3. **Simplified Workflow**: Removal of pull request support reduces complexity and potential failure points.

4. **Clear Error Messages**: Enhanced validation provides better feedback when the workflow is used incorrectly.

5. **Consistency with Working Patterns**: The modified workflow now follows the same pattern as the working `client-management.yml` workflow.

## Comparison with Working Workflow

The changes align the `deploy-quarto-app.yml` with the successful patterns in `client-management.yml`:

- Both now use `azure/login@v2` consistently
- Both require explicit client names via `workflow_dispatch`
- Both use the client name directly as the environment without fallbacks
- Both enforce client-specific deployment patterns

## Testing Recommendations

1. Test deployment with a valid 4-character client name
2. Verify that the workflow fails gracefully when no client name is provided
3. Confirm that Azure authentication works with the specified environment
4. Validate that the provisioning script receives the correct client name parameter

## Future Considerations

- Consider adding validation for client name format (4-character constraint)
- Evaluate if any pull request preview functionality is needed in the future
- Monitor for any additional environment-specific secrets that may be needed