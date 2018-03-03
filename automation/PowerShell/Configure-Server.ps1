
[CmdletBinding()]
param(
    # Working directory
    [string] $Dir = "C:\cloud-automation",

    # If Dry Run, we don't actually do anything
    [string] $DryRun = "No"
)

$VerbosePreference = "Continue"

New-Item -Path $Dir\logs -ItemType Directory -ErrorAction SilentlyContinue
Start-Transcript -Path $Dir\logs\Configure-Server.log -Append
Push-Location -Path $Dir

# Load our provisioning data
$Provisioning = ((Get-Content $Dir\provisioning.json) -join "`n" | ConvertFrom-Json)

if ($DryRun -eq "Yes") {
    Write-Host "`n[$(Get-Date)] ----> Dry Run, skipping all activities."
    Pop-Location
    Stop-Transcript
    exit(0)
}

# Get info about host
# @see https://docs.microsoft.com/en-us/powershell/scripting/getting-started/cookbooks/collecting-information-about-computers?view=powershell-6configuration
Write-Host "`n[$(Get-Date)] ----> Lots of System Info:"
Get-WmiObject -Class Win32_ComputerSystem
Get-WmiObject -Class Win32_BIOS -ComputerName .
Get-CimInstance Win32_OperatingSystem | FL *
Get-WmiObject -Class Win32_Processor -ComputerName . | Select-Object -Property [a-z]*

# Set up PS packages sources and repositories
if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue -ListAvailable)) 
{
    Write-Host "`n[$(Get-Date)] ----> Installing Package Provider nuget"
    Install-PackageProvider -Name nuget -Force
}

# Let's trust the PSGallery source
# WARNING: This may be a security issue, please don't continue blindly using this.
Write-Host "`n[$(Get-Date)] ----> Setting up policies for PowerShellGallery sources"
Set-PackageSource -Trusted -Name PSGallery -ProviderName PowerShellGet
Set-PSRepository -InstallationPolicy Trusted -name PSGallery

# Install PS modules.
$modules = @(
    'AzureRM.Compute'
    # 'AzureRM.KeyVault'
    'AzureRM.Profile'
    'Azure.Storage'    
    # 'WebPI.PS' 
    # NOTE: WebPI.PS is a community module and will need to be either
    # vetted & forked or replaced with something else (like a direct install from .MSI)
    # @TODO Kill WebPI and use a direct Web Deploy installation method. WebPI is slow.
    # @see https://www.iis.net/downloads/microsoft/web-deploy#additionalDownloads
)
Write-Host "`n[$(Get-Date)] ----> Installing PowerShell Modules"
foreach($module in $modules) 
{
    if (Get-Module -Name $module -ListAvailable) { continue  }
    Write-Host "`n[$(Get-Date)] ==> $module "
    Install-Module $module
    # Import Modules (useful when running in the ISE)
    # Import-Module -Name $module
}

Write-Host "`n[$(Get-Date)] ----> Un-Trusting PowerShellGallery Modules"
Set-PSRepository -InstallationPolicy Untrusted -name PSGallery

# Let's install some bare-minimum Windows Features
$features = @(
    'Web-Server'
    #'Web-Asp-Net' # Needed by WebPI
    'Web-Asp-Net45'
    'Web-Mgmt-Service'
    'Web-Mgmt-Console'
)
Write-Host "`n[$(Get-Date)] ----> Installing Windows Features"
foreach($feature in $features) 
{
    if ((Get-WindowsFeature $feature).Installed) { continue }
    Write-Host "`n[$(Get-Date)] ==> $feature"
    Install-WindowsFeature $feature
}

# Install Web Platform Installer packages
# THIS DOESN'T WORK AS A SYSTEM USER. Replace with direct download&install or DSC fragment
# $packages = @(
#     'UrlRewrite2'
#     'WDeploy36PS'
# )
# Write-Host "`n----> Installing Web Platform Installer packages"
# foreach($package in $packages) 
# {
#     Write-Host "`n==> $package"
#     Invoke-WebPI /Install /Products:$package /AcceptEula
# }

# Write-Host "`n----> All installed Web Platform Installer packages:"
# Invoke-WebPI /List /ListOption:Installed

$Installed = (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy" -ErrorAction SilentlyContinue)
if (-not $Installed) {
    Write-Host "`n[$(Get-Date)] ----> Downloading WebDeploy installer [$(Get-Date)]"
    curl -UseBasicParsing -Verbose `
        -OutFile artefacts/webdeploy.msi `
        http://download.microsoft.com/download/0/1/D/01DC28EA-638C-4A22-A57B-4CEF97755C6C/WebDeploy_amd64_en-US.msi
    Write-Host "`n[$(Get-Date)] ----> Installing WebDeploy"
    msiexec /L logs/msdeployinstall.log  /q /norestart /I artefacts/webdeploy.msi
}

Write-Host "`n`n[$(Get-Date)] ---->All Done!"

Pop-Location
Stop-Transcript