/*
  Deploy a SQL server with a sample database, a private endpoint and a private DNS zone
*/
@description('This is the base name for each Azure resource name (6-12 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

@description('The administrator username of the SQL server')
param sqlAdministratorLogin string
@description('The administrator password of the SQL server.')
@secure()
param sqlAdministratorLoginPassword string

// existing resource name params 
param privateEndpointsSubnetId string

// variables
var sqlServerName = 'sql-${baseName}'
var sampleSqlDatabaseName = 'sqldb-adventureworks'
var sqlPrivateEndpointName = 'pep-${sqlServerName}'
var sqlDnsGroupName = '${sqlPrivateEndpointName}/default'
var sqlDnsZoneName = 'privatelink${environment().suffixes.sqlServerHostname}'
var sqlConnectionString = 'Server=tcp:${sqlServerName}${environment().suffixes.sqlServerHostname},1433;Initial Catalog=${sampleSqlDatabaseName};Persist Security Info=False;User ID=${sqlAdministratorLogin};Password=${sqlAdministratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

// ---- Existing resources ----


// ---- Sql resources ----
module sqlServer 'br/public:avm/res/sql/server:0.4.1' = {
  name: 'serverDeployment'
  params: {
    name: sqlServerName
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorLoginPassword
    publicNetworkAccess: 'Disabled'
    location: location
    tags: {
      displayName: sqlServerName
    }
    databases: [
      {
        capacity: 5
        collation: 'SQL_Latin1_General_CP1_CI_AS'
        licenseType: 'LicenseIncluded'
        maxSizeBytes: 104857600
        name: sampleSqlDatabaseName
        skuName: 'Basic'
        skuTier: 'Basic'
        tags: {
          displayName: sampleSqlDatabaseName
        }
        sampleName: 'AdventureWorksLT'
      }
    ]
    privateEndpoints: [
      {
        privateDnsZoneResourceIds: [
          sqlPrivateEndpoint.outputs.resourceId
        ]
        subnetResourceId: privateEndpointsSubnetId
      }
    ]
  }
}



//DNS Zones & Private Endpoint
module sqlPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.5.0' = {
  name: 'sqlPrivateEndpointDeployment'
  params: {
    name: sqlPrivateEndpointName
    subnetResourceId: privateEndpointsSubnetId
    location: location
    privateDnsZoneResourceIds: [
      sqlPrivateDnsZone.outputs.resourceId
    ]
    privateDnsZoneGroupName: sqlDnsGroupName
  }
}

module sqlPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.4.0' = {
  name: 'privateDnsZoneDeployment'
  params: {
    name: sqlDnsZoneName
    location: 'global'
  }
}

@description('The connection string to the sample database.')
output sqlConnectionString string = sqlConnectionString
