#
# Install the VSTS Agent
# @TODO Make idempotent
# HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\TeamFoundationServer\15.0\VstsAgents
# Context: Runs on a target Virtual Machine 
#
[CmdletBinding()]
param(
    # If Dry Run, we don't actually do anything
    [ValidateSet('Yes','No')]
    [string] $DryRun = "No",

    # Working directory
    [string] $Dir = "C:\cloud-automation",

    # VSTS Account Name
    [string] $VstsAccountName = "devops-ps-uk-02",

    # VSTS Team Project
    [string] $VstsTeamProject = "MyFirstProject",
    
    # VSTS Deployment Group
    [string] $VstsDeploymentGroup = "Test01",
    
    # VSTS Personal Access Token
    [string] $VstsPat
)

$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

Start-Transcript -Path $Dir\logs\Register-VstsAgent.log

$Provisioning = ((Get-Content $Dir\provisioning.json) -join "`n" | ConvertFrom-Json)

if ($DryRun -eq "Yes") {
    Write-Host "`n----> Dry Run, skipping all activities."
    Stop-Transcript
    exit(0)
}


$Installed = (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\TeamFoundationServer\15.0\VstsAgents" -ErrorAction SilentlyContinue)
if ($Installed) {
    Write-Host "`n----> VSTS Agent already installed"
    Stop-Transcript
    exit(0)
}

## Copied from the VSTS Web UI
# Tidied up and parameters replaced with variables!
If (-not (Test-Path $env:SystemDrive\'vstsagent')) {
    mkdir $env:SystemDrive\'vstsagent'
}
cd $env:SystemDrive\'vstsagent'; 
for($i=1; $i -lt 100; $i++) {
    $destFolder = "A"+$i.ToString();
    if (-NOT (Test-Path ($destFolder))) {
        mkdir $destFolder;
        cd $destFolder
        break
    }
}

$agentZip = "$PWD\agent.zip"
$DefaultProxy = [System.Net.WebRequest]::DefaultWebProxy; 

$WebClient = New-Object Net.WebClient
$Uri ='https://vstsagentpackage.azureedge.net/agent/2.129.1/vsts-agent-win-x64-2.129.1.zip';

if ($DefaultProxy -and (-not $DefaultProxy.IsBypassed($Uri))) {
    $WebClient.Proxy = New-Object Net.WebProxy($DefaultProxy.GetProxy($Uri).OriginalString, $True)
}
$WebClient.DownloadFile($Uri, $agentZip)
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($agentZip, "$PWD");

.\config.cmd --unattended --replace `
    --deploymentgroup --deploymentgroupname "$($Provisioning.VstsDeploymentGroup)" `
    --agent $env:COMPUTERNAME --runasservice `
    --work '_work' `
    --url "https://$($Provisioning.VstsAccountName).visualstudio.com/" `
    --projectname $($Provisioning.VstsTeamProject) `
    --auth PAT --token $VstsPat
    
Remove-Item $agentZip

Stop-Transcript