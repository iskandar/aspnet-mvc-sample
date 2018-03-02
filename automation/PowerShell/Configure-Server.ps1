
[CmdletBinding()]
param(
    # Name of the current VM or VMSS
    [string] $VmName,

    # Working directory
    [string] $Dir = "C:\cloud-automation",

    # Name of the current Environment
    [string] $Environment = "SIT",

    # Name of the Artefact Storage Account
    [Parameter(Mandatory=$True)]
    [string] $ArtefactStorageAccount,

    # Name of the Artefact Blob Container
    [string] $ArtefactContainer = "artefacts",

    # VSTS Account Name
    [Parameter(Mandatory=$True)]
    [string] $VSTSAccountName,

    # VSTS Team Project
    [string] $TeamProject = "MyFirstProject",
    
    # VSTS Deployment Group
    [string] $DeploymentGroup = "dg-01"
)

New-Item -Path $Dir\logs -ItemType Directory -ErrorAction SilentlyContinue
Start-Transcript -Path $Dir\logs\Configure-Server.log -Append
Push-Location -Path $Dir

# Get data from Instance metadata
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/instance-metadata-service
$Metadata = $(Invoke-RestMethod `
    -UseBasicParsing `
    -URI http://169.254.169.254/metadata/instance?api-version=2017-08-01 `
    -Headers @{"Metadata"="true"} `
    -Method get)

# Create an object with our create-time Environment-specific configuration
$Config = @{
    "VmName" = $VmName
    "Environment" = $Environment
    "ArtefactStorageAccount" = $ArtefactStorageAccount
    "ArtefactContainer" = $ArtefactContainer
    "VstsAccountName" = $VSTSAccountName
    "TeamProject" = $TeamProject
    "DeploymentGroup" = $DeploymentGroup
    # Add Instance Metadata
    "SubscriptionId" = $Metadata.compute.subscriptionId
    "ResourceGroup" = $Metadata.compute.resourceGroupName
}
ConvertTo-Json -InputObject $Config > $Dir\Config.json

# Get info about host
# @see https://docs.microsoft.com/en-us/powershell/scripting/getting-started/cookbooks/collecting-information-about-computers?view=powershell-6
Get-WmiObject -Class Win32_ComputerSystem
Get-WmiObject -Class Win32_BIOS -ComputerName .
Get-CimInstance Win32_OperatingSystem | FL *
Get-WmiObject -Class Win32_Processor -ComputerName . | Select-Object -Property [a-z]*

# Set up PS packages sources and repositories
Install-PackageProvider -Name NuGet -Force
# Let's trust the PSGallery source
Set-PackageSource -Trusted -Name PSGallery -ProviderName PowerShellGet
Set-PSRepository -InstallationPolicy Trusted -name PSGallery

# Install PS modules.
Install-Module -Name PowerShellGet -Force
Install-Module -Name AzureRM -AllowClobber
Install-Module -Name Azure.Storage
Install-Module -Name WebPI.PS

# Import Modules (useful when running in the ISE)
Import-Module -Name AzureRM 
Import-Module -Name Azure.Storage
Import-Module -Name WebPI.PS

# Let's install some bare-minimum Windows Features
Install-WindowsFeature Web-Server 
Install-WindowsFeature Web-Asp-Net45
Install-WindowsFeature Web-Mgmt-Service
Install-WindowsFeature Web-Mgmt-Console

# Install Web Platform Installer packages
Invoke-WebPI /Install /Products:UrlRewrite2 /AcceptEula
Invoke-WebPI /Install /Products:WDeploy36PS /AcceptEula

Pop-Location
Stop-Transcript