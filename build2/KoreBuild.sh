#!/usr/bin/env bash
set -e

# Colors
GREEN="\033[1;32m"
BLACK="\033[0;30m"
CYAN="\033[0;36m"
RESET="\033[0m"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo -e "${GREEN}Preparing KoreBuild 2.0...${RESET}"

export REPO_FOLDER=$PWD
export KOREBUILD_FOLDER="$(dirname $DIR)"

BUILD_ROOT="$REPO_FOLDER/.build"
KOREBUILD_ROOT="$( cd "$DIR/.." && pwd)"

DOTNET_INSTALL="$KOREBUILD_ROOT/build/dotnet/dotnet-install.sh"
DOTNET_VERSION_DIR="$KOREBUILD_ROOT/build"

MSBUILD_DIR="$BUILD_ROOT/MSBuildTools"
TOOLS_DIR="$BUILD_ROOT/Tools"

KOREBUILD_LOG="$BUILD_ROOT/korebuild.log"
[ ! -e "$KOREBUILD_LOG" ] || rm "$KOREBUILD_LOG"

__exec() {
    local cmd=$1
    shift

    local cmdname=$(basename $cmd)
    echo -e "${CYAN}> $cmdname $@${RESET}"
    echo ">>>>> $cmd $@ <<<<<" >> $KOREBUILD_LOG
    $cmd "$@" >> $KOREBUILD_LOG
}

ensure_dotnet() {
    if test `uname` = Darwin; then
        versionFileName="cli.version.darwin"
    else
        versionFileName="cli.version.unix"
    fi
    versionFile="$DOTNET_VERSION_DIR/$versionFileName"
    version=$(<$versionFile)

    [ -z "$KOREBUILD_DOTNET_CHANNEL" ] && KOREBUILD_DOTNET_CHANNEL=preview
    [ -z "$KOREBUILD_DOTNET_VERSION" ] && KOREBUILD_DOTNET_VERSION=$version

    if [ ! -z "$KOREBUILD_SKIP_RUNTIME_INSTALL" ]; then
        echo -e "${BLACK}Skipping runtime installation because KOREBUILD_SKIP_RUNTIME_INSTALL is set${RESET}"

        # Add .NET installation directory to the path if it isn't yet included.
        # Add to the _end_ in case preferred .NET CLI is not in the default location.
        [[ ":$PATH:" != *":$DOTNET_INSTALL_DIR:"* ]] && export PATH="$PATH:$DOTNET_INSTALL_DIR"
    else
        # Need to set this variable because by default the install script
        # requires sudo
        export DOTNET_INSTALL_DIR=~/.dotnet
        chmod +x $DOTNET_INSTALL

        __exec $DOTNET_INSTALL --channel $KOREBUILD_DOTNET_CHANNEL --version $KOREBUILD_DOTNET_VERSION >> $KOREBUILD_LOG

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
}

ensure_msbuild() {
    if [ ! -d "$MSBUILD_DIR" ]; then
        RID=`dotnet --info | grep "RID" | awk '{ print $2 }'`

        mkdir -p $MSBUILD_DIR
        cat "$KOREBUILD_ROOT/build2/msbuild.project.json.template" | sed "s/RUNTIME/$RID/g" > "$MSBUILD_DIR/project.json"
        cp "$KOREBUILD_ROOT/NuGet.config" "$MSBUILD_DIR"

        echo -e "${GREEN}Preparing MSBuild ...${RESET}"
        __exec dotnet restore "$MSBUILD_DIR/project.json" -v Minimal
        __exec dotnet publish "$MSBUILD_DIR/project.json" -o "$MSBUILD_DIR/bin/pub"

        echo -e "${GREEN}Preparing KoreBuild Tasks ...${RESET}"
        __exec dotnet restore "$KOREBUILD_ROOT/src/Microsoft.AspNetCore.Build.Tasks" -v Minimal
        __exec dotnet publish "$KOREBUILD_ROOT/src/Microsoft.AspNetCore.Build.Tasks" -o "$MSBUILD_DIR/bin/pub" -f "netcoreapp1.0"
    else
        echo -e "${BLACK}MSBuild already initialized, use --reset-korebuild to refresh it${RESET}"
    fi
}

ensure_dotnet
ensure_msbuild

PROJ="$REPO_FOLDER/makefile.proj"
if [ ! -e "$PROJ" ]; then
    PROJ="$KOREBUILD_ROOT/msbuild/makefile.proj"
fi

MSBUILD_LOG="$BUILD_ROOT/korebuild.msbuild.log"
[ ! -e "$MSBUILD_LOG" ] || rm "$MSBUILD_LOG"

echo -e "${GREEN}Starting build...${RESET}"
echo -e "${CYAN}> msbuild $PROJ $@${RESET}"
"$MSBUILD_DIR/bin/pub/corerun" "$MSBUILD_DIR/bin/pub/MSBuild.exe" /nologo $PROJ /p:KoreBuildTasksPath="$MSBUILD_DIR/bin/pub/" /fl "/flp:logFile=$MSBUILD_LOG;verbosity=diagnostic" "$@"
