
#
# Because VM Extensions can't be sequenced effectively, we use this script to coordinate multiple provisioning steps, e.g.:
# * Configuration (OS, IIS, Agents)
# * Application Deployment
#
#
# This script accepts a large amount of parameters as passed in by the VM Custom Script Extension.
# Parameters here need to match those in the ARM template invocation of this script.
#
[CmdletBinding()]
param(

    # Working directory
    [string] $Dir = "C:\cloud-automation",

    # Name of the current Environment
    [string] $Environment = "SIT",

    # Namespace for this VM
    [string] $Namespace = "dx-01",
    
    # Name of the Artefact Subscription ID.
    # Defaults to current Subscription
    [string] $ArtefactSubscriptionId,   

    # Name of the Artefact Resource Group
    [string] $ArtefactResourceGroup = "iskdemo01-rg",

    # Name of the Artefact Storage Account
    [string] $ArtefactStorageAccount = "iskdemo01sa",

    # Name of the Artefact Blob Container
    [string] $ArtefactContainer = "artefacts",

    # VSTS Account Name
    [string] $VstsAccountName = "devops-ps-uk-02",

    # VSTS Team Project
    [string] $VstsTeamProject = "MyFirstProject",
    
    # VSTS Deployment Group
    [string] $VstsDeploymentGroup = "dg-01",
    
    # VSTS Personal Access Token
    # Not used!
    [string] $VstsPat,

    # Name of the Key Vault
    [string] $KeyVault = "iskdemo01-kv",

    # Application IDs to install automatically
    [string[]] $ApplicationIds = @("WebApplication1"),

    # If Dry Run, we don't actually do anything
    [ValidateSet('Yes','No')]
    [string] $DryRun = "No"
)

$VerbosePreference = "Continue"

New-Item -Path $Dir\logs -ItemType Directory -ErrorAction SilentlyContinue
# Start-Transcript -Path $Dir\logs\Provision-VM.log -Append
Push-Location -Path $Dir

# Get data from Instance metadata
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/instance-metadata-service
$Metadata = $(Invoke-RestMethod `
    -UseBasicParsing `
    -URI http://169.254.169.254/metadata/instance?api-version=2017-08-01 `
    -Headers @{"Metadata"="true"} `
    -Method GET)

# Create an object with our create-time Environment-specific configuration
Write-Verbose "`n----> Environment Config vars:"
$ArtefactSubscriptionId = if ($ArtefactSubscriptionId) { $ArtefactSubscriptionId } else { $Metadata.compute.subscriptionId }
$Provisioning = @{
    "Environment" = $Environment
    "Namespace" = $Namespace
    "ArtefactSubscriptionId" = $ArtefactSubscriptionId
    "ArtefactResourceGroup" = $ArtefactResourceGroup
    "ArtefactStorageAccount" = $ArtefactStorageAccount
    "ArtefactContainer" = $ArtefactContainer
    "KeyVault" = $KeyVault
    # VSTS Settings
    "VstsAccountName" = $VstsAccountName
    "VstsTeamProject" = $VstsTeamProject
    "VstsDeploymentGroup" = $VstsDeploymentGroup
    # Application List
    "ApplicationIds" = $ApplicationIds
    # Add Instance Metadata
    "VmName" = $Metadata.compute.name
    "SubscriptionId" = $Metadata.compute.subscriptionId
    "ResourceGroup" = $Metadata.compute.resourceGroupName
    "Location" = $Metadata.compute.location
}
ConvertTo-Json -InputObject $Provisioning | Tee $Dir\Provisioning.json


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

# Wait for MSI Extension to complete
# Get a token for ARM
$retry = 0; $maxRetries = 10; $retryDelay = 30

# Retry till we can get a token, this is only needed until we can sequence extensions in VMSS
$success = $false
while(!$success) {
    try {
        $retry += 1
        Write-Host "`n----> Getting ARM Token, attempt #$retry"
        # On the VM, get a ARM access token for the MSI
        $ArmToken = Get-AccessToken -Resource "https://management.azure.com/"        
        # Also get a Key Vault access token for the MSI
        # $VaultToken = Get-AccessToken -Resource "https://vault.azure.net/"
        $success = $true
        Write-Host -BackgroundColor DarkGreen "==> Got ARM token"
    } catch {
        Write-Error "==> Exception $_ trying to get ARM Token"
        if ($retry -gt $maxRetries) { throw $_ }
        Write-Host "==> Sleeping for $retryDelay seconds..."
        Start-Sleep $retryDelay
    }
}

# Check for Subscription ID linked to this MSI
$retry = 0; $maxRetries = 10; $retryDelay = 30
$success = $false
while(!$success) {
    try {
        $retry += 1
        Write-Host "`n----> Checking for Subscription ID, attempt #$retry"  
        $loginResult = Login-AzureRmAccount -Verbose `
             -AccessToken $ArmToken `
             -AccountId $Provisioning.SubscriptionId
        if ($loginResult.Context.Subscription.Id -ne $Provisioning.SubscriptionId) {
            throw "Subscription Id $($Provisioning.SubscriptionId) not in context" 
        }
        $success = $true
        Write-Host -BackgroundColor DarkGreen "==> Found Subscription ID $($Provisioning.SubscriptionId)"
    } catch {
        Write-Error "==> Exception $_ trying to Login"
        if ($retry -gt $maxRetries) { throw $_ }
        Write-Host "==> Sleeping for $retryDelay seconds..."
        Start-Sleep $retryDelay
    }
}

 Write-Host "`n----> Running Configure-Server"
.\Configure-Server.ps1 `
    -DryRun $DryRun `
    -Dir $Dir 

Write-Host "`n----> Running Deploy-App"
foreach($ApplicationId in $ApplicationIds) {
    Write-Host "==> $ApplicationId"
    .\Deploy-App.ps1 `
        -DryRun $DryRun `
        -Dir $Dir `
        -DeployNumber "Release-Local" `
        -DeployUrl "http://localhost" `
        -ApplicationId $ApplicationId `
        -ArtefactName "$ApplicationId.zip"
}