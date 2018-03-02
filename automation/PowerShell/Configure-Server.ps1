
[CmdletBinding()]
param(
    [string] $Dir = "C:\cloud-automation"
)

New-Item -Path $Dir\logs -ItemType Directory -ErrorAction SilentlyContinue
Start-Transcript -Path $Dir\logs\Configure-Server.log -Append
Push-Location -Path $Dir

# Get info about host
# @see https://docs.microsoft.com/en-us/powershell/scripting/getting-started/cookbooks/collecting-information-about-computers?view=powershell-6
Get-WmiObject -Class Win32_ComputerSystem
Get-WmiObject -Class Win32_BIOS -ComputerName .
Get-CimInstance Win32_OperatingSystem | FL *
Get-WmiObject -Class Win32_Processor -ComputerName . | Select-Object -Property [a-z]*

# Install PS modules.
# Note that there are some hoops to jump through before this (e.g. Allowing access to PowerShell Gallery repo)
Install-PackageProvider -Name NuGet -Force
# Let's trust the PSGallery source
Set-PackageSource -Trusted -Name PSGallery -ProviderName PowerShellGet
Set-PSRepository -InstallationPolicy Trusted -name PSGallery

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
Invoke-WebPI /Install /Products:HTTPErrors /AcceptEula
Invoke-WebPI /Install /Products:WDeploy36PS /AcceptEula

Pop-Location
Stop-Transcript