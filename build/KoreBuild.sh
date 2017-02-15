#!/usr/bin/env bash

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
    $cmd "$@"

    local exitCode=$?
    if [ $exitCode -ne 0 ]; then
        echo -e "${RED}'$cmdname $@' failed with exit code $exitCode${RESET}" 1>&2
        exit $exitCode
    fi
}

targets=""
repoFolder=""
while [[ $# > 0 ]]; do
    case $1 in
        -r)
            shift
            repoFolder=$1
            ;;
        *)
            if [ -z "$targets" ]; then
                targets="$1"
            else
                targets+=":$1"
            fi
            ;;
    esac
    shift
done
if [ ! -e "$repoFolder" ]; then
    printf "Usage: $filename -r [repoFolder] [ [targets] ]\n\n"
    echo "       -r [repo]     The repository to build"
    echo "       [targets]     A space separated list of targets to run"
    exit 1
fi

echo "Building $repoFolder"
cd $repoFolder

scriptRoot="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Make the path relative to the repo root because Sake/Spark doesn't support full paths
koreBuildFolder="${scriptRoot/$repoFolder/}"
koreBuildFolder="${koreBuildFolder#/}"

versionFile="$koreBuildFolder/cli.version"
version=$(<$versionFile)
sharedRuntimeVersionFile="$koreBuildFolder/shared-runtime.version"
sharedRuntimeVersion=$(<$sharedRuntimeVersionFile)

install_shared_runtime() {
    eval $invocation

    local version=$1
    local channel=$2

    local sharedRuntimePath="$DOTNET_INSTALL_DIR/shared/Microsoft.NETCore.App/$version"
    if [ ! -d "$sharedRuntimePath" ]; then
        $koreBuildFolder/dotnet/dotnet-install.sh --shared-runtime --channel $channel --version $version
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
    export KOREBUILD_FOLDER="$(dirname $koreBuildFolder)"
    chmod +x $koreBuildFolder/dotnet/dotnet-install.sh

    $koreBuildFolder/dotnet/dotnet-install.sh --channel rel-1.0.0 --version $version
    install_shared_runtime $sharedRuntimeVersion 'master'
    if [ ! -z "$KOREBUILD_DOTNET_SHARED_RUNTIME_VERSION" ]; then
        channel="$KOREBUILD_DOTNET_SHARED_RUNTIME_CHANNEL"
        [ -z "$channel" ] && channel="master"
        install_shared_runtime $KOREBUILD_DOTNET_SHARED_RUNTIME_VERSION $channel
    fi

    # Add .NET installation directory to the path if it isn't yet included.
    [[ ":$PATH:" != *":$DOTNET_INSTALL_DIR:"* ]] && export PATH="$DOTNET_INSTALL_DIR:$PATH"
fi


# workaround for CLI issue: https://github.com/dotnet/cli/issues/2143
DOTNET_PATH=`which dotnet | head -n 1`
ROOT_PATH=`dirname $DOTNET_PATH`
FOUND=`find $ROOT_PATH/shared -name dotnet`
if [ ! -z "$FOUND" ]; then
    echo $FOUND | xargs rm
fi

if [ "$(uname)" == "Darwin" ]; then
    ulimit -n 2048
fi

netfxversion='4.6.1'
if [ "$NUGET_PACKAGES" == "" ]; then
    NUGET_PACKAGES="$HOME/.nuget/packages"
fi
export ReferenceAssemblyRoot=$NUGET_PACKAGES/netframeworkreferenceassemblies/$netfxversion/content

nugetPath="$koreBuildFolder/nuget.exe"
if [ ! -f $nugetPath ]; then
    nugetUrl="https://dist.nuget.org/win-x86-commandline/v4.0.0-rc4/NuGet.exe"
    wget -O $nugetPath $nugetUrl 2>/dev/null || curl -o $nugetPath --location $nugetUrl 2>/dev/null
fi

export KOREBUILD_FOLDER="$koreBuildFolder"
makeFileProj="$koreBuildFolder/makefile.proj"

__exec dotnet restore "$makeFileProj" "/p:NetFxVersion=$netfxversion"

msbuildArtifactsDir="$repoFolder/artifacts/msbuild"
msbuildResponseFile="$msbuildArtifactsDir/msbuild.rsp"
msbuildLogFile="$msbuildArtifactsDir/msbuild.log"

if [ ! -f $msbuildArtifactsDir ]; then
    mkdir -p $msbuildArtifactsDir
fi

cat > $msbuildResponseFile <<ENDMSBUILDARGS
/nologo
/m
"$makeFileProj"
/p:RepositoryRoot="$repoFolder/"
/fl
/flp:LogFile="$msbuildLogFile";Verbosity=diagnostic;Encoding=UTF-8
/p:SakeTargets=$targets
ENDMSBUILDARGS

__exec dotnet msbuild @"$msbuildResponseFile"
