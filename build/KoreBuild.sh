#!/usr/bin/env bash

targets=""
repoFolder=""
while [[ $# > 0 ]]; do
    case $1 in
        -r)
            shift
            repoFolder=$1
            ;;
        *)
            targets+=" $1"
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

# Make the path relative to the repo root because Sake/Spark doesn't support full paths
koreBuildFolder="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
koreBuildFolder="${koreBuildFolder/$repoFolder/}"
koreBuildFolder="${koreBuildFolder#/}"

[ -z "$KOREBUILD_DOTNET_CHANNEL" ] && KOREBUILD_DOTNET_CHANNEL=beta
[ -z "$KOREBUILD_DOTNET_VERSION" ] && KOREBUILD_DOTNET_VERSION=1.0.0.001540

if [ ! -z "$KOREBUILD_SKIP_RUNTIME_INSTALL" ]; then
    echo "Skipping runtime installation because KOREBUILD_SKIP_RUNTIME_INSTALL is set"

    # Add .NET installation directory to the path if it isn't yet included.
    # Add to the _end_ in case preferred .NET CLI is not in the default location.
    [[ ":$PATH:" != *":$DOTNET_INSTALL_DIR/bin:"* ]] && export PATH="$PATH:$DOTNET_INSTALL_DIR/bin"
else
    # Need to set this variable because by default the install script
    # requires sudo
    export DOTNET_INSTALL_DIR=~/.dotnet
    export KOREBUILD_FOLDER="$(dirname $koreBuildFolder)"
    chmod +x $koreBuildFolder/dotnet/install.sh
    $koreBuildFolder/dotnet/install.sh --channel $KOREBUILD_DOTNET_CHANNEL --version $KOREBUILD_DOTNET_VERSION

    # Add .NET installation directory to the path if it isn't yet included.
    [[ ":$PATH:" != *":$DOTNET_INSTALL_DIR/bin:"* ]] && export PATH="$DOTNET_INSTALL_DIR/bin:$PATH"
fi

# Probe for Mono Reference assemblies
if [ -z "$DOTNET_REFERENCE_ASSEMBLIES_PATH" ]; then
    if [ $(uname) == Darwin ] && [ -d "/Library/Frameworks/Mono.framework/Versions/Current/lib/mono/xbuild-frameworks" ]; then
        export DOTNET_REFERENCE_ASSEMBLIES_PATH="/Library/Frameworks/Mono.framework/Versions/Current/lib/mono/xbuild-frameworks"
    elif [ -d "/usr/local/lib/mono/xbuild-frameworks" ]; then
        export DOTNET_REFERENCE_ASSEMBLIES_PATH="/usr/local/lib/mono/xbuild-frameworks"
    elif [ -d "/usr/lib/mono/xbuild-frameworks" ]; then
        export DOTNET_REFERENCE_ASSEMBLIES_PATH="/usr/lib/mono/xbuild-frameworks"
    fi
fi

if [ "$(uname)" == "Darwin" ]; then
    ulimit -n 2048
fi

echo "Using Reference Assemblies from: $DOTNET_REFERENCE_ASSEMBLIES_PATH"

sakeFolder=$koreBuildFolder/Sake
if [ ! -d $sakeFolder ]; then
    toolsProject="$koreBuildFolder/project.json"
    dotnet restore "$toolsProject" --packages "$koreBuildFolder" -v Minimal
    # Rename the project after restore because we don't want it to be restore afterwards
    mv "$toolsProject" "$toolsProject.norestore"
fi

nugetPath="$koreBuildFolder/nuget.exe"
if [ ! -f $nugetPath ]; then
    nugetUrl="https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    wget -O $nugetPath $nugetUrl 2>/dev/null || curl -o $nugetPath --location $nugetUrl 2>/dev/null
fi

makeFile="makefile.shade"
if [ ! -e $makeFile ]; then
    makeFile="$koreBuildFolder/shade/makefile.shade"
fi

export KOREBUILD_FOLDER="$koreBuildFolder"
mono $sakeFolder/0.2.2/tools/Sake.exe -I $koreBuildFolder/shade -f $makeFile $targets
