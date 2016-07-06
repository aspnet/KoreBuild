#requires -version 4

Write-Host -ForegroundColor Green "Starting KoreBuild 2.0 ..."

$RepositoryRoot = Convert-Path (Get-Location)
$BuildRoot = Join-Path $RepositoryRoot ".build"
$KoreBuildRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ArtifactsDir = Join-Path $RepositoryRoot "artifacts"

$env:REPO_FOLDER = $RepositoryRoot
$env:KOREBUILD_FOLDER = $KoreBuildRoot

$RID = "win7-x64";
if($env:PROCESSOR_ARCHITECTURE -eq "x86") {
    $RID = "win7-x86";
}

$MSBuildDir = Join-Path $BuildRoot "MSBuildTools"
$ToolsDir = Join-Path $BuildRoot "Tools"

$KoreBuildLog = Join-Path $BuildRoot "korebuild.log"
if(Test-Path $KoreBuildLog) {
    del $KoreBuildLog
}

$MSBuildLog = Join-Path $BuildRoot "korebuild.msbuild.log"
if(Test-Path $MSBuildLog) {
    del $MSBuildLog
}

$MSBuildResponseFile = Join-Path $BuildRoot "korebuild.msbuild.rsp"
if(Test-Path $MSBuildResponseFile) {
    del $MSBuildResponseFile
}


function exec($cmd) {
    $cmdName = [IO.Path]::GetFileName($cmd)
    Write-Host -ForegroundColor DarkGray "> $cmdName $args"
    "`r`n>>>>> $cmd $args <<<<<`r`n" >> $KoreBuildLog
    & $cmd @args 2>&1 >> $KoreBuildLog
    $exitCode = $LASTEXITCODE
    if($exitCode -ne 0) {
        throw "'$cmdName $args' failed with exit code: $exitCode. See '$ArtifactsDir\korebuild.log' for details"
    }
}

function EnsureDotNet() {
    $dotnetVersionFile = "$KoreBuildRoot\build\cli.version.win"
    $dotnetChannel = "rel-1.0.0"
    $dotnetVersion = Get-Content $dotnetVersionFile

    if ($env:KOREBUILD_DOTNET_CHANNEL)
    {
        $dotnetChannel = $env:KOREBUILD_DOTNET_CHANNEL
    }
    if ($env:KOREBUILD_DOTNET_VERSION)
    {
        $dotnetVersion = $env:KOREBUILD_DOTNET_VERSION
    }

    $dotnetLocalInstallFolder = "$env:LOCALAPPDATA\Microsoft\dotnet\"
    $newPath = "$dotnetLocalInstallFolder;$env:PATH"
    if ($env:KOREBUILD_SKIP_RUNTIME_INSTALL -eq "1")
    {
        Write-Host -ForegroundColor Green "Skipping runtime installation because KOREBUILD_SKIP_RUNTIME_INSTALL = 1"
        # Add to the _end_ of the path in case preferred .NET CLI is not in the default location.
        $newPath = "$env:PATH;$dotnetLocalInstallFolder"
    }
    else
    {
        Write-Host -ForegroundColor Green "Installing .NET Command-Line Tools ..."
        exec "$KoreBuildRoot\build\dotnet\dotnet-install.ps1" -Channel $dotnetChannel -Version $dotnetVersion -Architecture x64
    }
    if (!($env:Path.Split(';') -icontains $dotnetLocalInstallFolder))
    {
        Write-Host -ForegroundColor Green "Adding $dotnetLocalInstallFolder to PATH"
        $env:Path = "$newPath"
    }

    # workaround for CLI issue: https://github.com/dotnet/cli/issues/2143
    $sharedPath = (Join-Path (Split-Path ((get-command dotnet.exe).Path) -Parent) "shared");
    (Get-ChildItem $sharedPath -Recurse *dotnet.exe) | %{ $_.FullName } | Remove-Item;
}

function EnsureMSBuild() {
    if(!(Test-Path $MSBuildDir)) {
        try {
            mkdir $MSBuildDir | Out-Null
            $content = [IO.File]::ReadAllText((Convert-Path "$PSScriptRoot\msbuild.project.template.json"))
            $content = $content.Replace("RUNTIME", $RID)

            [IO.File]::WriteAllText((Join-Path $MSBuildDir "project.json"), $content);

            copy "$KoreBuildRoot\NuGet.config" "$MSBuildDir"

            Write-Host -ForegroundColor Green "Preparing MSBuild ..."
            exec dotnet restore "$MSBuildDir\project.json" -v Detailed
            exec dotnet publish "$MSBuildDir\project.json" -o "$MSBuildDir\bin\pub"

            Write-Host -ForegroundColor Green "Preparing KoreBuild Tasks ..."
            exec dotnet restore "$KoreBuildRoot\src\Microsoft.AspNetCore.Build" -v Detailed
            exec dotnet publish "$KoreBuildRoot\src\Microsoft.AspNetCore.Build" -o "$MSBuildDir\bin\pub" -f "netcoreapp1.0"
        } catch {
            $ex = $error[0]
            # Clean up to ensure we aren't half-initialized
            if(Test-Path $MSBuildDir) {
                del -rec -for $MSBuildDir
            }

            throw $ex
        }
    } else {
        Write-Host -ForegroundColor DarkGray "MSBuild already initialized, use -Reset to refresh it"
    }
}

function EnsureTools() {
    if(!(Test-Path $ToolsDir)) {
        try {
            Write-Host -ForegroundColor Green "Preparing other build tools ..."
            exec dotnet restore "$KoreBuildRoot\tools\project.json" -v Detailed --packages "$ToolsDir"
        } catch {
            # Clean up to ensure we aren't half-initialized
            if(Test-Path $ToolsDir) {
                del -rec -for $ToolsDir
            }
        }
    } else {
        Write-Host -ForegroundColor DarkGray "Build tools already initialized, use -Reset to refresh them"
    }
}

try {
    EnsureDotNet
    EnsureMSBuild
    EnsureTools

    $KoreBuildTargetsRoot = "$KoreBuildRoot\src\Microsoft.AspNetCore.Build\targets"

    # Check for a local KoreBuild project
    $Proj = Join-Path "$RepositoryRoot" "makefile.proj"
    if(!(Test-Path $Proj)) {
        $Proj = Join-Path "$KoreBuildTargetsRoot" "makefile.proj"
    }

    $MSBuildArguments = @"
/nologo
"$Proj"
/p:KoreBuildToolsPackages="$ToolsDir"
/p:KoreBuildTargetsPath="$KoreBuildTargetsRoot"
/p:KoreBuildTasksPath="$MSBuildDir\bin\pub"
/fl
/flp:LogFile="$MSBuildLog";Verbosity=diagnostic;Encoding=UTF-8
"@

    $MSBuildArguments | Out-File -Encoding ASCII -FilePath $MSBuildResponseFile
    $args | ForEach { $_ | Out-File -Append -Encoding ASCII -FilePath $MSBuildResponseFile } # Add local args to RSP

    Write-Host -ForegroundColor Green "Starting build ..."
    Write-Host -ForegroundColor DarkGray "> msbuild $Proj $args"

    & "$MSBuildDir\bin\pub\CoreRun.exe" "$MSBuildDir\bin\pub\MSBuild.exe" `@"$MSBuildResponseFile"
} finally {
    # Copy logs to artifacts
    if(!(Test-Path $ArtifactsDir)) {
        mkdir $ArtifactsDir | Out-Null
    }
    cp -ErrorAction SilentlyContinue $MSBuildResponseFile,$KoreBuildLog,$MSBuildLog $ArtifactsDir
}
