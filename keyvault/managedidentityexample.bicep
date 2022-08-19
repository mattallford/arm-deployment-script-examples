param location string
param now string = utcNow('F')
param destinationKeyVaultName string
param sslCertificateName string

// Import the existing source key vault
resource sourceKeyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: 'kvsourcedeployscript01'
}

// Create a User Assigned Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: 'keyvault-copy-cert-umi'
  location: location
}

// Provide access to the source key vault for the UAMI
resource sourceKeyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = {
  parent: sourceKeyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        permissions: {
          certificates: [
            'get'
          ]
          secrets: [
            'get'
          ]
        }
        tenantId: subscription().tenantId
        objectId: managedIdentity.properties.principalId
      }
    ]
  }
}

// Deploy the destination key vault and give access to the UAMI
resource destinationKeyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: destinationKeyVaultName
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    tenantId: subscription().tenantId
    accessPolicies: [
      // Add access policy for the managed identity
      {
        tenantId: subscription().tenantId
        objectId: managedIdentity.properties.principalId
        permissions: {
          certificates: [
            'all'
          ]
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

// Run the deployment script to copy the SSL cert from the source KV to the destination KV
resource copySslCertificateScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'copySslCertificate'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '6.2.1'
    arguments: ' -SourceKeyVaultName ${sourceKeyVault.name} -DestinationKeyVaultName ${destinationKeyVault.name} -SourceAzureSubscriptionId "${subscription().subscriptionId}" -DestinationAzureSubscriptionId "${subscription().subscriptionId}" -CertificateName ${sslCertificateName}' 
    scriptContent: loadTextContent('Copy-KeyVaultCertificate.ps1')
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'PT4H'
    forceUpdateTag: now
  }
}
