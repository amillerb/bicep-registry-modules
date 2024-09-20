/*
  Deploy storage account with private endpoint and private DNS zone
*/

@description('This is the base name for each Azure resource name (6-12 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

// existing resource params 
param vnetResourceId string
param privateEndpointsSubnetId string
param logAnalyticsWorkspaceId string

// variables
var storageName = 'st${baseName}'
var storageSkuName = 'Standard_LRS'
var storageDnsGroupName = '${storagePrivateEndpointName}/default'
var storagePrivateEndpointName = 'pep-${storageName}'
var blobStorageDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'

var appDeployStorageName = 'st${baseName}'
var appDeployStoragePrivateEndpointName = 'pep-${appDeployStorageName}'

var mlStorageName = 'stml${baseName}'
var mlBlobStoragePrivateEndpointName = 'pep-blob-${mlStorageName}'
var mlFileStoragePrivateEndpointName = 'pep-file-${mlStorageName}'


// ---- Existing resources ----

// ---- Storage resources ----
module appDeployStorage 'br/public:avm/res/storage/storage-account:0.9.1' = {
  name: 'appDeployStorageDeployment'
  params: {
    name: appDeployStorageName
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    allowCrossTenantReplication: false
    blobServices: {
      blob: {
        enabled: true
        keyType: 'Account'
      }
      containers: [
        {
          name: 'deploy'
          publicAccess: 'None'
        }
      ]
    }
    fileServices: {
      shares: [
        {
          enabled: true
          keyType: 'Account'
        }
      ]
    }
    requireInfrastructureEncryption: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
    kind: 'StorageV2'
    location: location
    skuName: storageSkuName
    privateEndpoints: [
      {
        name: storagePrivateEndpointName
        subnetResourceId: privateEndpointsSubnetId
        service: 'blob'
      }
      {
        name: storagePrivateEndpointName
        subnetResourceId: privateEndpointsSubnetId
        service: 'file'
      }
    ]
    diagnosticSettings:   [
      {
        workspaceResourceId: logAnalyticsWorkspaceId
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
        name: 'appDeployStorageDiagnosticSettings'
        logAnalyticsDestinationType: 'AzureDiagnostics'
      }
    ]
  }
}

module appDeployStoragePrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'appDeployStoragePrivateEndpointDeployment'
  params: {
    name: appDeployStoragePrivateEndpointName
    location: location
    subnetResourceId: privateEndpointsSubnetId
    privateDnsZoneGroup: {
      name: storageDnsGroupName
      privateDnsZoneGroupConfigs: [
        {
          name: blobStorageDnsZoneName
          privateDnsZoneResourceId: storageDnsZone.outputs.resourceId
        }
      ]
    }
    privateLinkServiceConnections: [
      {
        name: appDeployStoragePrivateEndpointName
        properties: {
          groupIds: ['blob']
          privateLinkServiceId: appDeployStorage.outputs.resourceId
        }
      }
    ]
  }
}

module storageDnsZone 'br/public:avm/res/network/private-dns-zone:0.4.0' = {
  name: 'storagePrivateDnsZoneDeployment'
  params: {
    name: blobStorageDnsZoneName
    location: 'global'
    virtualNetworkLinks: [
      {
        name: '${blobStorageDnsZoneName}-link'
        registrationEnabled: false
        virtualNetworkResourceId: vnetResourceId
      }
    ]
  }
  
}

module mlStorage 'br/public:avm/res/storage/storage-account:0.9.1' = {
  name: 'mlStorageDeployment'
  params: {
    name: mlStorageName
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    allowCrossTenantReplication: false
    blobServices: {
      blob: {
        enabled: true
        keyType: 'Account'
      }
      containers: [
        {
          name: 'deploy'
          publicAccess: 'None'
        }
      ]
      diagnosticSettings:   [
        {
          workspaceResourceId: logAnalyticsWorkspaceId
          metricCategories: [
            {
              category: 'AllMetrics'
            }
          ]
          name: 'mlBlobdiagnosticSettings'
          logAnalyticsDestinationType: 'AzureDiagnostics'
        }
      ]
    }
    fileServices: {
      shares: [
        {
          enabled: true
          keyType: 'Account'
        }
      ]
      diagnosticSettings:   [
        {
          workspaceResourceId: logAnalyticsWorkspaceId
          metricCategories: [
            {
              category: 'AllMetrics'
            }
          ]
          name: 'mlFilediagnosticSettings'
          logAnalyticsDestinationType: 'AzureDiagnostics'
        }
      ]
    }
    requireInfrastructureEncryption: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
    kind: 'StorageV2'
    location: location
    skuName: storageSkuName
    privateEndpoints: [
      {
        name: storagePrivateEndpointName
        subnetResourceId: privateEndpointsSubnetId
        service: 'blob'
      }
      {
        name: storagePrivateEndpointName
        subnetResourceId: privateEndpointsSubnetId
        service: 'file'
      }
    ]
    
  }
}

module mlBlobStoragePrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'mlBlobStoragePrivateEndpointDeployment'
  params: {
    name: mlBlobStoragePrivateEndpointName
    location: location
    subnetResourceId: privateEndpointsSubnetId
    privateLinkServiceConnections: [
      {
        name: mlBlobStoragePrivateEndpointName
        properties: {
          groupIds: ['blob']
          privateLinkServiceId: mlStorage.outputs.resourceId
        }
      }
    ]
  }
}

module mlFileStoragePrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'mlFileStoragePrivateEndpointDeployment'
  params: {
    name: mlFileStoragePrivateEndpointName
    location: location
    subnetResourceId: privateEndpointsSubnetId
    privateLinkServiceConnections: [
      {
        name: mlFileStoragePrivateEndpointName
        properties: {
          groupIds: ['file']
          privateLinkServiceId: mlStorage.outputs.resourceId
        }
      }
    ]
  }
}
