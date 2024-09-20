targetScope = 'resourceGroup'

param baseName string

@description('The resource group location')
param location string = resourceGroup().location

//variables
var openaiName = 'oai-${baseName}'
var openaiPrivateEndpointName = 'pep-${openaiName}'

// existing resources
param privateEndpointsSubnetId string
param logAnalyticsWorkspaceId string
param keyVaultId string

module openAiAccount 'br/public:avm/res/cognitive-services/account:0.7.0' = {
  name: 'openAiAccountDeployment'
  params: {
    kind: 'OpenAI'
    name: openaiName
    customSubDomainName: 'oai${baseName}'
    disableLocalAuth: false // Ideally you'd set this to 'true' and use Microsoft Entra ID. This is usually enforced through the policy 'Azure AI Services resources should have key access disabled (disable local authentication)'
    // secretsExportConfiguration: {
    //   accessKey1Name: 'key1'
    //   keyVaultResourceId: '<keyVaultResourceId>'
    // }
    deployments: [
      {
        model: {
          format: 'OpenAI'
          name: 'gpt-35-turbo'
          version: '0613'
        }
        name: 'gpt35'
        sku: {
          capacity: 25
          name: 'Standard'
        }
        raiPolicyName: 'blockingFilter'
        // versionAutoUpgrade: 'NoAutoUpgrade'
      }
    ]
    location: location
    networkAcls: {
      defaultAction: 'Deny'
    }
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspaceId
        logCategoriesAndGroups: [
          {
            category: 'RequestResponse'
          }
          {
            category: 'Audit'
          }
        ]
      }
    ]
    publicNetworkAccess: 'Disabled'
   
  }
  }

  module openaiPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
    name: 'openaiPrivateEndpointDeployment'
    params: {
      name: openaiPrivateEndpointName
      location: location
      subnetResourceId: privateEndpointsSubnetId
      privateLinkServiceConnections: [
        {
          name: openaiPrivateEndpointName
          properties: {
            groupIds: ['account']
            privateLinkServiceId: openAiAccount.outputs.resourceId
          }
        }
      ]
    }
  }
  

// ---- Outputs ----
output openAiResourceName string = openAiAccount.name
