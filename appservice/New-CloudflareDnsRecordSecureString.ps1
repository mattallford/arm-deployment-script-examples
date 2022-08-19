<#
  .SYNOPSIS
  Creates a DNS record in Cloudflare's hosted DNS service

  .DESCRIPTION
  The New-CloudflareDnsRecord.ps1 script uses the Cloudflare REST API to create DNS records
  in DNS zones hosted at Cloudflare. Optionally the script can update an existing record
  by using the UpdateRecord parameter. An API key will need to be generated in the Cloudflare
  service, and then passed to this script using the CloudFlareApiToken parameter.

  .PARAMETER DomainZoneName
  Specifies the name of the DNS zone to add the record in, for example domain.com.

  .PARAMETER RecordType
  Specifies the type of record to add to the DNS zone. Currently tested TXT, CNAME
  and A record types.

  .PARAMETER RecordName
  Specifies the name of the DNS record to create in the DNS zone.

  .PARAMETER RecordValue
  Specifies the value of the DNS record that will be created in the DNS zone.

  .PARAMETER Ttl
  Specified the time to live (ttl) value for the record being created,
  defaults to 3600 (1 hour).

  .PARAMETER CloudFlareApiToken
  Specifies the API Token to use for authorisation to the Cloudflare API.

  .PARAMETER UpdateRecord
  Use this parameter if the specified DNS record already exists in the
  specified DNS zone, but you want to update the value of the record.
#>


[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)]
	[string] $DomainZoneName,

    [Parameter(Mandatory=$true)]
    [ValidateSet("TXT","CNAME","A")]
    [string] $RecordType,

    [Parameter(Mandatory=$true)]
	[string] $RecordName,

    [Parameter(Mandatory=$true)]
	[string] $RecordValue,

    [Parameter(Mandatory=$false)]
	[int] $Ttl = 3600,

    [Parameter(Mandatory=$false)]
    [switch] $UpdateRecord
)

# Set up the API Header
$headers = @{
	"Authorization" = "Bearer $env:CloudFlareApiToken"
	"Content-Type" = "application/json"
}

# Set the base URL for API calls
$baseurl = "https://api.cloudflare.com/client/v4/zones"

# Set the URL to the domain name zone being used
$zoneurl = "$baseurl/?name=$DomainZoneName"

# Perform a GET request to get the DNS Zone and Zone ID
$zone = Invoke-RestMethod -Uri $zoneurl -Method Get -Headers $headers
$zoneid = $zone.result.id

# Set the Record URL to be modified / created
$recordurl = "$baseurl/$zoneid/dns_records/?name=$RecordName.$DomainZoneName"

# Get current DNS record
$dnsrecord = Invoke-RestMethod -Uri $recordurl -Method Get -Headers $headers

if ($dnsrecord.result.count -gt 0 -and $UpdateRecord) {
    # Update Existing DNS record
    Write-Output "Updating DNS Record $RecordName.$DomainZoneName of type $RecordType with value $RecordValue in DNS zone $DomainZoneName"
    $recordid = $dnsrecord.result.id
    $dnsrecord.result | Add-Member "content" $RecordValue -Force
    $body = $dnsrecord.result | ConvertTo-Json
    $updateurl = "$baseurl/$zoneid/dns_records/$recordid/"
    Invoke-RestMethod -Uri $updateurl -Method Put -Headers $headers -Body $body

} elseif ($dnsrecord.result.count -gt 0) {
    # If the record exists, and the UpdateRecord parameter is not used, just output the status
    Write-Output "DNS record specified already exists and UpdateRecord parameter not used ... not performing any changes. Existing Record:"
    $dnsrecord.result
} else {
    # Create new DNS record
    Write-Output "No existing DNS record found. Creating DNS Record $RecordName of type $RecordType with value $RecordValue in DNS zone $DomainZoneName"
    $newrecord = @{
		"type" = "$RecordType"
		"name" =  "$RecordName.$DomainZoneName"
		"content" = $RecordValue
        "ttl" = $Ttl
	}
    $body = $newrecord | ConvertTo-Json
    $newrecordurl = "$baseurl/$zoneid/dns_records"
    $request =  Invoke-RestMethod -Uri $newrecordurl -Method Post -Headers $headers -Body $body -ContentType "application/json"
    Write-Output "New record $RecordName.$DomainZoneName has been created with the ID $($request.result.id)"
}