#requires -version 4

param([parameter(ValueFromRemainingArguments=$true)][string[]] $allparams)

function exec($cmd) {
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

# Make the path relative to the repo root because Sake/Spark doesn't support full paths
$koreBuildFolder = $PSScriptRoot
$koreBuildFolder = $koreBuildFolder.Replace($repoFolder, "").TrimStart("\")

$dotnetVersionFile = $koreBuildFolder + "\cli.version"
$dotnetChannel = "rel-1.0.0"
$dotnetVersion = Get-Content $dotnetVersionFile
$sharedRuntimeVersion = Get-Content (Join-Path $koreBuildFolder 'shared-runtime.version')

if ($env:KOREBUILD_DOTNET_CHANNEL)
{
    $dotnetChannel = $env:KOREBUILD_DOTNET_CHANNEL
}
if ($env:KOREBUILD_DOTNET_VERSION)
{
    $dotnetVersion = $env:KOREBUILD_DOTNET_VERSION
}

$dotnetLocalInstallFolder = $env:DOTNET_INSTALL_DIR
if (!$dotnetLocalInstallFolder)
{
    $dotnetLocalInstallFolder = "$env:LOCALAPPDATA\Microsoft\dotnet\"
}

function InstallSharedRuntime([string] $version, [string] $channel)
{
    $sharedRuntimePath = [IO.Path]::Combine($dotnetLocalInstallFolder, 'shared', 'Microsoft.NETCore.App', $version)
    # Avoid redownloading the CLI if it's already installed.
    if (!(Test-Path $sharedRuntimePath))
    {
        & "$koreBuildFolder\dotnet\dotnet-install.ps1" -Channel $channel -SharedRuntime -Version $version -Architecture x64
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
    # Install the version of dotnet-cli used to compile
    & "$koreBuildFolder\dotnet\dotnet-install.ps1" -Channel $dotnetChannel -Version $dotnetVersion -Architecture x64
}

if (!($env:Path.Split(';') -icontains $dotnetLocalInstallFolder))
{
    Write-Host "Adding $dotnetLocalInstallFolder to PATH"
    $env:Path = "$newPath"
}

# wokaround for CLI issue: https://github.com/dotnet/cli/issues/2143
$sharedPath = (Join-Path (Split-Path ((get-command dotnet.exe).Path) -Parent) "shared");
(Get-ChildItem $sharedPath -Recurse *dotnet.exe) | %{ $_.FullName } | Remove-Item;

# We still nuget because dotnet doesn't have support for pushing packages
$nugetExePath = Join-Path $koreBuildFolder 'nuget.exe'
if (!(Test-Path $nugetExePath))
{
    Invoke-WebRequest "https://dist.nuget.org/win-x86-commandline/v4.0.0-rc4/NuGet.exe" -OutFile "$koreBuildFolder/nuget.exe"
}

$makeFileProj = "$koreBuildFolder/KoreBuild.proj"
$msbuildArtifactsDir = "$repoFolder/artifacts/msbuild"
$msbuildLogFilePath = "$msbuildArtifactsDir/msbuild.log"
$msBuildResponseFile = "$msbuildArtifactsDir/msbuild.rsp"

$preflightClpOption='/clp=DisableConsoleColor'
$msbuildClpOption='/clp:DisableConsoleColor;Summary'
if [ -z "${env:CI}${env:APPVEYOR}${env:TEAMCITY_VERSION}${env:TRAVIS}" ]; then
    # Not on any of the CI machines. Fine to use colors.
    $preflightClpOption=''
    $msbuildClpOption='/clp:Summary'
fi

$msBuildArguments = @"
/nologo
/m
/p:RepositoryRoot="$repoFolder/"
/fl
/flp:LogFile="$msbuildLogFilePath";Verbosity=detailed;Encoding=UTF-8
$msbuildClpOption
"$makeFileProj"
"@

$allparams | ForEach-Object { $msBuildArguments += "`n`"$_`"" }

if (!(Test-Path $msbuildArtifactsDir))
{
    mkdir $msbuildArtifactsDir | Out-Null
}

$msBuildArguments | Out-File -Encoding ASCII -FilePath $msBuildResponseFile

exec dotnet msbuild /nologo $preflightClpOption /t:Restore /p:PreflightRestore=true "$makeFileProj"
exec dotnet msbuild `@"$msBuildResponseFile"
