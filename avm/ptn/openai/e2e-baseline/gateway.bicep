/*
  Deploy an Azure Application Gateway with WAF v2 and a custom domain name.
*/

@description('This is the base name for each Azure resource name (6-12 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

@description('Optional. When true will deploy a cost-optimised environment for development purposes.')
param developmentEnvironment bool

@description('Domain name to use for App Gateway')
param customDomainName string

param availabilityZones array
param gatewayCertSecretUri string

// existing resource  params 
param appGatewaySubnetId string
param appName string
param keyVaultId string
param webAppDefaultHostName string
param logWorkspaceId string

//variables
var appGateWayName = 'agw-${baseName}'
var appGatewayManagedIdentityName = 'id-${appGateWayName}'
var appGatewayPublicIpName = 'pip-${baseName}'
var appGateWayFqdn = 'fe-${baseName}'
var wafPolicyName= 'waf-${baseName}'

// ---- Existing resources ----


// Built-in Azure RBAC role that is applied to a Key Vault to grant with secrets content read privileges. Granted to both Key Vault and our workload's identity.
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '4633458b-17de-408a-b874-0445c86b69e6'
  scope: subscription()
}

// ---- App Gateway resources ----

// Managed Identity for App Gateway. 


module appGatewayManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.2' = {
  name: 'appgwUserAssignedIdentityDeployment'
  params: {
    name: appGatewayManagedIdentityName
    location: location
  }
}
// Grant the Azure Application Gateway managed identity with key vault secrets role permissions; this allows pulling certificates.
module appGatewaySecretsUserRoleAssignmentModule 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'appGatewaySecretsUserRoleAssignmentDeploy'
  params: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: appGatewayManagedIdentity.outputs.principalId
    resourceId: keyVaultId
  }
}

//External IP for App Gateway
module appGatewayPublicIp 'br/public:avm/res/network/public-ip-address:0.4.2' = {
  name: 'appgwPublicIpAddressDeployment'
  params: {
    name: appGatewayPublicIpName
    dnsSettings: {
      domainNameLabel: appGateWayFqdn
      domainNameLabelScope: 'ResourceGroupReuse'
    }
    location: location
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    skuName: 'Standard'
    skuTier: 'Regional'
    zones: !developmentEnvironment ? availabilityZones : null
  }
}
module wafPolicy 'br/public:avm/res/network/application-gateway-web-application-firewall-policy:0.1.1' = {
  name: 'applicationGatewayWebApplicationFirewallPolicyDeployment'
  params: {
    policySettings: {
      fileUploadLimitInMb: 10
      state: 'Enabled'
      mode: 'Prevention'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '0.1'
        }
      ]
    }
    name: wafPolicyName
    location: location
  }
}

//App Gateway
module appGateWay 'br/public:avm/res/network/application-gateway:0.1.0' = {
  name: 'applicationGatewayDeployment'
  params: {
    name: appGateWayName
    zones: !developmentEnvironment ? availabilityZones : null
    backendAddressPools: [
      {
        name: 'pool-${appName}'
        properties: {
          backendAddresses: [
            {
              fqdn: webAppDefaultHostName
            }
          ]
        }
      }
    ]
    managedIdentities: {
      userAssignedResourceIds: ['${appGatewayManagedIdentity.outputs.resourceId}']
    }
    
    
    backendHttpSettingsCollection: [
      {
        name: 'WebAppBackendHttpSettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGateWayName, 'probe-web${baseName}')
          }
        }
      }
    ]
    enableHttp2: false
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: appGatewayPublicIp.outputs.resourceId
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port-443'
        properties: {
          port: 443
        }
      }
      
    ]
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: appGatewaySubnetId
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'WebAppListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGateWayName, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGateWayName, 'port-443')
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', appGateWayName, '${appGateWayName}-ssl-certificate')
          }
          hostName: 'www.${customDomainName}'
          hostNames: []
          requireServerNameIndication: true
        }
      }
    ]
    location: location
    probes: [
      {
        name: 'probe-web${baseName}'
        properties: {
          protocol: 'Https'
          path: '/favicon.ico'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
              '401'
              '403'
            ]
          }
        }
      }
    ]
   
    sku: 'WAF_v2'
    sslCertificates: [
      {
        name: '${appGateWayName}-ssl-certificate'
        properties: {
          keyVaultSecretId: gatewayCertSecretUri
        }
      }
    ]
    sslPolicyType: 'Custom'
    sslPolicyCipherSuites: [
        'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'
        'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
      ]
    sslPolicyMinProtocolVersion: 'TLSv1_2'
    firewallPolicyId: wafPolicy.outputs.resourceId
    diagnosticSettings: [
      {
       
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
        name: '$appgw-diagnosticSettings'
        workspaceResourceId: logWorkspaceId
      }
    ]
  }
}
// App Gateway diagnostics


@description('The name of the app gateway resource.')
output appGateWayName string = appGateWay.name
