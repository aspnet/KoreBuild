$repoFolder = $env:REPO_FOLDER
if (!$repoFolder) {
    throw "REPO_FOLDER is not set"
}

Write-Host "Building $repoFolder"
cd $repoFolder

# Make the path relative to the repo root because Sake/Spark doesn't support full paths
$koreBuildFolder = $PSScriptRoot
$koreBuildFolder = $koreBuildFolder.Replace($repoFolder, "").TrimStart("\")

$dotnetVersionFile = $koreBuildFolder + "\cli.version.win"
$dotnetChannel = "beta"
$dotnetVersion = Get-Content $dotnetVersionFile

if ($env:KOREBUILD_DOTNET_CHANNEL) 
{
    $dotnetChannel = $env:KOREBUILD_DOTNET_CHANNEL
}
if ($env:KOREBUILD_DOTNET_VERSION) 
{
    $dotnetVersion = $env:KOREBUILD_DOTNET_VERSION
}

$dotnetLocalInstallFolder = "$env:LOCALAPPDATA\Microsoft\dotnet\cli"
$dotnetLocalInstallFolderBin = "$dotnetLocalInstallFolder\bin"
$newPath = "$dotnetLocalInstallFolderBin;$env:PATH"
if ($env:KOREBUILD_SKIP_RUNTIME_INSTALL -eq "1") 
{
    Write-Host "Skipping runtime installation because KOREBUILD_SKIP_RUNTIME_INSTALL = 1"
    # Add to the _end_ of the path in case preferred .NET CLI is not in the default location.
    $newPath = "$env:PATH;$dotnetLocalInstallFolderBin"
}
else
{
    & "$koreBuildFolder\dotnet\install.ps1" -Channel $dotnetChannel -Version $dotnetVersion
}
if (!($env:Path.Split(';') -icontains $dotnetLocalInstallFolderBin))
{
    Write-Host "Adding $dotnetLocalInstallFolderBin to PATH"
    $env:Path = "$newPath"
}

if (!(Test-Path "$koreBuildFolder\Sake")) 
{
    $toolsProject = "$koreBuildFolder\project.json"
    &dotnet restore "$toolsProject" --packages "$koreBuildFolder" -f https://www.myget.org/F/dnxtools/api/v3/index.json -v Minimal
    # Rename the project after restore because we don't want it to be restore afterwards
    mv "$toolsProject" "$toolsProject.norestore"
    # We still nuget because dotnet doesn't have support for pushing packages
    Invoke-WebRequest "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile "$koreBuildFolder/nuget.exe"
}

$makeFilePath = "makefile.shade"
if (!(Test-Path $makeFilePath)) 
{
    $makeFilePath = "$koreBuildFolder\shade\makefile.shade"
}

Write-Host "Using makefile: $makeFilePath"

$env:KOREBUILD_FOLDER=$koreBuildFolder
&"$koreBuildFolder\Sake\0.2.2\tools\Sake.exe" -I $koreBuildFolder\shade -f $makeFilePath @args