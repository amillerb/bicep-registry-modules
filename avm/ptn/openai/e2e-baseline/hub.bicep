var vnetDeploymentName = 'vnet-hub-deployment'
var nsgDeploymentName = 'sharedPE-nsg-hub-deployment'
var rtDeploymentPEName = 'udr-sharedPrivateEndpoints-deployment'

var vnetName = 'vnet-hub'
var privateEndpointsSubnetName = 'snet-sharedPrivateEndpoints'
param location string

var rtSharedPEName = 'udr-sharedPrivateEndpoints'
var nsgSharedPrivateEndpointsName = 'nsg-sharedPrivateEndpointsSubnet'

var fwPrivateIP = '10.1.1.4'
var azureFirewallSubnetPrefix = '10.1.1.0/26'
var sharedPEPrefix = '10.1.2.0/24'

//Route Table

module rtSharedPE 'br/public:avm/res/network/route-table:0.2.1' = {
  name: rtDeploymentPEName
  params: {
    name: rtSharedPEName
    location: location
    routes: [
      {
        name: 'default'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopIpAddress: fwPrivateIP
          nextHopType: 'VirtualAppliance'
        }
      }
    ]
  }
}
output rtId string = rtSharedPE.outputs.resourceId

module hubvnet 'br/public:network/virtual-network:1.1.3' = {
  name: vnetDeploymentName
  params: {
    name: vnetName
    location: location
    addressPrefixes: [
      '10.1.0.0/16'
    ]
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        addressPrefix: '10.1.1.0/26'
      }
      {
        name: privateEndpointsSubnetName
        addressPrefix: '10.1.2.0/24'
        networkSecurityGroupResourceId: nsgSharedPrivateEndpoint.outputs.resourceId
        routeTableResourceId: rtSharedPE.outputs.resourceId
      }
    ]
  }
}
output vnetId string = hubvnet.outputs.resourceId



// NSGs
module nsgSharedPrivateEndpoint 'br/public:avm/res/network/network-security-group:0.1.2' = {
  name: nsgDeploymentName
  params: {
    name: nsgSharedPrivateEndpointsName
    location: location
    securityRules: [
      {
        name: 'SharedPrivateEndpoints.In.Allow.AzureFirewall'
        properties: {
          access: 'Allow'
          description: 'Allow inbound access from the Azure Firewall Subnet'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
          direction: 'Inbound'
          priority: 130
          protocol: 'Tcp'
          sourceAddressPrefix: azureFirewallSubnetPrefix
          sourcePortRange: '*'
        }
      }
      {
        name: 'DenyVnetInBound'
        properties: {
          access: 'Deny'
          description: 'Deny inbound traffic from other subnets to the appServices subnet. Note: adjust rules as needed after adding resources to the subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny outbound traffic from the app services (vnet integration) subnet. Note: adjust rules as needed after adding resources to the subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: sharedPEPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
     
    ]
   }
}
