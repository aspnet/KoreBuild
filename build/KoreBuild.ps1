$repoFolder = $env:REPO_FOLDER
if (!$repoFolder) {
    throw "REPO_FOLDER is not set"
}

Write-Host "Building $repoFolder"
cd $repoFolder

# Make the path relative to the repo root because Sake/Spark doesn't support full paths
$koreBuildFolder = $PSScriptRoot
$koreBuildFolder = $koreBuildFolder.Replace($repoFolder, "").TrimStart("\")

$dotnetChannel = "beta"
$dotnetVersion = "1.0.0.001496"

if ($env:KOREBUILD_DOTNET_CHANNEL) 
{
    $dotnetChannel = $env:KOREBUILD_DOTNET_CHANNEL
}
if ($env:KOREBUILD_DOTNET_VERSION) 
{
    $dotnetVersion = $env:KOREBUILD_DOTNET_VERSION
}
if ($env:KOREBUILD_SKIP_RUNTIME_INSTALL -eq "1") 
{
    Write-Host "Skipping runtime installation because KOREBUILD_SKIP_RUNTIME_INSTALL = 1"
}
else
{
    $dotnetLocalInstallFolder = "$env:LOCALAPPDATA\Microsoft\dotnet\cli"
    $dotnetLocalInstallFolderBin = "$dotnetLocalInstallFolder\bin"
    & "$koreBuildFolder\dotnet\install.ps1" -Channel $dotnetChannel -Version $dotnetVersion

    Write-Host "Adding $dotnetLocalInstallFolderBin to PATH"
    $env:Path = "$dotnetLocalInstallFolderBin;$env:PATH"

    # ==== Temporary =====
    if ($env:SKIP_DNX_INSTALL -ne "1") 
    {
        $dnxVersion = "latest"
        if ($env:BUILDCMD_DNX_VERSION) 
        {
            $dnxVersion = $env:BUILDCMD_DNX_VERSION
        }

        &"$koreBuildFolder\dnvm\dnvm.cmd" install $dnxVersion -runtime CoreCLR -arch x86 -alias default
        &"$koreBuildFolder\dnvm\dnvm.cmd" install default -runtime CLR -arch x86 -alias default
    }
    else
    {
        &"$koreBuildFolder\dnvm\dnvm.cmd" use default -runtime CLR -arch x86
    }
    # ====================
}

if (!(Test-Path "$koreBuildFolder\Sake")) 
{
    &dotnet restore "$koreBuildFolder\project.json" --packages "$koreBuildFolder" -f https://www.myget.org/F/dnxtools/api/v3/index.json -v Minimal
}

$makeFilePath = "makefile.shade"
if (!(Test-Path $makeFilePath)) 
{
    $makeFilePath = "$koreBuildFolder\shade\makefile.shade"
}

Write-Host "Using makefile: $makeFilePath"

$env:KOREBUILD_FOLDER=$koreBuildFolder
&"$koreBuildFolder\Sake\0.2.2\tools\Sake.exe" -I $koreBuildFolder\shade -f $makeFilePath @args