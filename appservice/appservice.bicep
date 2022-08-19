@description('Enter the location to deploy the resources to')
param location string

param now string = utcNow('F')

@description('Enter the value for the first part of the custom domain name that will be configured on the app service. For example, "youtubedemo"')
param customDomainRecordName string

@description('Enter the custom domain name zone where the DNS record needs to be created. For example, mattallford.com')
param customDomainZoneName string

@description('Enter the Cloudflare API Token')
@secure()
param cloudFlareApiToken string

var fullCustomUrl = '${customDomainRecordName}.${customDomainZoneName}'

resource appServicePlan 'Microsoft.Web/serverfarms@2020-12-01' = {
  name: 'deployscriptasp01'
  location: location
  sku: {
    name: 'P1v2'
    capacity: 1
    tier: 'PremiumV2'
    size: 'p1v2'
  }
  properties: {
    reserved: true
  }
}


resource webApplication 'Microsoft.Web/sites@2021-01-01' = {
  name: 'deployscriptapp01'
  location: location
  kind: 'app,linux,container'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|mcr.microsoft.com/appsvc/staticsite:latest'
      netFrameworkVersion: 'v4.0'
      numberOfWorkers: 1
      alwaysOn: true
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
  }
}

resource createCloudFlareCnameRecord 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'createCloudFlareCnameRecord'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '6.2.1'
    arguments: ' -DomainZoneName ${customDomainZoneName} -RecordType CNAME -RecordName ${customDomainRecordName} -RecordValue ${webApplication.properties.defaultHostName} -CloudFlareApiToken ${cloudFlareApiToken} -UpdateRecord'
    scriptContent: loadTextContent('New-CloudflareDnsRecord.ps1')
    cleanupPreference: 'OnSuccess' //When to clean up the storage account and container
    retentionInterval: 'PT1H' //How long to keep the deployment script resource
    forceUpdateTag: now //Change this value between deployments to force the deployment script to rerun
  }
}

resource hostnameBinding 'Microsoft.Web/sites/hostNameBindings@2021-01-01' = {
  dependsOn: [
    createCloudFlareCnameRecord
  ]
  parent: webApplication
  name: fullCustomUrl
}

resource appServiceManagedCertificate 'Microsoft.Web/certificates@2021-01-01' = {
  dependsOn: [
    hostnameBinding
  ]
  name: 'appServiceCert'
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    canonicalName: fullCustomUrl
  }
}

module bindSslCertToCustomHostname 'bindsslcert.bicep' = {
  name: 'bindSslCertToCustomHostname'
  params: {
    fullCustomUrl: fullCustomUrl
    sslCertThumbprint: appServiceManagedCertificate.properties.thumbprint
    webApplicationName: webApplication.name
  }
}
