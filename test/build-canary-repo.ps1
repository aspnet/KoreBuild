<#
.SYNOPSIS
    Runs KoreBuild on a sample repository as a canary test
.PARAMETER RepoUrl
    The url of the repo to git clone and build with KoreBuild
#>
param(
    [Alias("r")][string]$RepoUrl = 'https://github.com/aspnet/DependencyInjection.git')

$ErrorActionPreference ='Stop'

$workdir = "$PSScriptRoot/obj/"

if (Test-Path $workdir) {
    Remove-Item -Recurse -Force $workdir
}

if (!(Get-Command git -ErrorAction Ignore)) {
    throw 'git is not available on the PATH'
}

& git clone -q $RepoUrl $workdir
Copy-Item -Recurse "$PSScriptRoot/../build/" "$workdir/.build/"
& $workdir/build.ps1
