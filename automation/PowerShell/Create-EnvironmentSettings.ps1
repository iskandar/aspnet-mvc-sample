# This is intended to run in the context of a VSTS Release Step, but
# we also want to be able to run this standalone for testing and portability.
# By 'portability', we mean this code should run successfully in Jenkins with minor modifications.

# Capture relevant values, checking for VSTS-formatted names.
$Environment = "x"
$ArtefactStorageAccount = ""
$ArtefactContainer = ""
$VSTSAccountName = ""
$TeamProject = ""
$DeploymentGroup = ""
$BuildNumber = $(Build.BuildNumber) ?? 'unknown'
$BuildId = $(Build.BuildId) ?? 'unknown'

$WorkingDir = $(System.ArtifactsDirectory)

# Create a file to live in ENVIRONMENT/APPLICATION_ID
# Content of the file is ONLY the build number
# This represents the most-recently deployed build for this application in this environment
Push-Location $(WorkingDir)
New-Item -Path metadata -ItemType Directory

# Create an object with our deploy-time Environment-specific configuration
$Config = @{
    "Environment" = $Environment
    "ArtefactStorageAccount" = $ArtefactStorageAccount
    "ArtefactContainer" = $ArtefactContainer
    "VstsAccountName" = $VSTSAccountName
    "TeamProject" = $TeamProject
    "DeploymentGroup" = $DeploymentGroup
    "BuildNumber" = $BuildNumber
    "BuildId" = $BuildId
}
ConvertTo-Json -InputObject $Config > metadata\$(ApplicationId).json

# Upload this to Blob Storage
# az storage blob upload --container-name artefacts --file $(ApplicationId) --name $(Release.EnvironmentName)/$(ApplicationID)