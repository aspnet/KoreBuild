#Requires -Version 4
# Installs KoreBuild into a repo, overwriting all previous build scripts
# This script is downloaded and executed without any of the corresponding scripts in this repo, so don't assume anything in this repo is available!

param(
    [switch]$Local,
    [string]$KoreBuildUrl)

## Sucks that we have to have a copy of this in both this script AND the build script :(.
function DownloadWithRetry([string] $url, [string] $downloadLocation, [int] $retries)
{
    while($true)
    {
        try
        {
            Invoke-WebRequest $url -OutFile $downloadLocation
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

# Prerequisites
if(!(Test-Path "$(Get-Location)\.git")) {
    throw "This install script should be run from the root of a Git repo"
}

$Changes = git diff --name-only
if($Changes) {
    throw "There are unstaged changes in this repo. Reset or stage them before installing KoreBuild"
}

function ConfirmOverwrite($message) {
    $title = "Overwrite previous build scripts?"
    $prompt = "$message Should we continue? [Y]es or [N]o?"
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes','Continues installation'
    $no = New-Object System.Management.Automation.Host.ChoiceDescription '&No','Cancels installation'
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
    $choice = $host.UI.PromptForChoice($title, $prompt, $options, 1);

    if($choice -ne 0) {
        throw "User cancelled the operation"
    }
}

$OldBuildScriptExists = @(
    (Test-Path "$(Get-Location)\build.cmd"),
    (Test-Path "$(Get-Location)\build.ps1"),
    (Test-Path "$(Get-Location)\build.sh")
)

# Check the existing build scripts
if($OldBuildScriptExists -contains $true) {
    ConfirmOverwrite "Build scripts already exist, possibly from a previous KoreBuild installation. They will be replaced by this process."
}

# Determine KoreBuild Repo URL if not specified
if(!$KoreBuildUrl) {
    $KoreBuildUrl = $env:KOREBUILD_ZIP
}
if(!$KoreBuildUrl) {
    $KoreBuildUrl = "https://github.com/aspnet/KoreBuild/archive/dev.zip"
}

if($Local) {
    $TemplateSource = Join-Path (Split-Path -Parent $PSScriptRoot) "template2"
    Write-Host -ForegroundColor Green "Copying template files from $TemplateSource ..."
    dir $TemplateSource | ForEach-Object {
        $dest = Join-Path (Get-Location) $_.Name
        Write-Host -ForegroundColor Cyan "* $($_.Name)"
        cp $_.FullName $dest
    }
}
else {
    $KoreBuildZip = Join-Path ([IO.Path]::GetTempPath()) "$([IO.Path]::GetRandomFileName()).zip"

    Write-Host -ForegroundColor Green "Downloading KoreBuild files to $KoreBuildZip ..."
    DownloadWithRetry -url $KoreBuildUrl -downloadLocation $KoreBuildZip -retries 6

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($KoreBuildZip)
    try {
        # Copy the template files over top of existing files.
        Write-Host -ForegroundColor Green "Copying template files from $KoreBuildZip ..."
        $zip.Entries | ForEach-Object {
            $dir = [IO.Path]::GetDirectoryName($_.FullName)
            if ($dir.EndsWith("template2") -and ($_.Name)) {
                Write-Host -ForegroundColor Cyan "* $($_.Name)"
                $dest = Join-Path (Convert-Path (Get-Location)) $_.Name
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $dest, $true)

                git add $dest

                if($_.Name.EndsWith(".sh")) {
                    # Make sure that git records the "x" mode flag on this file (since we can't set it directly because Windows)
                    git update-index --chmod=+x $dest
                }
            }
        }
    }
    finally {
        $zip.Dispose()
        Write-Host -ForegroundColor Green "Deleting temporary download $KoreBuildZip ..."
        del -for $KoreBuildZip
    }

    Write-Host -ForegroundColor Green "KoreBuild has been installed into this repo. The changes are ready to be committed."
}
