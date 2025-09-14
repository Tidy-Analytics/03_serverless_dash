## Application Deployment Overview

This '03_serverless_dash' application is the first in a series of applications that are assigned to *specific clients*. This contrasts with the primary applications in 00_clientinfra, which creates initial client resources, and creates a dedicated app for data uploading and downloading, and 02_mapscatter, which is is a brand application that *may* be exposed to specific clients (or made available to the general public). The current application is a simple serverless Dash application that is deployed to a specific client.

# Topic: Boostrapping Keys and Secrets

Please note that the application requires a hybrid of the keys and secrets that are associated with the '00_clientinfra' client provisioning process. 

Like that process, it needs to be boostrapped with a tenant-wide 'client configurator' managed identity, which is specified, as with the main provisioner, in a configuration file stored in a non-git-tracked 'configs' folder. 

One significant difference is that the resource group used here should not be the resource group of the master provisioner identity, but rather the resource group of the *client* to which the application is being deployed.

# CONFIGURATION KEYS AND SECRETS DETAIL

The relevant keys and secrets that need to be recycled here from the provisioning process 00_clientinfra .env file INPUTS:

CLIENT_NAME=<<4 character code for client, e.g. "drby">>
ADMIN_EMAIL=<<tenant master admin>> email of tenant owner, remain hardcoded
ADMIN_IP=<<master tenant admin IP whitelist>> IP permission for admin, remain hardcoded
ADMIN_OBJ=<<some azure object id>> # object id of provisioner identity, remain hardcoded
APP_OWNER=<<some users email>> # email of CLIENT admin user responsible for, and the master admin of, the app being provisioned, an entra external user 
APP_OWNER_NAME=<<app admin users name in Entra external tenant>>
ORG_NAME=<<company name>>
TEMP_PW=<<temporary password for app owner>> # this should be assigned randomly as part of the provisioning process, and sent to the APP_OWNER email using standard Azure/MSFT auth processes
CUSTOM_DOMAIN=${CLIENT_NAME}.tidyanalytics.com # this will be a subdomain consisting of the 4-digit code and the main tidyanalytics.com domain
LOCATION=CentralUS
GH_TOKEN=<<some token value>> ## remain hardcoded
AZURE_CLIENT_ID=<<provisioner client ID>> # remain hardcoded
AZURE_TENANT_ID=<<provisioner tenant ID>> # remain hardcoded
AZURE_SUBSCRIPTION_ID=<<provisioner subscription ID>> # remain hardcoded

### REPO

Note that this info is new; repo references for the app being deployed, rather than the root 00_clientinfra repo. 

REPO_NAME=Tidy-Analytics/03_serverless_dash
REPO_URL=https://github.com/Tidy-Analytics/03_serverless_dash

## Azure Keys

The process should use keys and secrets that are maintained in the master Azure Key Vault set up for the client in the 00_clientinfra process, and generated and stored as part of "00_clientinfra/scripts/client-setup.sh". Thus, the most productive way to run the provisioning process will likely be to retrieve these keys first as part of the app provisioning script (see below); The process should also copy over keys from the 00_clientinfra .env file INPUTS, as needed, pursuant to the above specification, and generate the .env file in a 'configs' directory, like the main provisioner.

# APP SPECIFICS

## "APP_OWNER" 

This user should be created if necessary, ie, if the client identity does not already exist in the tenant.
 
## created directories and files

The app provisioning process should create a 'configs' directory, if needed, and populate keys over from the main provisioner .env file INPUTS, as needed, and generate a .env file in the 'configs' directory, like the main provisioner.

The app provisioning process itself should be stored in a 'scripts' directory, and named appropriately based on the app repo name, e.g. 'provision-03_serverless_dash.sh', with a 'pre-provisioning' script, to be created as well, consisting of the key creation and federated identity credential creation steps, which result in all needed keys (except those that will be created during app provisioning), being posted to Github secrets. 

As a last step in provisioning process, any keys created or updated that are not stored in the Azure Key Vault should be added. See the "00_clientinfra/scripts/client-setup.sh" for a template of how to do this.

# APP SPECIFICS FUNCTIONALITY MODULES

This is an R based Quarto app that uses Observable plot to show a clients customer data heatmap. 

This uses dummy data for now in project root stored as 'customer_data.json', but the final implementation to be set up and deployed here should provide for this data to be pulled from the blob container storage resource set up in the initial client provisioning process 00_clientinfra for use by the Observable.js app components at runtime. All resource IDs for these locations will be stored in the Azure Key Vault created as part of that process, and should be retrieved as part of the app provisioning process. The deployment should ensure that client data is never checked into the repo. This app should pull all client data from the '${CLIENT_NAME}-in' conteiner created in th main client provisioning process.

## Functionality Needed in Setup

-- set up static assets as Azure Static Web app, running under client resource group '${CLINT_NAME}-rg'
-- create app registration in Entra ID 
-- create new users in external tenant, if needed, per above
-- assign users to client user group created in 00_clientinfra for this client
-- create app role for app, and assign permissions to the client app user group
-- create MS auth that uses tenant endpoint, as with 00_clientinfra

This app should be set up and configured to use Github Actions, again, use '00_clientinfra' repo for reference.

## MS AUTH: 

Make sure that the Microsoft provider is set to bypass interactive setup using '--yes' flag, as this will be a process set to run under automation on Github actions.

## end results

Should result in a fully functioning static web app, showing the heatmap app, running under the client resource group, and using the client identity and auth setup in the main client provisioning process 00_clientinfra.

## RULES

These rules should always be followed for any work done in this repo:

1) All new work in this repo should be summarized to markdown files stored in the 'lineage' directory. Each of these files should be timestamped for the date that the changes were made, as a suffix in YYYY-MM-DD format, eg' 'sas-token-integration-2025-09-14.md'. 

## NOTE: You should wait to do these summaries until prompted, you will be given the instruction to 'document your work' in the chat.




