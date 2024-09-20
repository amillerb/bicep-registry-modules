targetScope = 'resourceGroup'

/*
  Deploy container registry with private endpoint
*/

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

@description('The zone redundancy of the ACR.')
param zoneRedundancy string = 'Enabled'

// existing resource name params 
param vnetName string

@description('The name of the resource group containing the spoke virtual network.')
@minLength(1)
param virtualNetworkResourceGroupName string


//variables
var acrName = 'cr${baseName}'
var acrPrivateEndpointName = 'pep-${acrName}'

param privateEndpointSubnetId string
param logAnalyticsWorkspaceId string

module acrResource 'br/public:avm/res/container-registry/registry:0.5.1' = {
  name: 'registryDeployment'
  params: {
    name: acrName
    acrSku: 'Premium'
    location: location
    acrAdminUserEnabled:false
    networkRuleSetDefaultAction: 'Deny'
    publicNetworkAccess: 'Disabled'
    zoneRedundancy: zoneRedundancy
    exportPolicyStatus: 'disabled'
    azureADAuthenticationAsArmPolicyStatus: 'disabled'
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspaceId
      }
    ]
    privateEndpoints: [
      {
        name: acrPrivateEndpointName
        subnetResourceId: privateEndpointSubnetId
      }
    ]

  }
}



module acrPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'acrPrivateEndpointDeployment'
  params: {
    name: acrPrivateEndpointName
    subnetResourceId: privateEndpointSubnetId
    privateLinkServiceConnections: [
      {
        name: acrPrivateEndpointName
        properties: {
          groupIds: ['registry']
          privateLinkServiceId: acrResource.outputs.resourceId
        }
      }
    ]
  }
  }
