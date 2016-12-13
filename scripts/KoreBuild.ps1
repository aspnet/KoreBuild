#Requires -Version 4
# Just here to isolate the build template from having to know anything about the interior structure of KoreBuild.
# You can move pretty much everything else in this repo EXCEPT this file.
$KoreBuildRoot = Convert-Path (Split-Path -Parent $PSScriptRoot)
$KoreBuild = Join-Path "$KoreBuildRoot" "src\Microsoft.AspNetCore.Build\scripts\KoreBuild.ps1"
& "$KoreBuild" @args
