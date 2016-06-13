#!/usr/bin/env bash

# Stop the script on any error
set -e

show_help() {
    echo "Usage: $0 [-r] [--] [arguments to msbuild]"
    echo "       $0 [-r] [-u <URL>] [--] [arguments to msbuild]"
    echo "       $0 [-r] [-b <BRANCH>] [--] [arguments to msbuild]"
    echo ""
    echo "Arguments:"
	echo "		-d, --docker			Build in a docker container"
	echo "		--docker-image <IMAGE>	Build in a docker container based on <IMAGE> (implies --docker)"
    echo ""
    echo "Notes:"
    echo "      The '--' switch is only necessary when you want to pass an argument that would otherwise be recognized by this"
    echo "      script to KoreBuild. By default, any unrecognized argument will be forwarded to KoreBuild."
    echo ""
    echo "      If you wish to build a specific target from the MSBuild project file, use the '-t:<TARGET>' switch, which will be forwarded"
    echo "      to MSBuild. For example `.\build.sh -t:Verify`"
}

DEFAULT_DOCKER_IMAGE="korebuild/ubuntu:14.04"

while [[ $# > 0 ]]; do
    case $1 in
        -h|-\?|--help)
            show_help
            exit 0
            ;;
		-d|--docker)
			DOCKER_IMAGE="$DEFAULT_DOCKER_IMAGE"
			break
			;;
		--docker-image)
			DOCKER_IMAGE="$2"
			shift
			break
			;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
    shift
done

if [ ! -z "$DOCKER_IMAGE" ]; then
	exec "$DIR/DockoreEnter.sh" "$DOCKER_IMAGE" "$@"
	# exec takes over this process, so the rest won't be executed.
fi

# Colors
GREEN="\033[1;32m"
BLACK="\033[0;30m"
CYAN="\033[0;36m"
RESET="\033[0m"

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
    echo -e "${BLACK}KoreBuild 1.0 Compatibility Mode Enabled${RESET}"
    echo -e "${BLACK}KoreBuild 1.0 Command Line: ${@}${RESET}"
    echo -e "${BLACK}KoreBuild 2.0 Command Line: ${MSBUILD_ARGS[@]}${RESET}"
else
    MSBUILD_ARGS=("$@")
fi

export REPO_FOLDER=$PWD
export KOREBUILD_FOLDER="$(dirname $DIR)"

BUILD_ROOT="$REPO_FOLDER/.build"
KOREBUILD_ROOT="$( cd "$DIR/../../.." && pwd)"

DOTNET_INSTALL="$KOREBUILD_ROOT/build/dotnet/dotnet-install.sh"
DOTNET_VERSION_DIR="$KOREBUILD_ROOT/build"

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
        echo -e "${BLACK}MSBuild already initialized, use --reset-korebuild to refresh it${RESET}"
    fi
}

ensure_dotnet

RID=`dotnet --info | grep "RID" | awk '{ print $2 }'`
MSBUILD_DIR="$BUILD_ROOT/$RID/MSBuildTools"
TOOLS_DIR="$BUILD_ROOT/$RID/Tools"

ensure_msbuild

KOREBUILD_TARGETS_ROOT="$KOREBUILD_ROOT/src/Microsoft.AspNetCore.Build/targets"

PROJ="$REPO_FOLDER/makefile.proj"
if [ ! -e "$PROJ" ]; then
    PROJ="$KOREBUILD_TARGETS_ROOT/makefile.proj"
fi

MSBUILD_LOG="$BUILD_ROOT/korebuild.msbuild.log"
[ ! -e "$MSBUILD_LOG" ] || rm "$MSBUILD_LOG"

echo -e "${GREEN}Starting build...${RESET}"
echo -e "${CYAN}> msbuild $PROJ $@${RESET}"
"$MSBUILD_DIR/bin/pub/corerun" "$MSBUILD_DIR/bin/pub/MSBuild.exe" -nologo $PROJ -p:RuntimeIdentifier=$RID -p:KoreBuildToolsPackages="$BUILD_DIR" -p:KoreBuildTargetsPath="$KOREBUILD_TARGETS_ROOT" -p:KoreBuildTasksPath="$MSBUILD_DIR/bin/pub/" -fl -flp:logFile="$MSBUILD_LOG;verbosity=diagnostic" "${MSBUILD_ARGS[@]}"
