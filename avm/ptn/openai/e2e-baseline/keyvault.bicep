/*
  Deploy a Key Vault with a private endpoint and DNS zone
*/

@description('This is the base name for each Azure resource name (6-12 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

@description('The certificate data for app gateway TLS termination. The value is base64 encoded')
@secure()
param appGatewayListenerCertificate string
param sqlConnectionString string

// existing resource name params 
param vnetId string
param privateEndpointsSubnetResourceId string
param logAnalyticsWorkspaceId string
param logAnalyticsWorkspaceName string
param keyExpiration int = dateTimeToEpoch(dateTimeAdd(utcNow(), 'P60D'))


//variables
var keyVaultName = 'kv-${baseName}'
var keyVaultPrivateEndpointName = 'pep-${keyVaultName}'
var keyVaultDnsGroupName = '${keyVaultPrivateEndpointName}/default'
var keyVaultDnsZoneName = 'privatelink.vaultcore.azure.net' //Cannot use 'privatelink${environment().suffixes.keyvaultDns}', per https://github.com/Azure/bicep/issues/9708

resource onlineEndpoint 'Microsoft.MachineLearningServices/workspaces/onlineEndpoints@2023-10-01' existing = {
  name: 'ept-${baseName}'
}

// ---- Key Vault resources ----

// create key vault with PE but no rbac to it - can guide 

module keyVault 'br/public:avm/res/key-vault/vault:0.7.0' = {
  name: 'keyVaultDeployment'
  params: {
    name: keyVaultName
    location: location
    enableVaultForDeployment: true  // VMs can retrieve certificates
    enableVaultForDiskEncryption: false
    enablePurgeProtection: false  // Ideally set this true. This is usually enforced through 'Key vaults should have deletion protection enabled' policy
    enableRbacAuthorization: true // Using RBAC
    enableVaultForTemplateDeployment: true // ARM can retrieve values
    enableSoftDelete: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    sku: 'standard'
    publicNetworkAccess: 'Disabled'
    // tenantId: subscription().tenantId
    createMode: 'default' // Creating or updating the key vault (not recovering)
    secrets: [
      {
        attributes: {
          enabled: true
          exp: keyExpiration // Autoexpire this key
        }
        contentType: 'text/plain'
        name: 'chatApiKey'
        value: 'secretValue'
      }
    ]
}
}

module keyVaultPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'keyVaultPrivateEndpointDeployment'
  params: {
    name: keyVaultPrivateEndpointName
    location: location
    subnetResourceId: privateEndpointsSubnetResourceId
    privateDnsZoneGroup: {
      name: keyVaultDnsGroupName
      privateDnsZoneGroupConfigs: [
        {
          name: keyVaultDnsZoneName
          privateDnsZoneResourceId: keyVaultDnsZone.outputs.resourceId
        }
      ]
    }
    privateLinkServiceConnections: [
      {
        name: keyVaultPrivateEndpointName
        properties: {
          groupIds: ['vault']
          privateLinkServiceId: keyVault.outputs.resourceId
        }
      }
    ]
  }
}

module keyVaultDnsZone 'br/public:avm/res/network/private-dns-zone:0.4.0' = {
  name: 'keyVaultPrivateDnsZoneDeployment'
  params: {
    name: keyVaultDnsZoneName
    location: 'global'
    virtualNetworkLinks: [
      {
        name: '${keyVaultDnsZoneName}-link'
        registrationEnabled: false
        virtualNetworkResourceId: vnetId
      }
    ]
  }
}


@description('The name of the key vault account.')
output keyVaultName string= keyVault.name

@description('Uri to the secret holding the cert.')
output gatewayCertSecretUri string = keyVault.outputs.uri
