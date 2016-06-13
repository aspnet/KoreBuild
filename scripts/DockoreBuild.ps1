# Just here to isolate the build template from having to know anything about the interior structure of KoreBuild.
# You can move pretty much everything else in this repo EXCEPT this file.
$KoreBuildRoot = Convert-Path (Split-Path -Parent $PSScriptRoot)
$DockoreBuild = Join-Path "$KoreBuildRoot" "src\Microsoft.AspNetCore.Build\scripts\DockoreBuild.ps1"
& "$DockoreBuild" @args
