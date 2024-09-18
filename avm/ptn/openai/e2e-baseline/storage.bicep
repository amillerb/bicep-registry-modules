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

// variables
var storageName = 'st${baseName}'
var storageSkuName = 'Standard_LRS'
var storageDnsGroupName = '${storagePrivateEndpointName}/default'
var storagePrivateEndpointName = 'pep-${storageName}'
var blobStorageDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'

// ---- Existing resources ----

// ---- Storage resources ----
module storage 'br/public:avm/res/storage/storage-account:0.9.1' = {
  name: 'storageAccountDeployment'
  params: {
    name: storageName
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    blobServices: {
      blob: {
        enabled: true
        keyType: 'Account'
      }
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
    ]
    
  }
}

module storagePrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'storagePrivateEndpointDeployment'
  params: {
    name: storagePrivateEndpointName
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
        name: storagePrivateEndpointName
        properties: {
          groupIds: ['blob']
          privateLinkServiceId: resourceId('Microsoft.Storage/storageAccounts', storageName)
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

@description('The name of the storage account.')
output storageName string = storage.name
