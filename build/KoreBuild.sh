#!/usr/bin/env bash
set -o pipefail

# Colors
GREEN="\033[1;32m"
CYAN="\033[0;36m"
RESET="\033[0m"
RED="\033[0;31m"


# functions

__exec() {
    local cmd=$1
    shift

    local cmdname=$(basename $cmd)
    echo -e "${CYAN}> $cmdname $@${RESET}"

    if [ -z "${TRAVIS}" ]; then
        $cmd "$@"
    else
        # Work around https://github.com/Microsoft/msbuild/issues/1792
        $cmd "$@" | tee /dev/null
    fi

    local exitCode=$?
    if [ $exitCode -ne 0 ]; then
        echo -e "${RED}'$cmdname $@' failed with exit code $exitCode${RESET}" 1>&2
        exit $exitCode
    fi
}

msbuild_args=""
repoFolder=""
while [[ $# > 0 ]]; do
    case $1 in
        -r)
            shift
            repoFolder=$1
            ;;
        *)
            msbuild_args+="\"$1\"\n"
            ;;
    esac
    shift
done
if [ ! -e "$repoFolder" ]; then
    printf "Usage: $filename -r [repoFolder] [ [msbuild-args] ]\n\n"
    echo "       -r [repo]       The repository to build"
    echo "       [msbuild-args]  A space separated list of arguments to pass to MSBuild"
    exit 1
fi

echo "Building $repoFolder"
cd $repoFolder

scriptRoot="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# The default azure feed used to download .NET Core CLI
dotnet_azure_feed="https://dotnetcli.azureedge.net/dotnet"

if [ "$(uname)" == "Darwin" ]; then
    ulimit -n 2048

    # Check that OS is 10.12 or newer
    osx_version="$(sw_vers | grep ProductVersion | awk '{print $2}')"
    minor_version="$(echo $osx_version | awk -F '.' '{print $2}')"
    if [ $minor_version -lt 12 ]; then
        echo -e "${RED}.NET Core 2.0 requires OSX 10.12 or newer. Current version is $osx_version.${RESET}"
        exit 1
    fi

    if [ "$TRAVIS" = true ]; then
        # Travis OSX agents consistently have networking issues pulling from dotnetcli.azureedge.net.
        # This switches to using the "uncached feed"
        dotnet_azure_feed="https://dotnetcli.blob.core.windows.net/dotnet"
    fi
fi

versionFile="$scriptRoot/cli.version"
version=$(<$versionFile)
sharedRuntimeVersionFile="$scriptRoot/shared-runtime.version"
sharedRuntimeVersion=$(<$sharedRuntimeVersionFile)

[ -z "$KOREBUILD_DOTNET_CHANNEL" ] && KOREBUILD_DOTNET_CHANNEL="preview"
[ -z "$KOREBUILD_DOTNET_VERSION" ] && KOREBUILD_DOTNET_VERSION=$version

install_shared_runtime() {
    eval $invocation

    local version=$1
    local channel=$2

    local sharedRuntimePath="$DOTNET_INSTALL_DIR/shared/Microsoft.NETCore.App/$version"
    if [ ! -d "$sharedRuntimePath" ]; then
        $scriptRoot/dotnet/dotnet-install.sh \
            --shared-runtime \
            --channel $channel \
            --version $version \
            --azure-feed $dotnet_azure_feed

        if [ $? -ne 0 ]; then
            exit 1
        fi
    fi
}

if [ ! -z "$KOREBUILD_SKIP_RUNTIME_INSTALL" ]; then
    echo "Skipping runtime installation because KOREBUILD_SKIP_RUNTIME_INSTALL is set"

    # Add .NET installation directory to the path if it isn't yet included.
    # Add to the _end_ in case preferred .NET CLI is not in the default location.
    [[ ":$PATH:" != *":$DOTNET_INSTALL_DIR:"* ]] && export PATH="$PATH:$DOTNET_INSTALL_DIR"
else
    # Need to set this variable because by default the install script
    # requires sudo
    [ -z "$DOTNET_INSTALL_DIR" ] && DOTNET_INSTALL_DIR=~/.dotnet
    export DOTNET_INSTALL_DIR=$DOTNET_INSTALL_DIR
    chmod +x $scriptRoot/dotnet/dotnet-install.sh

    $scriptRoot/dotnet/dotnet-install.sh \
        --channel $KOREBUILD_DOTNET_CHANNEL \
        --version $KOREBUILD_DOTNET_VERSION \
        --azure-feed $dotnet_azure_feed

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Add .NET installation directory to the path if it isn't yet included.
    [[ ":$PATH:" != *":$DOTNET_INSTALL_DIR:"* ]] && export PATH="$DOTNET_INSTALL_DIR:$PATH"
fi

# Temporarily install 1.1.1 to prevent build breaks for repos not yet converted
install_shared_runtime "1.1.1" "release/1.1.0"

# Install shared runtime
# Example text: 2.0.0-preview1-2399;master
if [ "$sharedRuntimeVersion" != "" ]; then
    IFS=';' read -a parts <<< "$sharedRuntimeVersion"
    ver="${parts[0]}"
    ch="${parts[1]}"
    install_shared_runtime $ver $ch
fi

# workaround for CLI issue: https://github.com/dotnet/cli/issues/2143
DOTNET_PATH=`which dotnet | head -n 1`
ROOT_PATH=`dirname $DOTNET_PATH`
FOUND=`find $ROOT_PATH/shared -name dotnet`
if [ ! -z "$FOUND" ]; then
    echo $FOUND | xargs rm
fi

netfxversion='4.6.1'
if [ "$NUGET_PACKAGES" == "" ]; then
    NUGET_PACKAGES="$HOME/.nuget/packages"
fi
export ReferenceAssemblyRoot=$NUGET_PACKAGES/netframeworkreferenceassemblies/$netfxversion/content

nugetPath="$scriptRoot/nuget.exe"
if [ ! -f $nugetPath ]; then
    nugetUrl="https://dist.nuget.org/win-x86-commandline/v4.0.0-rc4/NuGet.exe"
    wget -O $nugetPath $nugetUrl 2>/dev/null || curl -o $nugetPath --location $nugetUrl 2>/dev/null
fi

makeFileProj="$scriptRoot/KoreBuild.proj"
msbuildArtifactsDir="$repoFolder/artifacts/msbuild"
msbuildPreflightResponseFile="$msbuildArtifactsDir/msbuild.preflight.rsp"
msbuildResponseFile="$msbuildArtifactsDir/msbuild.rsp"
msbuildLogFile="$msbuildArtifactsDir/msbuild.log"

if [ ! -f $msbuildArtifactsDir ]; then
    mkdir -p $msbuildArtifactsDir
fi

preflightClpOption='/clp:DisableConsoleColor'
msbuildClpOption='/clp:DisableConsoleColor;Summary'
if [ -z "${CI}${APPVEYOR}${TEAMCITY_VERSION}${TRAVIS}" ]; then
    # Not on any of the CI machines. Fine to use colors.
    preflightClpOption=''
    msbuildClpOption='/clp:Summary'
fi

cat > $msbuildPreflightResponseFile <<ENDMSBUILDPREFLIGHT
/nologo
/p:NetFxVersion=$netfxversion
/p:PreflightRestore=true
/p:RepositoryRoot="$repoFolder/"
/t:Restore
$preflightClpOption
"$makeFileProj"
ENDMSBUILDPREFLIGHT

# workaround https://github.com/dotnet/core-setup/issues/1664
echo "{\"sdk\":{\"version\":\"$KOREBUILD_DOTNET_VERSION\"}}" > "$repoFolder/global.json"

__exec dotnet msbuild @"$msbuildPreflightResponseFile"

cat > $msbuildResponseFile <<ENDMSBUILDARGS
/nologo
/m
/p:RepositoryRoot="$repoFolder/"
/fl
/flp:LogFile="$msbuildLogFile";Verbosity=detailed;Encoding=UTF-8
$msbuildClpOption
"$makeFileProj"
ENDMSBUILDARGS
echo -e "$msbuild_args" >> $msbuildResponseFile

__exec dotnet msbuild @"$msbuildResponseFile"
