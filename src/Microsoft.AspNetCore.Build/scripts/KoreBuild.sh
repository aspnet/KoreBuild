#!/usr/bin/env bash

# Colors
GREEN="\033[1;32m"
CYAN="\033[0;36m"
RESET="\033[0m"
RED="\033[0;31m"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo -e "${GREEN}Preparing KoreBuild 2.0...${RESET}"

if [ "$KOREBUILD_COMPATIBILITY" = "1" ]; then
    MSBUILD_ARGS=()
    for arg in "$@"; do
        case $arg in
            --quiet)
                MSBUILD_ARGS=(${MSBUILD_ARGS[@]} -v:m)
                ;;
            --*)
                echo "Unknown KoreBuild 1.0 switch: $arg. If this switch took an argument, you'll have a bad problem :)"
                ;;
            *)
                TARGET="-t:$(echo "${arg[@]:0:1}" | tr "[:lower:]" "[:upper:]")${arg[@]:1}"
                MSBUILD_ARGS=(${MSBUILD_ARGS[@]} "$TARGET")
                ;;
        esac
    done
    echo -e "${CYAN}KoreBuild 1.0 Compatibility Mode Enabled${RESET}"
    echo -e "${CYAN}KoreBuild 1.0 Command Line: ${@}${RESET}"
    echo -e "${CYAN}KoreBuild 2.0 Command Line: ${MSBUILD_ARGS[@]}${RESET}"
else
    MSBUILD_ARGS=("$@")
fi

export REPO_FOLDER=$PWD
export KOREBUILD_FOLDER="$(dirname $DIR)"

BUILD_ROOT="$REPO_FOLDER/.build"
KOREBUILD_ROOT="$( cd "$DIR/../../.." && pwd)"
ARTIFACTS_DIR="$REPO_FOLDER/artifacts"
[ -d $ARTIFACTS_DIR ] || mkdir $ARTIFACTS_DIR

DOTNET_INSTALL="$KOREBUILD_ROOT/build/dotnet/dotnet-install.sh"
DOTNET_VERSION_DIR="$KOREBUILD_ROOT/build"

MSBUILD_DIR="$BUILD_ROOT/MSBuildTools"
TOOLS_DIR="$BUILD_ROOT/Tools"

KOREBUILD_LOG="$BUILD_ROOT/korebuild.log"
[ ! -e "$KOREBUILD_LOG" ] || rm "$KOREBUILD_LOG"

MSBUILD_RSP="$BUILD_ROOT/korebuild.msbuild.rsp"
[ ! -e "$MSBUILD_RSP" ] || rm "$MSBUILD_RSP"

MSBUILD_LOG="$BUILD_ROOT/korebuild.msbuild.log"
[ ! -e "$MSBUILD_LOG" ] || rm "$MSBUILD_LOG"


__exec() {
    local cmd=$1
    shift

    local cmdname=$(basename $cmd)
    echo -e "${CYAN}> $cmdname $@${RESET}"
    echo ">>>>> $cmd $@ <<<<<" >> $KOREBUILD_LOG
    $cmd "$@" 2>&1 >> $KOREBUILD_LOG

    local exitCode=$?
    if [ $exitCode -ne 0 ]; then
        echo -e "${RED}'$cmdname $@' failed with exit code $exitCode${RESET}" 1>&2
        echo -e "${RED} check '$ARTIFACTS_DIR/korebuild.log' for more info.${RESET}" 1>&2
        __end $exitCode
    fi
}

ensure_dotnet() {
    if test `uname` = Darwin; then
        versionFileName="cli.version.darwin"
    else
        versionFileName="cli.version.unix"
    fi
    versionFile="$DOTNET_VERSION_DIR/$versionFileName"
    version=$(<$versionFile)

    [ -z "$KOREBUILD_DOTNET_CHANNEL" ] && KOREBUILD_DOTNET_CHANNEL=rel-1.0.0
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
        cat "$KOREBUILD_ROOT/src/Microsoft.AspNetCore.Build/scripts/msbuild.project.template.json" | sed "s/RUNTIME/$RID/g" > "$MSBUILD_DIR/project.json"
        cp "$KOREBUILD_ROOT/NuGet.config" "$MSBUILD_DIR"

        echo -e "${GREEN}Preparing MSBuild ...${RESET}"
        __exec dotnet restore "$MSBUILD_DIR/project.json" -v Minimal
        __exec dotnet publish "$MSBUILD_DIR/project.json" -o "$MSBUILD_DIR/bin/pub"

        echo -e "${GREEN}Preparing KoreBuild Tasks ...${RESET}"
        __exec dotnet restore "$KOREBUILD_ROOT/src/Microsoft.AspNetCore.Build" -v Minimal
        __exec dotnet publish "$KOREBUILD_ROOT/src/Microsoft.AspNetCore.Build" -o "$MSBUILD_DIR/bin/pub" -f "netcoreapp1.0"
    else
        echo -e "${CYAN}MSBuild already initialized, use --reset-korebuild to refresh it${RESET}"
    fi
}

__join() {
    local IFS="$1"
    shift
    echo "$*"
}

__end() {
    local EXITCODE=$1

    # Copy logs to artifacts
    cp $MSBUILD_LOG $KOREBUILD_LOG $MSBUILD_RSP $ARTIFACTS_DIR 2>/dev/null >/dev/null

    [ -e "$MSBUILD_LOG" ] && rm $MSBUILD_LOG
    [ -e "$MSBUILD_RSP" ] && rm $MSBUILD_RSP
    [ -e "$KOREBUILD_LOG" ] && rm $KOREBUILD_LOG

    exit $EXITCODE
}

ensure_dotnet
ensure_msbuild

KOREBUILD_TARGETS_ROOT="$KOREBUILD_ROOT/src/Microsoft.AspNetCore.Build/targets"

PROJ="$REPO_FOLDER/makefile.proj"
if [ ! -e "$PROJ" ]; then
    PROJ="$KOREBUILD_TARGETS_ROOT/makefile.proj"
fi

cat > $MSBUILD_RSP <<ENDMSBUILDARGS
-nologo
"$PROJ"
-p:KoreBuildToolsPackages="$BUILD_DIR"
-p:KoreBuildTargetsPath="$KOREBUILD_TARGETS_ROOT"
-p:KoreBuildTasksPath="$MSBUILD_DIR/bin/pub/"
-fl
-flp:LogFile="$MSBUILD_LOG";Verbosity=diagnostic;Encoding=UTF-8
ENDMSBUILDARGS
__join $'\n' $MSBUILD_ARGS >> $MSBUILD_RSP

echo -e "${GREEN}Starting build...${RESET}"
echo -e "${CYAN}> msbuild $PROJ $@${RESET}"

# Enable "on error result next" ;P
"$MSBUILD_DIR/bin/pub/corerun" "$MSBUILD_DIR/bin/pub/MSBuild.exe" @"$MSBUILD_RSP"
__end $?
