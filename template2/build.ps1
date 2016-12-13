#Requires -Version 4
# Don't remove the next line, it's used by Universe to detect a KoreBuild 2.0-based repo.
# KoreBuild 2.0

<#
.SYNOPSIS
    Builds this project.
.DESCRIPTION
    Uses the ASP.NET Core Build System (KoreBuild) to build this repository. If not already present in the '.build' directory, this script downloads the latest copy of the KoreBuild tools from https://github.com/aspnet/KoreBuild (or the URL/Branch provided in the arguments). Eventually, MSBuild is invoked to perform the actual build. Additional arguments provided to this script are passed along to MSBuild. So, for example, to build a specific target, use '.\build.ps1 /t:Target'
.PARAMETER ResetKoreBuild
    Deletes the '.build' directory which contains the current set of KoreBuild scripts before building. This forces the build script to re-download the latest version of the scripts.
.PARAMETER KoreBuildUrl
    The URL from which to download the KoreBuild ZIP
.PARAMETER KoreBuildBranch
    The branch in the default KoreBuild repository (https://github.com/aspnet/KoreBuild) to download. This overrides the -KoreBuildUrl parameter.
.PARAMETER KoreKoreBuildRoot
    The local folder from which to retrieve KoreBuild files (designed for use when testing KoreBuild changes). This overrides both the -KoreBuildUrl and -KoreBuildBranch parameters.
#>

[CmdletBinding(PositionalBinding=$false,DefaultParameterSetName="DownloadDefault")]
param(
    [Alias("r")][switch]$ResetKoreBuild,
    [Parameter(ParameterSetName="DownloadByUrl")][Alias("u")][string]$KoreBuildUrl,
    [Parameter(ParameterSetName="DownloadByBranch")][Alias("b")][string]$KoreBuildBranch,
    [Parameter(ParameterSetName="DownloadFromFolder")]$KoreBuildFolder,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$KoreBuildArgs)

function DownloadWithRetry([string] $url, [string] $downloadLocation, [int] $retries)
{
    while($true)
    {
        try
        {
            Invoke-WebRequest $url -OutFile $downloadLocation | Out-Null
            break
        }
        catch
        {
            $exceptionMessage = $_.Exception.Message
            Write-Host "Failed to download '$url': $exceptionMessage"
            if ($retries -gt 0) {
                $retries--
                Write-Host "Waiting 10 seconds before retrying. Retries left: $retries"
                Start-Sleep -Seconds 10
            }
            else 
            {
                $exception = $_.Exception
                throw $exception
            }
        }
    }
}

if ($PSCmdlet.ParameterSetName -eq "DownloadDefault") {
    if(!$KoreBuildUrl) {
        $KoreBuildUrl = $env:KOREBUILD_ZIP
    }
    if(!$KoreBuildUrl) {
        $KoreBuildUrl = "https://github.com/aspnet/KoreBuild/archive/dev.zip"
    }
} elseif($PSCmdlet.ParameterSetName -eq "DownloadByBranch") {
    $KoreBuildUrl = "https://github.com/aspnet/KoreBuild/archive/$KoreBuildBranch.zip"
} # No need for an 'else' block, since KoreBuildUrl has been set!

$BuildFolder = Join-Path $PSScriptRoot ".build"
$KoreBuildRoot = Join-Path $BuildFolder "KoreBuild"
$BuildFile = Join-Path $KoreBuildRoot "scripts\KoreBuild.ps1"

if ($ResetKoreBuild -and (Test-Path $BuildFolder)) {
    Write-Host -ForegroundColor Green "Cleaning old Build folder to force a reset ..."
    del -rec -for $BuildFolder
}

if (!(Test-Path $KoreBuildRoot)) {
    if($KoreBuildFolder) {
        Write-Host -ForegroundColor Green "Copying local KoreBuild from $KoreBuildFolder ..."
        cp -rec $KoreBuildFolder $KoreBuildRoot
    } else {
        Write-Host -ForegroundColor Green "Downloading KoreBuild from $KoreBuildUrl ..."
        $KoreBuildDir = Join-Path ([IO.Path]::GetTempPath()) $([IO.Path]::GetRandomFileName())
        mkdir $KoreBuildDir | Out-Null
        $KoreBuildZip = Join-Path $KoreBuildDir "korebuild.zip"
        DownloadWithRetry -url $KoreBuildUrl -downloadLocation $KoreBuildZip -retries 6

        $KoreBuildExtract = Join-Path $KoreBuildDir "extract"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($KoreBuildZip, $KoreBuildExtract)

        pushd "$KoreBuildExtract\*"
        cp -rec . $KoreBuildRoot
        popd

        if (Test-Path $KoreBuildDir) {
            del -rec -for $KoreBuildDir
        }
    }
}

if(($KoreBuildArgs -contains "-t:") -or ($KoreBuildArgs -contains "-p:")) {
    throw "Due to PowerShell weirdness, you need to use '/t:' and '/p:' to pass targets and properties to MSBuild"
}

# Launch KoreBuild
try {
    pushd $PSScriptRoot
    & "$BuildFile" @KoreBuildArgs
} finally {
    popd
}
