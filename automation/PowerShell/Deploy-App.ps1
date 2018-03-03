

# Context: Runs on a target Virtual Machine

[CmdletBinding()]
param(
    # If Dry Run, we don't actually do anything
    [ValidateSet('Yes','No')]
    [string] $DryRun = "No",

    # Working directory
    [string] $Dir = "C:\cloud-automation",
    
    # Application ID
    [string] $ApplicationId = "WebApplication1",

    # IIS Web Site Name
    [string] $WebSiteName = "Default Web Site",

    # Version string for the artefact (the Blob prefix)
    [string] $ArtefactVersion = "latest",

    # Path to artefact in Blob Storage
    [string] $ArtefactName = "WebApplication1.zip",

    # Deployment ID or number
    [string] $DeployNumber = "Release-Local",
    
    # Deployment URL
    [string] $DeployUrl = "http://local-deployment"
)

New-Item -Path $Dir\logs -ItemType Directory -ErrorAction SilentlyContinue
Start-Transcript -Path $Dir\logs\Deploy-Web.log -Append

# Load our provisioning data
$Provisioning = ((Get-Content $Dir\provisioning.json) -join "`n" | ConvertFrom-Json)

if ($DryRun -eq "Yes") {
    Write-Host "`n----> Dry Run, skipping all activities."
    Pop-Location
    Stop-Transcript
    exit(0)
}

Push-Location -Path $Dir

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
Write-Host "`n----> Getting ARM Token"
$ArmToken = Get-AccessToken -Resource "https://management.azure.com/"

# Also get a Key Vault access token for the MSI
Write-Host "`n----> Getting Key Vault Token"
$VaultToken = Get-AccessToken -Resource "https://vault.azure.net/"

# Add-AzureRmAccount -AccessToken $ArmToken -AccountId $SubscriptionId
# Get-AzureRmContext

### Get an SAS credential
# https://docs.microsoft.com/en-us/azure/active-directory/msi-tutorial-windows-vm-access-storage-sas
# Getting the SAS Token via PowerShell leaves us with a chicken-and-egg problem; 
#  - we can't get a SAS token without a Storage Context, and we can't get a Context without some Token
# Expire this credential in 10 minutes
Write-Host "`n----> Getting SAS Token"
$expiry = (Get-Date).AddMinutes(10).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
Write-Host "  ==> Expiry: $expiry"
$params = @{
    canonicalizedResource="/blob/$($Provisioning.ArtefactStorageAccount)/$($Provisioning.ArtefactContainer)";
    signedResource="c"; signedPermission="rl"; signedProtocol="https";
    signedExpiry=${expiry};
}
$jsonParams = $params | ConvertTo-Json

# Now get the SAS Token
$URL = "https://management.azure.com/subscriptions/$($Provisioning.ArtefactSubscriptionId)/resourceGroups/$($Provisioning.ArtefactResourceGroup)/providers/Microsoft.Storage/storageAccounts/$($Provisioning.ArtefactStorageAccount)/listServiceSas/?api-version=2017-06-01"
$sasResponse = Invoke-WebRequest -Verbose `
    -UseBasicParsing `
    -Uri $URL `
    -Method POST `
    -Headers @{Authorization="Bearer $ArmToken"} `
    -Body $jsonParams

# Extract the token string
$sasToken = ($sasResponse.Content | ConvertFrom-Json).serviceSasToken

# Set up a Storage Context
$saContext = New-AzureStorageContext -Verbose `
    -StorageAccountName $($Provisioning.ArtefactStorageAccount) `
    -SasToken $sasToken


function DeployApplication([string] $ApplicationId) 
{
    Write-Host "`n----> Deploying $($ApplicationId)"

    # Get our metadata
    $LocalMetadata = "environments\$($ApplicationId)"
    Get-AzureStorageBlobContent -Verbose `
        -Force `
        -Context $saContext `
        -Blob "environments/$($Provisioning.Environment)/$($ApplicationId)" `
        -Container $($Provisioning.ArtefactContainer) `
        -Destination $LocalMetadata

    if ($ArtefactVersion -eq "latest") {
        $ArtefactVersion = (Get-Content $LocalMetadata -Raw).trim()
        Write-Host "  ==> Using latest version from environment metadata"
    }

    Write-Host "  ==> $($ApplicationId) version: $($ArtefactVersion)"
    $ArtefactName = "$($ApplicationId).zip"

    # Get our artefact
    $LocalArtefact = "artefacts\$($ApplicationId).zip"
    Get-AzureStorageBlobContent -Verbose `
        -Force `
        -Context $saContext `
        -Blob "apps/$ApplicationId/$ArtefactVersion/$ArtefactName" `
        -Container $($Provisioning.ArtefactContainer) `
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
    $MSDeployPath = (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy" | Select -Last 1).GetValue("InstallPath")

    $msdeploy = Join-Path $MSDeployPath "msdeploy.exe"
    $arguments = [string[]]@(
            "-verb:sync",
            "-source:package='$($LocalArtefact)'",
            "-dest:auto",
            # We use a bunch of 'setParam' arguments here, but could also use a parameters XML file instead.
            "-setParam:name='IIS Web Application Name',value='$($WebSiteName)'",
            "-setparam:name='Environment',value='$($Provisioning.Environment)'",
            "-setparam:name='DeployNumber',value='$($DeployNumber)'",
            "-setparam:name='DeployDate',value='$($DeployDate)'",
            "-setparam:name='DeployUrl',value='$($DeployUrl)'",
            "-allowUntrusted")
        
    Write-Host "`n----> Arguments for msdeploy.exe"
    $arguments
    
    Write-Host "`n----> Running $($msdeploy)"
    $job = Start-Process $msdeploy -Verbose -ArgumentList $arguments -NoNewWindow -Wait -PassThru
    if ($job.ExitCode -ne 0) {
        Write-Host "`nstdout"
        Write-Host $job.StandardOutput
        Write-Host "`nstderr"
        Write-Host $job.StandardError
        throw('msdeploy exited with an error. ExitCode:' + $job.ExitCode)
    }
    Write-Host "`n----> Done deploying $($ApplicationId)"
}


DeployApplication($ApplicationId)

Pop-Location
Stop-Transcript