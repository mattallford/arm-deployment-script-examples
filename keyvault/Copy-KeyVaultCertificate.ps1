<#
  .SYNOPSIS
  Copies a certificate from one Azure Key Vault to another, even across subscriptions

  .DESCRIPTION
  The Copy-KeyVaultCertificate.ps1 script assists with copying an SSL certificate
  from one Azure Key Vault to another Azure Key Vault. The script can accomodate
  copying more than one certificate in a single call, and can also copy the SSL
  certificate between key vaults in different subscriptions. The main requirement
  is that the user or principal running this script has access to both the source
  and destination key vault resources, both from an access policy and firewall
  perspective. This script can be handy in situations where you need a certificate
  in multiple key vault resources, but don't want to upload / copy it manually. By
  default, the script will only copy the certificate to the destination key vault
  if either the certificate doesn't exist, or if the thumbprint is different between
  the source and destination Key Vaults (the assumption here is the SSL cert in the
  source key vault has been updated).

  .PARAMETER SourceKeyVaultName
  Specify the name of the source key vault where the SSL certificate(s) are located.
  This is the short name of the key vault resource, not the FQDN.

  .PARAMETER DestinationKeyVaultName
  Specify the name of the destination key vault to copy the SSL certificate(s) to.
  This is the short name of the key vault resource, not the FQDN.

  .PARAMETER SourceAzureSubscriptionId
  Specify the subscription ID where the source key vault is located.

  .PARAMETER DestinationAzureSubscriptionId
  Specify the subscription ID where the destination key vault is located.

  .PARAMETER CertificateName
  Specify the name(s) of the SSL certificate(s) as they appear in the source
  key vault, that will be copied to the destination key vault. Accepts comma
  separated strings such as cert1,cert2,cert3 or "cert1", "cert2", "cert3"

  .EXAMPLE
  PS> .\Copy-KeyVaultCertificate.ps1 -SourceKeyVaultName kv-mgmt-01 -DestinationKeyVaultName kv-prod-01 -SourceAzureSubscriptionId 98765-43210-00000 -DestinationAzureSubscriptionId 12345-678910-11111 -CertificateName wildcard-domain-com-certificate

  .EXAMPLE
  PS> .\Copy-KeyVaultCertificate.ps1 -SourceKeyVaultName kv-mgmt-01 -DestinationKeyVaultName kv-prod-01 -SourceAzureSubscriptionId 98765-43210-00000 -DestinationAzureSubscriptionId 12345-678910-11111 -CertificateName cert1,cert2,cert3

  .EXAMPLE
  PS> .\Copy-KeyVaultCertificate.ps1 -SourceKeyVaultName kv-mgmt-01 -DestinationKeyVaultName kv-prod-01 -SourceAzureSubscriptionId 98765-43210-00000 -DestinationAzureSubscriptionId 12345-678910-11111 -CertificateName "cert1","cert2","cert3"
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)]
	[string] $SourceKeyVaultName,

    [Parameter(Mandatory=$true)]
    [string] $DestinationKeyVaultName,

    [Parameter(Mandatory=$true)]
	[string] $SourceAzureSubscriptionId,

    [Parameter(Mandatory=$true)]
	[string] $DestinationAzureSubscriptionId,

    [Parameter(Mandatory=$true)]
	[string[]] $CertificateName
)

#Create a function to perform the certificate copy as this needs to get called from multiple places
function Copy-Certificate {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string] $SourceKeyVaultName,

        [Parameter(Mandatory=$true)]
        [string] $DestinationKeyVaultName,

        [Parameter(Mandatory=$true)]
        [string] $SourceAzureSubscriptionId,

        [Parameter(Mandatory=$true)]
        [string] $DestinationAzureSubscriptionId,

        [Parameter(Mandatory=$true)]
        [string] $CertificateName
    )
    # Log in to the source subscription and get the certificate and secret from key vault
    Set-AzContext -SubscriptionId $SourceAzureSubscriptionId

    $SourceCert = Get-AzKeyVaultCertificate -VaultName $SourceKeyVaultName -Name $CertificateName
    $secret = Get-AzKeyVaultSecret -VaultName $SourceKeyVaultName -Name $SourceCert.Name

    # Create a certificate object in PowerShell
    $secretValueText = '';
    $ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret.SecretValue)
    try {
        $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
    }
    $secretByte = [Convert]::FromBase64String($secretValueText)
    $x509Cert = new-object System.Security.Cryptography.X509Certificates.X509Certificate2($secretByte, "", "Exportable,PersistKeySet")

    # Log in to the destination subscription and import the certificate object to the destination vault
    Set-AzContext -SubscriptionId $DestinationAzureSubscriptionId
    Import-AzKeyVaultCertificate -VaultName $DestinationKeyVaultName -Name $CertificateName -CertificateCollection $x509Cert
}

foreach ($certificate in $CertificateName) {
    #Check to see if the certificate already exists in the destination key vault
    Set-AzContext -SubscriptionId $DestinationAzureSubscriptionId
    $DestinationCert = Get-AzKeyVaultCertificate -VaultName $DestinationKeyVaultName -Name $certificate

    if ($DestinationCert) {
        Write-Output "Certificate exists in destination Key Vault ... checking to see if thumbprint matches"
        # Log in to the source subscription and get the certificate and secret from key vault
        Set-AzContext -SubscriptionId $SourceAzureSubscriptionId
        $SourceCert = Get-AzKeyVaultCertificate -VaultName $SourceKeyVaultName -Name $certificate

        # Check to see if the thumbprint on the certificates match. If they do, no need to copy
        # but if they don't, copy the cert from source key vault to the destination key vault
        if ($SourceCert.Certificate.Thumbprint -match $DestinationCert.Certificate.Thumbprint) {
            Write-Output "Certificate exists in destination Key Vault and thumbprint matches ... nothing to do"
        } else {
            Write-Output "Copying certificate with thumbprint $($SourceCert.Certificate.Thumbprint) and subject $($SourceCert.Certificate.Subject) from $SourceKeyVaultName to $DestinationKeyVaultName"

            # Call the Copy-Certificate function to perform a copy of the certificate from the source key vault to the desintation vault
            Copy-Certificate -SourceKeyVaultName $SourceKeyVaultName -DestinationKeyVaultName $DestinationKeyVaultName -SourceAzureSubscriptionId $SourceAzureSubscriptionId -DestinationAzureSubscriptionId $DestinationAzureSubscriptionId -CertificateName $certificate
        }

    } else {
        Write-Output "Certificate does not exist in destination Key Vault ... copying now ..."
        # Call the Copy-Certificate function to perform a copy of the certificate from the source key vault to the desintation vault
        Copy-Certificate -SourceKeyVaultName $SourceKeyVaultName -DestinationKeyVaultName $DestinationKeyVaultName -SourceAzureSubscriptionId $SourceAzureSubscriptionId -DestinationAzureSubscriptionId $DestinationAzureSubscriptionId -CertificateName $certificate
    }
}

