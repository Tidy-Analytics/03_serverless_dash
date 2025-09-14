# 03_serverless_dash - Customer Analytics Dashboard

A Quarto + Observable.js application that displays customer segment heatmap analysis, deployed as an Azure Static Web App with client-specific data from Azure Blob Storage.

## Overview

This application creates interactive customer cohort heatmaps using Observable.js visualizations within a Quarto website. Each client deployment:

- Runs under their own Azure resource group (`{CLIENT_NAME}-rg`)
- Pulls customer data from their dedicated blob storage container (`{CLIENT_NAME}-in`)
- Uses Microsoft authentication for secure access
- Deploys via GitHub Actions to Azure Static Web Apps

## Prerequisites

- Azure CLI installed and authenticated
- GitHub CLI (`gh`) installed
- Access to the master provisioner Azure tenant
- Client configuration from `00_clientinfra` setup

## Setup Process

### 1. Create Client Configuration

Copy the sample configuration and update for your client:

```bash
cp configs/sample.env configs/{CLIENT_NAME}.env
```

Update the following values in `configs/{CLIENT_NAME}.env`:
- `CLIENT_NAME`: 4-character client code (e.g., "drby")
- `APP_OWNER`: Client admin email address
- `APP_OWNER_NAME`: Client admin full name
- `ORG_NAME`: Client organization name
- `TEMP_PW`: Temporary password for client admin
- `CUSTOM_DOMAIN`: Client subdomain (e.g., "drby.tidyanalytics.com")

Keep these values from the master provisioner:
- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- `ADMIN_EMAIL`, `ADMIN_IP`, `ADMIN_OBJ`
- `GH_TOKEN`

### 2. Run Pre-Provisioning

This step creates GitHub secrets and federated credentials:

```bash
./scripts/pre-provision-03_serverless_dash.sh {CLIENT_NAME}
```

### 3. Run Main Provisioning

This step creates Azure resources and configures the Static Web App:

```bash
./scripts/provision-03_serverless_dash.sh {CLIENT_NAME}
```

### 4. Deploy the Application

Go to the GitHub repository and run the workflow:

1. Navigate to Actions → "Azure Static Web Apps CI/CD"
2. Click "Run workflow"
3. Select action: "deploy-app"
4. Enter client handle: `{CLIENT_NAME}`
5. Run the workflow

**Note**: The deployment workflow automatically refreshes SAS tokens before building the app, so expired tokens are not an issue even if weeks or months have passed since the initial client setup.

### 5. Upload Customer Data

Upload the client's customer data to their blob storage container:

- **Storage Account**: `{CLIENT_NAME}storage`
- **Container**: `{CLIENT_NAME}-in`
- **File Name**: `customer_data.json`

The data should be in JSON format with the following structure:
```json
[
  {
    "customer_id": "string",
    "segment_code": "string",
    "customer_tenure_week": number,
    "elapsed_week": number,
    "amount": number
  }
]
```

## Architecture

### Data Flow
1. **Development**: Uses local `customer_data.json` file
2. **Production**: Fetches data from client's blob storage at runtime
3. **Fallback**: If blob storage fails, falls back to local dummy data

### Runtime Configuration
The application uses `runtime-config.js` to configure blob storage access:
- Injected during GitHub Actions build process
- Contains SAS token for secure blob access
- Loaded by Observable.js data fetching code

### Authentication
- Uses Microsoft Azure AD authentication
- Configured via `staticwebapp.config.json`
- Client-specific app registration and permissions

## File Structure

```
03_serverless_dash/
├── configs/                    # Client configuration files
│   ├── sample.env             # Template configuration
│   └── {CLIENT_NAME}.env      # Client-specific config
├── scripts/                   # Provisioning scripts
│   ├── pre-provision-03_serverless_dash.sh
│   ├── provision-03_serverless_dash.sh
│   ├── update-sas-url.sh      # SAS token refresh (from 00_clientinfra)
│   └── data-fetcher.js
├── .github/workflows/         # GitHub Actions
│   └── azure-static-web-apps.yml
├── _quarto.yml               # Quarto configuration
├── index.qmd                 # Landing page
├── heatmap.qmd              # Main dashboard
├── customer_data.json       # Dummy data for development
├── staticwebapp.config.json # Azure SWA configuration
└── README.md                # This file
```

## Key Features

### Interactive Heatmap
- **Segment Selection**: Dropdown to filter by customer segment
- **Cohort Analysis**: Shows customer behavior over tenure weeks
- **Visual Encoding**: Color-coded average amounts with value labels
- **Responsive Design**: Optimized for various screen sizes

### Security
- **Azure AD Integration**: Microsoft authentication required
- **SAS Token Access**: Secure blob storage access with time-limited tokens
- **Client Isolation**: Each client has separate resource groups and storage

### Deployment
- **Automated CI/CD**: GitHub Actions workflow for builds and deployment
- **Environment-Specific**: Different configurations for dev/staging/production
- **Zero-Downtime**: Azure Static Web Apps provides seamless updates

## Configuration Details

### Environment Variables (GitHub Secrets)
- `{CLIENT_NAME}_AZURE_CLIENT_ID`: Azure service principal client ID
- `{CLIENT_NAME}_STORAGE_ACCOUNT_NAME`: Client's storage account name
- `{CLIENT_NAME}_STORAGE_SAS_TOKEN`: SAS token for blob access
- `{CLIENT_NAME}_BLOB_CONTAINER_NAME`: Container name for customer data

### Azure Resources Created
- **Resource Group**: `{CLIENT_NAME}-rg`
- **Static Web App**: `{CLIENT_NAME}-dashboard`
- **Managed Identity**: `{CLIENT_NAME}-swa-identity`
- **Storage Account**: `{CLIENT_NAME}storage` (from 00_clientinfra)
- **Key Vault**: `{CLIENT_NAME}-kv` (from 00_clientinfra)

## Troubleshooting

### Common Issues

1. **Data not loading**: SAS tokens are automatically refreshed on deployment, but verify blob container has data
2. **Build failures**: Verify GitHub secrets are properly configured
3. **Authentication errors**: Ensure app registration is properly configured
4. **Permission denied**: Check Azure RBAC assignments
5. **Expired SAS tokens**: Run `./scripts/update-sas-url.sh {CLIENT_NAME}` manually if needed

### Logs and Monitoring

- **GitHub Actions**: Build and deployment logs
- **Azure Static Web Apps**: Runtime logs and metrics
- **Browser Console**: Client-side data loading errors

## Development

To run locally for development:

```bash
quarto preview
```

The app will use the local `customer_data.json` file when no blob storage configuration is available.

## Related Projects

- **00_clientinfra**: Client provisioning and base infrastructure
- **02_mapscatter**: Brand application for general public access

## Support

For issues or questions, refer to the main project documentation or contact the development team.