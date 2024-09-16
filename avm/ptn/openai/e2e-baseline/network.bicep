/*
  Deploy vnet with subnets and NSGs
*/

@description('This is the base name for each Azure resource name (6-12 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

param developmentEnvironment bool = false

// variables
var vnetName = 'vnet-${baseName}'
var ddosPlanName = 'ddos-${baseName}'

var vnetAddressPrefix = '10.0.0.0/16'
var appGatewaySubnetPrefix = '10.0.1.0/24'
var appServicesSubnetPrefix = '10.0.0.0/24'
var privateEndpointsSubnetPrefix = '10.0.2.0/27'
var agentsSubnetPrefix = '10.0.2.32/27'

//Temp disable DDoS protection
var enableDdosProtection = !developmentEnvironment

// ---- Networking resources ----

// DDoS Protection Plan
module ddosProtectionPlan 'br/public:avm/res/network/ddos-protection-plan:0.1.4' =  if (enableDdosProtection == true){
  name: 'ddosProtectionPlanDeployment'
  params: {
    name: ddosPlanName
    location: location
  }
}

//vnet and subnets
module vnet 'br/public:avm/res/network/virtual-network:0.2.0' = {
  name: 'virtualNetworkDeployment'
  params: {
    // Required parameters
    addressPrefixes: [
      vnetAddressPrefix
    ]
    name: vnetName
    location: location
    ddosProtectionPlanResourceId: ddosProtectionPlan.outputs.resourceId
    subnets: [
      {
        //App services plan subnet
        name: 'snet-appServicePlan'
        properties: {
          addressPrefix: appServicesSubnetPrefix
          networkSecurityGroupResourceId: appServiceSubnetNsg.outputs.resourceId
    
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        //App Gateway subnet
        name: 'snet-appGateway'
        properties: {
          addressPrefix: appGatewaySubnetPrefix
          networkSecurityGroupResourceId: appGatewaySubnetNsg.outputs.resourceId
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        //Private endpoints subnet
        name: 'snet-privateEndpoints'
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          networkSecurityGroupResourceId: privateEndpointsSubnetNsg.outputs.resourceId
          
        }
      }
      {
        // Build agents subnet
        name: 'snet-agents'
        properties: {
          addressPrefix: agentsSubnetPrefix
          networkSecurityGroupResourceId: agentsSubnetNsg.outputs.resourceId  
        }
      }
    ]
  }
}

// doesn't really take conditionals :  ddosProtectionPlan: enableDdosProtection ? { id: ddosProtectionPlan.outputs.resourceId } : null

// calling an existing named subnet
// module agentsSubnet 'br/public:avm/res/network/virtual-network/subnet:' = {
//   name: 'snet-agents'
// }


//App Gateway subnet NSG

module appGatewaySubnetNsg 'br/public:avm/res/network/network-security-group:0.4.0' = {
  name: 'nsg-appGatewaySubnetDeployment'
  params: {
    name: 'nsg-appGatewaySubnet'
    location: location
    securityRules: [
      {
        name: 'AppGw.In.Allow.ControlPlane'
        properties: {
          access: 'Allow'
          destinationAddressPrefix: '*'
          destinationPortRange: '65200-65535'
          direction: 'Inbound'
          priority: 100
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
      {
        name: 'AppGw.In.Allow443.Internet'
        properties: {
          description: 'Allow ALL inbound web traffic on port 443'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: appGatewaySubnetPrefix
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AppGw.In.Allow.LoadBalancer'
        properties: {
          description: 'Allow inbound traffic from azure load balancer'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }  
      {
        name: 'AppGw.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the App Gateway subnet to the Private Endpoints subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetPrefix
          destinationAddressPrefix: privateEndpointsSubnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AppPlan.Out.Allow.AzureMonitor'
        properties: {
          description: 'Allow outbound traffic from the App Gateway subnet to Azure Monitor'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetPrefix
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
    ]
  }
}

//App service subnet nsg
module appServiceSubnetNsg 'br/public:avm/res/network/network-security-group:0.4.0' = {
  name: 'nsg-appServicesSubnetDeployment'
  params: {
    name: 'nsg-appServicesSubnet'
    location: location
    securityRules: [
      {
        name: 'AppPlan.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the app service subnet to the private endpoints subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: appServicesSubnetPrefix
          destinationAddressPrefix: privateEndpointsSubnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AppPlan.Out.Allow.AzureMonitor'
        properties: {
          description: 'Allow outbound traffic from App service to the AzureMonitor ServiceTag.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appServicesSubnetPrefix
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
    ]
  }
}

//Private endpoints subnets NSG
module privateEndpointsSubnetNsg 'br/public:avm/res/network/network-security-group:0.4.0' = {
  name: 'nsg-privateEndpointsSubnetDeployment'
  params: {
    name: 'nsg-privateEndpointsSubnet'
    location: location
    securityRules: [
      {
        name: 'PE.Out.Deny.All'
        properties: {
          description: 'Deny outbound traffic from the private endpoints subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: privateEndpointsSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 100
          direction: 'Outbound'
        }
      }      
    ]
  }
}

//Build agents subnets NSG
module agentsSubnetNsg 'br/public:avm/res/network/network-security-group:0.4.0' = {
  name: 'nsg-agentsSubnetDeployment'
  params: {
    name: 'nsg-agentsSubnet'
    location: location
    securityRules: [
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny outbound traffic from the build agents subnet. Note: adjust rules as needed after adding resources to the subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

@description('The name of the vnet.')
output vnetNName string = vnet.outputs.name
output vnetResourceId string = vnet.outputs.resourceId

@description('The name of the app service plan subnet.')
output appServicesSubnetName string = vnet.outputs.subnetNames[0]
output appServicesSubnetId string =vnet.outputs.subnetResourceIds[0]


@description('The name of the app gatewaysubnet.')
output appGatewaySubnetName string = vnet.outputs.subnetNames[1]
output appGatewaySubnetId string =vnet.outputs.subnetResourceIds[1]


@description('The name of the private endpoints subnet.')
output privateEndpointsSubnetName string = vnet.outputs.subnetNames[2]
output privateEndpointsSubnetId string =vnet.outputs.subnetResourceIds[2]

@description('The name of the agents subnet.')
output agentsSubnetName string = vnet.outputs.subnetNames[3]
output agentsSubnetSubnetId string =vnet.outputs.subnetResourceIds[3]
