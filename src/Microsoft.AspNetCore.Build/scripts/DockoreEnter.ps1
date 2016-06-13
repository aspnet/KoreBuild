param([Parameter(Mandatory=$true)][string]$ImageName, [Parameter(ValueFromRemainingArguments=$true)][string[]]$DockerCommand)

$RepositoryRoot = Convert-Path (Get-Location)
Write-Host -ForegroundColor Green "Setting up DockoreBuild ..."

if(!(Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Can't use DockoreBuild without docker!"
}

if($ImageName.StartsWith("korebuild/")) {
    Write-Host -ForegroundColor Green "Ensuring KoreBuild image $ImageName is built ..."
    $ImageRelPath = $ImageName.Substring("korebuild/".Length).Replace(":", "\")
    $Root = Split-Path -Parent $PSScriptRoot
    $ImagePath = Join-Path (Join-Path $Root "docker") $ImageRelPath
    if(!(Test-Path "$ImagePath\Dockerfile")) {
        throw "Could not find Dockerfile in $ImagePath"
    }

    # Build the image
    docker build -t $ImageName $ImagePath
}

$DockerHostPath = $RepositoryRoot.Replace("\", "/")

# Run the image
Write-Host -ForegroundColor Green "Launching Docker Image '$ImageName' for build ..."

docker run -it --rm -v "$($DockerHostPath):/opt/code" $ImageName $DockerCommand
