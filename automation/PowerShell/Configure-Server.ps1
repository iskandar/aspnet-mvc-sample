
[CmdletBinding()]
param(
    # Name of the current VM or VMSS
    [string] $VmName,

    # Namespace for this VM
    [Parameter(Mandatory=$True)]
    [string] $Namespace,

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
    [string] $VstsAccountName,

    # VSTS Team Project
    [string] $TeamProject = "MyFirstProject",
    
    # VSTS Deployment Group
    [string] $DeploymentGroup = "dg-01"
)

$VerbosePreference = "Continue"

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
Write-Verbose "----> Environment Config vars:"
$Config = @{
    "VmName" = $VmName
    "Namespace" = $Namespace
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
ConvertTo-Json -InputObject $Config | Tee $Dir\Config.json

# Get info about host
# @see https://docs.microsoft.com/en-us/powershell/scripting/getting-started/cookbooks/collecting-information-about-computers?view=powershell-6configuration
Write-Verbose "----> Lots of System Info:"
Get-WmiObject -Class Win32_ComputerSystem
Get-WmiObject -Class Win32_BIOS -ComputerName .
Get-CimInstance Win32_OperatingSystem | FL *
Get-WmiObject -Class Win32_Processor -ComputerName . | Select-Object -Property [a-z]*

# Set up PS packages sources and repositories
if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue -ListAvailable)) 
{
    Write-Verbose "----> Installing Package Provider nuget"
    Install-PackageProvider -Name nuget -Force
}
# Let's trust the PSGallery source
Write-Verbose "----> Setting up policies for PowerShellGallery source"
Set-PackageSource -Trusted -Name PSGallery -ProviderName PowerShellGet
Set-PSRepository -InstallationPolicy Trusted -name PSGallery

# Install PS modules.
$modules = @(
    'AzureRM'
    'WebPI.PS'
    'Azure.Storage'
)
Write-Verbose "----> Installing PowerShell Modules"
foreach($module in $modules) 
{
    if (!(Get-Module -Name $module -ListAvailable) )
    {
        Write-Verbose "==> $module"
        Install-Module $module -Force
        # Import Modules (useful when running in the ISE)
        # Import-Module -Name $module
    } 
}

# Let's install some bare-minimum Windows Features
$features = @(
    'Web-Server'
    'Web-Asp-Net45'
    'Web-Mgmt-Service'
    'Web-Mgmt-Console'
)
Write-Verbose "----> Installing Windows Features"
foreach($feature in $features) 
{
    Write-Verbose "==> $feature"
    Install-WindowsFeature $feature
}

# Install Web Platform Installer packages
$packages = @(
    'UrlRewrite2'
    'WDeploy36PS'
)
Write-Verbose "----> Installing Web Platform Installer packages"
foreach($package in $packages) 
{
    Write-Verbose "==> $package"
    Invoke-WebPI /Install /Products:$package /AcceptEula
}

Write-Verbose "All Done!"

Pop-Location
Stop-Transcript