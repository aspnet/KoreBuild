#requires -version 4

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
    # TODO temporarily install preview4 while we move to RC3
    & "$koreBuildFolder\dotnet\dotnet-install.ps1" -Channel $dotnetChannel -Version 1.0.0-preview4-004233 -Architecture x64
    & "$koreBuildFolder\dotnet\dotnet-install.ps1" -Channel $dotnetChannel -Version $dotnetVersion -Architecture x64
    InstallSharedRuntime '1.1.0' 'release/1.1.0'

    $sharedRuntimeChannel='master'
    InstallSharedRuntime $sharedRuntimeVersion $sharedRuntimeChannel

    Write-Host ''
    Write-Host -ForegroundColor Cyan 'To run tests in Visual Studio, you may need to run this installer:'
    Write-Host -ForegroundColor Cyan "https://dotnetcli.blob.core.windows.net/dotnet/$sharedRuntimeChannel/Installers/$sharedRuntimeVersion/dotnet-win-x64.$sharedRuntimeVersion.exe"
    Write-Host ''

    if ($env:KOREBUILD_DOTNET_SHARED_RUNTIME_VERSION)
    {
        $channel = 'master'
        if ($env:KOREBUILD_DOTNET_SHARED_RUNTIME_CHANNEL)
        {
            $channel = $env:KOREBUILD_DOTNET_SHARED_RUNTIME_CHANNEL
        }
        InstallSharedRuntime $env:KOREBUILD_DOTNET_SHARED_RUNTIME_VERSION $channel
    }
}
if (!($env:Path.Split(';') -icontains $dotnetLocalInstallFolder))
{
    Write-Host "Adding $dotnetLocalInstallFolder to PATH"
    $env:Path = "$newPath"
}

# wokaround for CLI issue: https://github.com/dotnet/cli/issues/2143
$sharedPath = (Join-Path (Split-Path ((get-command dotnet.exe).Path) -Parent) "shared");
(Get-ChildItem $sharedPath -Recurse *dotnet.exe) | %{ $_.FullName } | Remove-Item;

if (!(Test-Path "$koreBuildFolder\Sake"))
{
    $toolsProject = "$koreBuildFolder\tools.proj"
    &dotnet restore "$toolsProject" --packages "$PSScriptRoot" -v Minimal
    # We still nuget because dotnet doesn't have support for pushing packages
    Invoke-WebRequest "https://dist.nuget.org/win-x86-commandline/v3.5.0-beta2/NuGet.exe" -OutFile "$koreBuildFolder/nuget.exe"
}

$makeFilePath = "makefile.shade"
if (!(Test-Path $makeFilePath))
{
    $makeFilePath = "$koreBuildFolder\shade\makefile.shade"
}

Write-Host "Using makefile: $makeFilePath"

$env:KOREBUILD_FOLDER=$koreBuildFolder
&"$koreBuildFolder\Sake\0.2.2\tools\Sake.exe" -I $koreBuildFolder\shade -f $makeFilePath @args
