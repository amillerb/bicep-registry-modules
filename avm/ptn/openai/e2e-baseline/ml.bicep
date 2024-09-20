targetScope = 'resourceGroup'

/*
  Deploy machine learning workspace, private endpoints and compute resources
*/

@description('This is the base name for each Azure resource name (6-8 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

// existing resource name params 
param vnetName string

@description('The name of the resource group containing the spoke virtual network.')
@minLength(1)
param virtualNetworkResourceGroupName string

param privateEndpointsSubnetName string
param applicationInsightsName string
param containerRegistryName string
param keyVaultName string
param mlStorageAccountName string
param logWorkspaceName string
param openAiResourceName string
param keyExpiration int = dateTimeToEpoch(dateTimeAdd(utcNow(), 'P60D'))

// ---- Variables ----
var workspaceName = 'mlw-${baseName}'
var resourceGroupName = resourceGroup().name

// Existing Resources
param privateEndpointsSubnetResourceId string
param applicationInsightsId string
param containerRegistryId string
param keyVaultId string // AML creates secrets that do not have expiry information attached, which is often forbidden through policy such as 'Secrets should have the specified maximum validity period'
param mlStorageId string
param openAIAccountId string
param logAnalyticsWorkspaceId string

// ---- RBAC built-in role definitions and role assignments ----



// ---- Managed Identities ----

@description('User managed identity that represents the Azure Machine Learning workspace.')
module azureMachineLearningWorkspaceManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'azureMachineLearningWorkspaceManagedIdentityDeployment'
  params: {
    name: 'id-amlworkspace'
    location: location
  }
}

@description('User managed identity that represents the Azure Machine Learning workspace\'s managed online endpoint.')
module azureMachineLearningOnlineEndpointManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'azureMachineLearningOnlineEndpointManagedIdentityDeployment'
  params: {
    name: 'id-amlonlineendpoint'
    location: location
  }
}

@description('User managed identity that represents the Azure Machine Learning workspace\'s compute instance.')
module azureMachineLearningInstanceComputeManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'azureMachineLearningInstanceComputeManagedIdentityDeployment'
  params: {
    name: 'id-amlinstancecompute'
    location: location
  }
}

// ---- Azure Machine Learning Workspace role assignments ----

module workspaceContributorToResourceGroupRoleAssignment 'br/public:avm/ptn/authorization/role-assignment:0.2.0' = {
  name: 'workspaceContributorToResourceGroupRoleAssignmentDeployment'
  scope: resourceGroup()
  params: {
    roleDefinitionIdOrName: '/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c' //Contributor role
    location: location
    principalType: 'ServicePrincipal'
    principalId: azureMachineLearningWorkspaceManagedIdentity.outputs.principalId
    resourceGroupName: resourceGroup().name
    subscriptionId: subscription().subscriptionId
  }
}

@description('Assign AML Workspace Azure Machine Learning Workspace Connection Secrets Reader to the endpoint managed identity.')
module onlineEndpointSecretsReaderRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'onlineEndpointSecretsReaderRoleAssignmentDeployment'
  params: {
    // name: guid(
    //   machineLearning.id,
    //   azureMachineLearningOnlineEndpointManagedIdentity.name,
    //   machineLearningConnetionSecretsReaderRole.id
    // )
    principalId: azureMachineLearningOnlineEndpointManagedIdentity.outputs.principalId
    resourceId: machineLearning.id
    roleDefinitionId: 'ea01e6af-a1c1-4350-9563-ad00f8c72ec5'
    description: 'Built-in Role: [Azure Machine Learning Workspace Connection Secrets Reader](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles)'
    principalType: 'ServicePrincipal'
    roleName: 'Azure Machine Learning Workspace Connection Secrets Reader'
  }
}

@description('Assign AML Workspace\'s ID: Storage Blob Data Contributor to workload\'s storage account.')
module storageBlobDataContributorRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'storageBlobDataContributorRoleAssignmentDeployment'
  params: {
    principalId: azureMachineLearningWorkspaceManagedIdentity.outputs.principalId
    resourceId: mlStorageId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    description: 'Built-in Role: [Storage Blob Data Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-data-contributor)'    
    principalType: 'ServicePrincipal'
    roleName: 'Storage Blob Data Contributor'
  }
}

@description('Assign AML Workspace\'s ID: Storage File Data Privileged Contributor to workload\'s storage account.')
module storageFileDataContributorRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'storageFileDataContributorRoleAssignmentDeployment'
  params: {
    principalId: azureMachineLearningWorkspaceManagedIdentity.outputs.principalId
    resourceId: mlStorageId
    roleDefinitionId: '69566ab7-960f-475b-8e7c-b3118f30c6bd'
    description: 'Built-in Role: [Storage File Data Privileged Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-file-data-privileged-contributor)'
    principalType: 'ServicePrincipal'
    roleName: 'Storage File Data Privileged Contributor'
  }
}

@description('Assign AML Workspace\'s ID: Key Vault Administrator to Key Vault instance.')
module keyVaultAdministratorRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'keyVaultAdministratorRoleAssignmentDeployment'
  params: {
    principalId: azureMachineLearningWorkspaceManagedIdentity.outputs.principalId
    resourceId: keyVaultId
    roleDefinitionId: '00482a5a-887f-4fb3-b363-3b7fe8e74483'
    description: 'Built-in Role: [Key Vault Administrator](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#key-vault-administrator)'
    principalType: 'ServicePrincipal'
    roleName: 'Key Vault Administrator'
  }
}

@description('Assign AML Workspace\'s ID: AcrPush to workload\'s container registry.')
module containerRegistryPushRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'containerRegistryPushRoleAssignmentDeployment'
  params: {
    principalId: azureMachineLearningWorkspaceManagedIdentity.outputs.principalId
    resourceId: containerRegistryId
    roleDefinitionId: '8311e382-0749-4cb8-b61a-304f252e45ec'
    description: 'Built-in Role: [AcrPush](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#acrpush)'
    principalType: 'ServicePrincipal'
    roleName: 'AcrPush'
  }
}

@description('Assign AML Workspace\'s Managed Online Endpoint: AcrPull to workload\'s container registry.')
module onlineEndpointContainerRegistryPullRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'onlineEndpointContainerRegistryPullRoleAssignmentDeployment'
  params: {
    principalId: azureMachineLearningOnlineEndpointManagedIdentity.outputs.principalId
    resourceId: containerRegistryId
    roleDefinitionId: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    description: 'Built-in Role: [AcrPull](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#acrpull)'
    principalType: 'ServicePrincipal'
    roleName: 'AcrPull'
  }
}

@description('Assign AML Workspace\'s Managed Online Endpoint: Storage Blob Data Reader to workload\'s ml storage account.')
module onlineEndpointBlobDataReaderRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'onlineEndpointBlobDataReaderRoleAssignmentDeployment'
  params: {
    principalId: azureMachineLearningOnlineEndpointManagedIdentity.outputs.principalId
    resourceId: mlStorageId
    roleDefinitionId: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
    description: 'Built-in Role: [Storage Blob Data Reader](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-data-reader)'
    principalType: 'ServicePrincipal'
    roleName: 'Storage Blob Data Reader'
  }
}

@description('Assign AML Workspace\'s Managed Online Endpoint: Storage Blob Data Reader to workload\'s ml storage account.')
module computeInstanceBlobDataReaderRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'computeInstanceBlobDataReaderRoleAssignmentDeployment'
  params: {
    principalId:  azureMachineLearningInstanceComputeManagedIdentity.outputs.principalId
    resourceId: mlStorageId
    roleDefinitionId: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
    description: 'Built-in Role: [Storage Blob Data Reader](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-data-reader)'
    principalType: 'ServicePrincipal'
    roleName: 'Storage Blob Data Reader'
  }
}


// ---- Machine Learning Workspace assets ----

@description('The Azure Machine Learning Workspace.')
module machineLearning 'br/public:avm/res/machine-learning-services/workspace:0.8.0' ={
  name: 'machineLearningDeployment'
  params: {
    name: workspaceName
    description: 'Azure Machine Learning workspace for this solution. Using platform-managed virtual network. Outbound access fully restricted.'
    location: location
    sku: 'Basic'
    hbiWorkspace: false
    primaryUserAssignedIdentity: azureMachineLearningWorkspaceManagedIdentity.outputs.resourceId
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        '${azureMachineLearningWorkspaceManagedIdentity.outputs.resourceId}'
      ]
    }

    // configuration for workspaces with private link endpoint
    imageBuildCompute: null
    publicNetworkAccess: 'Disabled'
    managedNetworkSettings: {
      isolationMode: 'AllowOnlyApprovedOutbound'
      outboundRules: {
        wikipedia: {
          type: 'FQDN'
          destination: 'en.wikipedia.org'
          category: 'UserDefined'
        }
        OpenAI: {
          type: 'PrivateEndpoint'
          destination: {
            serviceResourceId: openAIAccountId
            subresourceTarget: 'account'
            sparkEnabled: false
            sparkStatus: 'Inactive'
          }
        }
      }
    }
    // dependent resources
    associatedApplicationInsightsResourceId: applicationInsightsId
    associatedContainerRegistryResourceId: containerRegistryId
    associatedKeyVaultResourceId: keyVaultId
    associatedStorageAccountResourceId: mlStorageId
    computes: [
      {
        computeLocation: location
        computeType: 'ComputeInstance'
        description: 'Machine Learning compute instance'
        disableLocalAuth: true
        managedIdentities: {
          systemAssigned: false
          userAssignedResourceIds: [
             '${azureMachineLearningInstanceComputeManagedIdentity.outputs.resourceId}'
          ]
        }
        name: 'amli-${baseName}'
        location: location
        properties: {
          customServices: null
          enableNodePublicIp: false
          personalComputeInstanceSettings: null
          remoteLoginPortPublicAccess: 'Disabled'
          sshSettings: null
          vmPriority: 'Dedicated'
          vmSize: 'STANDARD_DS3_V2'
        }
        sku: 'Basic'
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspaceId
        logAnalyticsDestinationType: null
        logCategoriesAndGroups: [
          {
            category: 'allLogs'
          }
        ]
        name: 'default'

      }
    ]
  }
  dependsOn: [
    // Role assignments: https://learn.microsoft.com/azure/machine-learning/how-to-identity-based-service-authentication#user-assigned-managed-identity
    workspaceContributorToResourceGroupRoleAssignment
    storageBlobDataContributorRoleAssignment
    storageFileDataContributorRoleAssignment
    keyVaultAdministratorRoleAssignment
    containerRegistryPushRoleAssignment
  ]
}



// doesn't have a mention in AVM
@description('Managed online endpoint for the /score API.')
resource onlineEndpoint 'Microsoft.MachineLearningServices/workspaces/onlineEndpoints@2023-10-01'= {
  name: 'ept-${baseName}'
  location: location
  kind: 'Managed'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${azureMachineLearningOnlineEndpointManagedIdentity.outputs.clientId}': {}
    }
  }
  properties: {
    authMode: 'Key'
    description: 'Managed online endpoint for the /score API, to be used by the Chat UI app.'
    publicNetworkAccess: 'Disabled'
  }
  dependsOn: [
    // Role requirements for the online endpoint: https://learn.microsoft.com/azure/machine-learning/how-to-access-resources-from-endpoints-managed-identities#give-access-permission-to-the-managed-identity
    onlineEndpointContainerRegistryPullRoleAssignment
    onlineEndpointBlobDataReaderRoleAssignment
    onlineEndpointSecretsReaderRoleAssignment
  ]
}

@description('Azure Diagnostics: Online Endpoint - allLogs')
resource endpointDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: onlineEndpoint
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}



module machineLearningPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'keyVaultPrivateEndpointDeployment'
  params: {
    name: 'pep-${workspaceName}'
    location: location
    subnetResourceId: privateEndpointsSubnetResourceId
    privateLinkServiceConnections: [
      {
        name: 'pep-${workspaceName}'
        properties: {
          groupIds: ['amlworkspace']
          privateLinkServiceId: machineLearning.outputs.resourceId
        }
      }
    ]
  }
}
