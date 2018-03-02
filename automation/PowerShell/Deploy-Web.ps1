
[CmdletBinding()]
param(
    # Working directory
    [string] $Dir = "C:\cloud-automation",
    
    # Application ID
    [string] $ApplicationId = "WebApplication1",

    # IIS Web Site Name
    [string] $WebSiteName = "Default Web Site",

    # Name of the Key Vault
    [string] $KeyVaultName = "iskdemo01-kv",

    # Name of the Artefact Storage Account
    [string] $ArtefactStorageAccount = "iskdemo01sa",

    # Name of the Artefact Blob Container
    [string] $ArtefactContainer = "artefacts",

    # Version string for the artefact (the Blob prefix)
    [string] $ArtefactVersion = "latest",

    # Path to artefact in Blob Storage
    [string] $ArtefactName = "WebApplication1.zip",

    # Name of the current Environment
    [string] $Environment = "SIT",

    # Deployment ID or number
    [string] $DeployNumber = "Release-Local",
    
    # Deployment URL
    [string] $DeployUrl = "http://local-deployment"
)

New-Item -Path $Dir\logs -ItemType Directory -ErrorAction SilentlyContinue
Start-Transcript -Path $Dir\logs\Deploy-Web.log -Append

Push-Location -Path $Dir
New-Item -Path $Dir\artefacts -ItemType Directory -ErrorAction SilentlyContinue
New-Item -Path $Dir\environments -ItemType Directory -ErrorAction SilentlyContinue

# Get data from Instance metadata
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/instance-metadata-service
$Metadata = $(Invoke-RestMethod `
    -UseBasicParsing `
    -URI http://169.254.169.254/metadata/instance?api-version=2017-08-01 `
    -Headers @{"Metadata"="true"} `
    -Method get)

$SubscriptionId = $Metadata.compute.subscriptionId
$ResourceGroup = $Metadata.compute.resourceGroupName

function Get-AccessToken([string]$Resource) 
{
    $response = Invoke-WebRequest -Verbose `
        -UseBasicParsing `
        -Uri http://localhost:50342/oauth2/token `
        -Method GET `
        -Headers @{Metadata="true"} `
        -Body @{resource="$Resource"}
    return ($response.Content | ConvertFrom-Json).access_token
}

# On the VM, get a ARM access token for the MSI
$ArmToken = Get-AccessToken -Resource "https://management.azure.com/"

# Also get a Key Vault access token for the MSI
$VaultToken = Get-AccessToken -Resource "https://vault.azure.net/"

# Add-AzureRmAccount -AccessToken $ArmToken -AccountId $SubscriptionId
# Get-AzureRmContext

### Get an SAS credential
# https://docs.microsoft.com/en-us/azure/active-directory/msi-tutorial-windows-vm-access-storage-sas
# Expire this credential in 10 minutes
$expiry = (Get-Date).AddMinutes(10).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$params = @{
    canonicalizedResource="/blob/${ArtefactStorageAccount}/${ArtefactContainer}";
    signedResource="c"; signedPermission="r"; signedProtocol="https";
    signedExpiry=${expiry};
}
$jsonParams = $params | ConvertTo-Json
$headers = @{Authorization="Bearer $ArmToken"}

# Now get the SAS Token
$URL = "https://management.azure.com/subscriptions/${SubscriptionId}/resourceGroups/${ResourceGroup}/providers/Microsoft.Storage/storageAccounts/${ArtefactStorageAccount}/listServiceSas/?api-version=2017-06-01"
$sasResponse = Invoke-WebRequest -Verbose `
    -UseBasicParsing `
    -Uri $URL `
    -Method POST `
    -Headers $headers `
    -Body $jsonParams

# Extract the token string
$sasToken = ($sasResponse.Content | ConvertFrom-Json).serviceSasToken

# Set up a Storage Context
$saContext = New-AzureStorageContext -Verbose `
    -StorageAccountName $ArtefactStorageAccount `
    -SasToken $sasToken
    
# Get our metadata
$LocalMetadata = "environments\$($ApplicationId)"
Get-AzureStorageBlobContent -Verbose `
    -Force `
    -Context $saContext `
    -Blob "environments/$Environment/$ApplicationId" `
    -Container $ArtefactContainer `
    -Destination $LocalMetadata

if ($ArtefactVersion -eq "latest") {
    $ArtefactVersion = (Get-Content $LocalMetadata -Raw).trim()
    Write-Host "Using latest version from environment metadata"
}

Write-Host "$($ApplicationId) version: $($ArtefactVersion)"

# Get our artefact
$LocalArtefact = "artefacts\$($ApplicationId).zip"
Get-AzureStorageBlobContent -Verbose `
    -Force `
    -Context $saContext `
    -Blob "apps/$ApplicationId/$ArtefactVersion/$ArtefactName" `
    -Container $ArtefactContainer `
    -Destination $LocalArtefact
    

# Get Environment-specific settings
# Get Environment-specific secrets
# @TODO Fetch things from Key Vault

# function Get-VaultKeys
# (
#   [string]$accessToken,
#   [string]$vaultName
# )
# {
#   $headers = @{ 'Authorization' = "Bearer $accessToken" }
#   $queryUrl = "https://$vaultName.vault.azure.net/keys" + '?api-version=2016-10-01'

#   $keyResponse = Invoke-RestMethod -Verbose -Method GET -Uri $queryUrl -Headers $headers

#   return $keyResponse.value
# }

# Invoke-WebRequest -Verbose -Debug `
#     -Uri https://iskdemo01-kv2.vault.azure.net/keys?api-version=2016-10-01 `
#     -Method GET `
#     -Headers @{Authorization="Bearer $VaultToken"}

# Get-Keys -accessToken $VaultToken -vaultName iskdemo01-kv


## Use msdeploy.exe to deploy the web package
$DeployDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$InstallPath = "C:\Program Files (x86)\IIS\Microsoft Web Deploy V3"

$msdeploy = Join-Path $InstallPath "msdeploy.exe"
$arguments = [string[]]@(
        "-verb:sync",
        "-source:package='$($LocalArtefact)'",
        "-dest:auto",
        # We use a bunch of 'setParam' arguments here, but could also use a parameters XML file instead.
        "-setParam:name='IIS Web Application Name',value='$($WebSiteName)'",
        "-setparam:name='Environment',value='$($Environment)'",
        "-setparam:name='DeployNumber',value='$($DeployNumber)'",
        "-setparam:name='DeployDate',value='$($DeployDate)'",
        "-setparam:name='DeployUrl',value='$($DeployUrl)'",
        "-allowUntrusted")
    
$job = Start-Process $msdeploy -Verbose -ArgumentList $arguments -NoNewWindow -Wait -PassThru
if ($job.ExitCode -ne 0) {
    echo $job.StandardOutput
    echo $job.StandardError
    throw('msdeploy exited with an error. ExitCode:' + $job.ExitCode)
}

Pop-Location
Stop-Transcript