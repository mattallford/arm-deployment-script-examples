param webApplicationName string
param sslCertThumbprint string
param fullCustomUrl string

// Import the existing Web App that was just deployed
resource webApplication 'Microsoft.Web/sites@2018-11-01' existing = {
  name: webApplicationName
}

resource bindHostnameToSslCertificate 'Microsoft.Web/sites/hostNameBindings@2021-01-01' = {
  parent: webApplication
  name: fullCustomUrl
  properties: {
    thumbprint: sslCertThumbprint
    sslState: 'SniEnabled'
  }
}
