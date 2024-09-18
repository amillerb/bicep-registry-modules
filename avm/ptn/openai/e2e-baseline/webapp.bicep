/*
  Deploy a web app with a managed identity, diagnostic, and a private endpoint
*/

@description('This is the base name for each Azure resource name (6-12 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

param developmentEnvironment bool
param publishFileName string

// existing resource params 
param vnetResourceId string
param appServicesSubnetId string
param privateEndpointsSubnetId string
param storageName string
param storageId string
param keyVaultName string
param keyVaultId string
param logWorkspaceId string


// variables
var appName = 'app-${baseName}'
var appServicePlanName = 'asp-${appName}${uniqueString(subscription().subscriptionId)}'
var appServiceManagedIdentityName = 'id-${appName}'
var packageLocation = 'https://${storageName}.blob.${environment().suffixes.storage}/deploy/${publishFileName}'
var appServicePrivateEndpointName = 'pep-${appName}'
var appInsightsName= 'appinsights-${appName}'

var appServicePlanPremiumSku = 'P2v2'
var appServicePlanStandardSku = 'S1'
var appServicePlanPremiumCapacity = 1
var appServicePlanStandardCapacity = 3

var appServicesDnsZoneName = 'privatelink.azurewebsites.net'
var appServicesDnsGroupName = '${appServicePrivateEndpointName}/default'

//** replace existing with the module reference


// ---- Existing resources ----


// Built-in Azure RBAC role that is applied to a Key Vault to grant secrets content read permissions. 
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '4633458b-17de-408a-b874-0445c86b69e6'
  scope: subscription()
}

// Built-in Azure RBAC role that is applied to a Key storage to grant data reader permissions. 
resource blobDataReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  scope: subscription()
}

// ---- Web App resources ----

// Managed Identity for App Service
resource appServiceManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: appServiceManagedIdentityName
  location: location
}

// Grant the App Service managed identity key vault secrets role permissions
module appServiceSecretsUserRoleAssignmentModule 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'appServiceSecretsUserRoleAssignmentDeployment'
  params: {
    principalId: appServiceManagedIdentity.properties.principalId
    resourceId: keyVaultId
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalType: 'ServicePrincipal'
  }
}

// Grant the App Service managed identity storage data reader role permissions
module blobDataReaderRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'resourceRoleAssignmentDeployment'
  params: {
    principalId: appServiceManagedIdentity.properties.principalId
    resourceId: storageId
    roleDefinitionId: blobDataReaderRole.id
    principalType: 'ServicePrincipal'
  }
}


//App service plan
module appServicePlan 'br/public:avm/res/web/serverfarm:0.2.2' = {
  name: 'appServicePlanDeployment'
  params: {
    name: appServicePlanName
    skuCapacity:developmentEnvironment ? appServicePlanStandardCapacity : appServicePlanPremiumCapacity
    skuName: developmentEnvironment ? appServicePlanStandardSku : appServicePlanPremiumSku
    location: location
    zoneRedundant: !developmentEnvironment
    kind: 'App'
  }
}


// Web App -- the public assess is disabled but deploying in an enabled state
module webApp 'br/public:avm/res/web/site:0.4.0' = {
  name: 'webAppDeployment'
  params: {
    kind: 'app'
    name: appName
    serverFarmResourceId:  appServicePlan.outputs.resourceId
    virtualNetworkSubnetId: appServicesSubnetId
    httpsOnly: false
    keyVaultAccessIdentityResourceId: appServiceManagedIdentity.id
    // hostNamesDisabled: false //disable public host names
    location: location
    managedIdentities: { 
      userAssignedResourceIds:[
        appServiceManagedIdentity.id
    ]
  }
    siteConfig: {
      appSettings: [
        {
          WEBSITE_RUN_FROM_PACKAGE: packageLocation
          WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID: appServiceManagedIdentity.id
          AZURE_SQL_CONNECTIONSTRING: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}${environment().suffixes.keyvaultDns}/secrets/adWorksConnString)'
          APPINSIGHTS_INSTRUMENTATIONKEY: appInsights.outputs.instrumentationKey
          APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.outputs.connectionString
          ApplicationInsightsAgent_EXTENSION_VERSION: '~2'
        }
      ]
    }
  }
}

// App service private endpoint

module appServicePrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'appServicePrivateEndpointDeployment'
  params: {
    name: appServicePrivateEndpointName
    subnetResourceId: privateEndpointsSubnetId
    location: location
    privateDnsZoneGroup: {
      name: appServicesDnsGroupName
      privateDnsZoneGroupConfigs: [
        {
          name: 'privatelink.azurewebsites.net'
          privateDnsZoneResourceId:appServiceDnsZone.outputs.resourceId
        }
      ]
    }
    privateLinkServiceConnections: [
      {
        name: appServicePrivateEndpointName
        properties: {
          groupIds: [
            'sites'
          ]
          privateLinkServiceId: webApp.outputs.resourceId
        }
      }
    ]
  }
}

module appServiceDnsZone 'br/public:avm/res/network/private-dns-zone:0.4.0' = {
  name: 'appServicePrivateDnsZoneDeployment'
  params: {
    name: appServicesDnsZoneName
    location: 'global'
    virtualNetworkLinks: [
      {
        name: '${appServicesDnsZoneName}-link'
        registrationEnabled: false
        virtualNetworkResourceId: vnetResourceId
      }
    ]
  }  
}


// App service plan diagnostic settings
module appServicePlanDiagSettings 'br/public:avm/res/insights/diagnostic-setting:0.1.3' = {
  name: 'appServiceDiagnosticSettingDeployment'
  params: {
    location: location
    metricCategories: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    name: '${appServicePlan.name}-diagnosticSettings'
    workspaceResourceId: logWorkspaceId
  }
  scope: subscription()
}

//Web App diagnostic settings
module webAppDiagSettings 'br/public:avm/res/insights/diagnostic-setting:0.1.3' = {
  name: 'webAppDiagnosticSettingDeployment'
  params: {
    location: location
    metricCategories: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    logCategoriesAndGroups: [
      {
        category: 'AppServiceHTTPLogs'
        categoryGroup: null
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        categoryGroup: null
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        categoryGroup: null
        enabled: true
      }
    ]
    name: '${webApp.name}-diagnosticSettings'
    workspaceResourceId: logWorkspaceId
  }
  scope: subscription()
}

// App service plan auto scale settings -- no AVM module for this
resource appServicePlanAutoScaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: '${appServicePlan.name}-autoscale'
  location: location
  properties: {
    enabled: true
    targetResourceUri: appServicePlan.outputs.resourceId
    profiles: [
      {
        name: 'Scale out condition'
        capacity: {
          maximum: '5'
          default: '1'
          minimum: '1'
        }
        rules: [
          {
            scaleAction: {
              type: 'ChangeCount'
              direction: 'Increase'
              cooldown: 'PT5M'
              value: '1'
            }
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricNamespace: 'microsoft.web/serverfarms'
              operator: 'GreaterThan'
              timeAggregation: 'Average'
              threshold: 70
              metricResourceUri: appServicePlan.outputs.resourceId
              timeWindow: 'PT10M'
              timeGrain: 'PT1M'
              statistic: 'Average'
            }
          }
        ]
      }
    ]
  }
  dependsOn: [
    webApp
    appServicePlanDiagSettings
  ]
}

// create application insights resource

module appInsights 'br/public:avm/res/insights/component:0.4.0' = {
  name: 'appInsightsComponentDeployment'
  params: {
    name: appInsightsName
    workspaceResourceId: logWorkspaceId
    location: location
    applicationType:'web'
    kind: 'web'
  }
}


@description('The name of the app service plan.')
output appServicePlanName string = appServicePlan.name

@description('The name of the web app.')
output appName string = webApp.name
