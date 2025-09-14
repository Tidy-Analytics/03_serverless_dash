// Data fetcher for Azure Blob Storage
// This script fetches client data from Azure Blob Storage during build time

const CLIENT_NAME = process.env.CLIENT_NAME || 'demo';
const STORAGE_ACCOUNT_NAME = process.env.STORAGE_ACCOUNT_NAME || `${CLIENT_NAME.toLowerCase()}storage`;
const SAS_TOKEN = process.env.STORAGE_SAS_TOKEN || '';
const CONTAINER_NAME = process.env.BLOB_CONTAINER_NAME || `${CLIENT_NAME}-in`;
const DATA_FILE_NAME = process.env.DATA_FILE_NAME || 'customer_data.json';

async function fetchCustomerData() {
    // If no SAS token, fallback to local dummy data for development
    if (!SAS_TOKEN) {
        console.log('No SAS token provided, using local dummy data for development');
        return null; // Will use the existing customer_data.json
    }

    try {
        // Construct the blob URL with SAS token
        const blobUrl = `https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${CONTAINER_NAME}/${DATA_FILE_NAME}?${SAS_TOKEN}`;

        console.log(`Fetching customer data from: ${STORAGE_ACCOUNT_NAME}/${CONTAINER_NAME}/${DATA_FILE_NAME}`);

        const response = await fetch(blobUrl);

        if (!response.ok) {
            throw new Error(`Failed to fetch data: ${response.status} ${response.statusText}`);
        }

        const data = await response.json();
        console.log(`Successfully fetched ${data.length} customer records`);

        return data;
    } catch (error) {
        console.error('Error fetching customer data from blob storage:', error);
        console.log('Falling back to local dummy data');
        return null; // Will use the existing customer_data.json
    }
}

// Export for use in build process
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { fetchCustomerData };
}

// For use in browser/Observable
if (typeof globalThis !== 'undefined') {
    globalThis.fetchCustomerData = fetchCustomerData;
}