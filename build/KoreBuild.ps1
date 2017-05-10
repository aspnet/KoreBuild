#requires -version 4

param([parameter(ValueFromRemainingArguments=$true)][string[]] $allparams)

function __exec($cmd) {
    $cmdName = [IO.Path]::GetFileName($cmd)
    Write-Host -ForegroundColor Cyan "> $cmdName $args"
    & $cmd @args
    $exitCode = $LASTEXITCODE
    if($exitCode -ne 0) {
        throw "'$cmdName $args' failed with exit code: $exitCode"
    }
}

$repoFolder = $env:REPO_FOLDER
if (!$repoFolder) {
    throw "REPO_FOLDER is not set"
}

Write-Host "Building $repoFolder"
cd $repoFolder

$dotnetArch = 'x64'
$dotnetVersionFile = $PSScriptRoot + "\cli.version"
$dotnetChannel = "preview"
$dotnetVersion = Get-Content $dotnetVersionFile
$sharedRuntimeVersionFile = $PSScriptRoot + "\shared-runtime.version"
$sharedRuntimeChannel = "master"
$sharedRuntimeVersion = Get-Content $sharedRuntimeVersionFile

if ($env:KOREBUILD_DOTNET_CHANNEL)
{
    $dotnetChannel = $env:KOREBUILD_DOTNET_CHANNEL
}
if ($env:KOREBUILD_DOTNET_VERSION)
{
    $dotnetVersion = $env:KOREBUILD_DOTNET_VERSION
}
if ($env:KOREBUILD_DOTNET_SHARED_RUNTIME_CHANNEL)
{
    $sharedRuntimeChannel = $env:KOREBUILD_DOTNET_SHARED_RUNTIME_CHANNEL
}
if ($env:KOREBUILD_DOTNET_SHARED_RUNTIME_VERSION)
{
    $sharedRuntimeVersion = $env:KOREBUILD_DOTNET_SHARED_RUNTIME_VERSION
}

$dotnetLocalInstallFolder = $env:DOTNET_INSTALL_DIR
if (!$dotnetLocalInstallFolder)
{
    $dotnetLocalInstallFolder = "$env:USERPROFILE\.dotnet\$dotnetArch\"
}

function InstallSharedRuntime([string] $version, [string] $channel)
{
    $sharedRuntimePath = [IO.Path]::Combine($dotnetLocalInstallFolder, 'shared', 'Microsoft.NETCore.App', $version)
    # Avoid redownloading the CLI if it's already installed.
    if (!(Test-Path $sharedRuntimePath))
    {
        & "$PSScriptRoot\dotnet\dotnet-install.ps1" -Channel $channel `
            -SharedRuntime `
            -Version $version `
            -Architecture $dotnetArch `
            -InstallDir $dotnetLocalInstallFolder
    }
}

$newPath = "$dotnetLocalInstallFolder;$env:PATH"
if ($env:KOREBUILD_SKIP_RUNTIME_INSTALL -eq "1")
{
    Write-Host "Skipping runtime installation because KOREBUILD_SKIP_RUNTIME_INSTALL = 1"
    # Add to the _end_ of the path in case preferred .NET CLI is not in the default location.
    $newPath = "$env:PATH;$dotnetLocalInstallFolder"
}
else
{
    # Temporarily install these runtimes to prevent build breaks for repos not yet converted
    # 1.0.4 - for tools
    InstallSharedRuntime -version "1.0.4" -channel "preview"
    # 1.1.1 - for test projects which haven't yet been converted to netcoreapp2.0
    InstallSharedRuntime -version "1.1.1" -channel "release/1.1.0"

    if ($sharedRuntimeVersion)
    {
        InstallSharedRuntime -version $sharedRuntimeVersion -channel $sharedRuntimeChannel
    }

    # Install the version of dotnet-cli used to compile
    & "$PSScriptRoot\dotnet\dotnet-install.ps1" -Channel $dotnetChannel `
        -Version $dotnetVersion `
        -Architecture $dotnetArch `
        -InstallDir $dotnetLocalInstallFolder
}

if (!($env:Path.Split(';') -icontains $dotnetLocalInstallFolder))
{
    Write-Host "Adding $dotnetLocalInstallFolder to PATH"
    $env:Path = "$newPath"
}

$makeFileProj = "$PSScriptRoot/KoreBuild.proj"
$msbuildArtifactsDir = "$repoFolder/artifacts/msbuild"
$msbuildLogFilePath = "$msbuildArtifactsDir/msbuild.log"
$msBuildResponseFile = "$msbuildArtifactsDir/msbuild.rsp"


$msBuildArguments = @"
/nologo
/m
/p:RepositoryRoot="$repoFolder/"
/fl
/flp:LogFile="$msbuildLogFilePath";Verbosity=detailed;Encoding=UTF-8
/clp:Summary
"$makeFileProj"
"@

$allparams | ForEach-Object { $msBuildArguments += "`n`"$_`"" }

if (!(Test-Path $msbuildArtifactsDir))
{
    mkdir $msbuildArtifactsDir | Out-Null
}

$msBuildArguments | Out-File -Encoding ASCII -FilePath $msBuildResponseFile

__exec dotnet restore /p:PreflightRestore=true "$makeFileProj"
__exec dotnet msbuild `@"$msBuildResponseFile"
