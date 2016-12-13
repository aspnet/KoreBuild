#!/usr/bin/env bash

# KoreBuild 2.0

# Colors
GREEN="\033[1;32m"
BLACK="\033[0;30m"
RED="\033[0;31m"
RESET="\033[0m"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR

show_help() {
    echo "Usage: $0 [-r] [--] [arguments to msbuild]"
    echo "       $0 [-r] [-u <URL>] [--] [arguments to msbuild]"
    echo "       $0 [-r] [-b <BRANCH>] [--] [arguments to msbuild]"
    echo ""
    echo "Arguments:"
    echo "      -r, --reset-korebuild               Delete the current `.build` directory and re-fetch KoreBuild"
    echo "      -u, --korebuild-url <URL>           Fetch KoreBuild from URL"
    echo "      -b, --korebuild-branch <BRANCH>     Fetch KoreBuild from BRANCH in the default repository (https://github.com/aspnet/KoreBuild)"
    echo "      --korebuild-dir <DIR>               Copy KoreBuild from DIR instead of downloading it"
    echo "      --                                  Consider all remaining arguments arguments to MSBuild when building the repo."
    echo ""
    echo "Notes:"
    echo "      The '--' switch is only necessary when you want to pass an argument that would otherwise be recognized by this"
    echo "      script to MSBuild. By default, any unrecognized argument will be forwarded to MSBuild."
    echo ""
    echo "      If you wish to build a specific target from the MSBuild project file, use the '-t:<TARGET>' switch, which will be forwarded"
    echo "      to MSBuild. For example `.\build.sh -t:Verify`"
}

while [[ $# > 0 ]]; do
    case $1 in
        -h|-\?|--help)
            show_help
            exit 0
            ;;
        -r|--reset-korebuild)
            KOREBUILD_RESET=1
            ;;
        -u|--korebuild-url)
            KOREBUILD_URL=$2
            shift
            ;;
        -b|--korebuild-branch)
            KOREBUILD_BRANCH=$2
            shift
            ;;
        --korebuild-dir)
            KOREBUILD_LOCAL=$2
            shift
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

if [ -z $KOREBUILD_URL ]; then
    if [ ! -z $KOREBUILD_BRANCH ]; then
        KOREBUILD_URL="https://github.com/aspnet/KoreBuild/tarball/$KOREBUILD_BRANCH"
    else
        KOREBUILD_URL="https://github.com/aspnet/KoreBuild/tarball/dev"
    fi
fi

BUILD_FOLDER="$DIR/.build"
KOREBUILD_ROOT="$BUILD_FOLDER/KoreBuild"
BUILD_FILE="$KOREBUILD_ROOT/scripts/KoreBuild.sh"

if [[ -d $BUILD_FOLDER && $KOREBUILD_RESET = "1" ]]; then
    echo -e "${GREEN}Cleaning old KoreBuild folder to force a reset ...${RESET}"
    rm -Rf $BUILD_FOLDER
fi

if [ ! -d $BUILD_FOLDER ]; then
    mkdir -p $BUILD_FOLDER
    if [ ! -z $KOREBUILD_LOCAL ]; then
        echo -e "${GREEN}Copying KoreBuild from $KOREBUILD_LOCAL ...${RESET}"
        cp -R "$KOREBUILD_LOCAL" "$KOREBUILD_ROOT"
    else
        echo -e "${GREEN}Downloading KoreBuild from $KOREBUILD_URL ...${RESET}"

        KOREBUILD_DIR=`mktemp -d`
        KOREBUILD_TAR="$KOREBUILD_DIR/korebuild.tar.gz"

        retries=6
        until (wget -O $KOREBUILD_TAR $KOREBUILD_URL 2>/dev/null || curl -o $KOREBUILD_TAR --location $KOREBUILD_URL 2>/dev/null); do
            echo -e "${RED}Failed to download '$KOREBUILD_TAR'${RESET}"
            if [ "$retries" -le 0 ]; then
                exit 1
            fi
            retries=$((retries - 1))
            echo "${BLACK}Waiting 10 seconds before retrying. Retries left: $retries${RESET}"
            sleep 10s
        done

        mkdir $KOREBUILD_ROOT
        tar xf $KOREBUILD_TAR --strip-components 1 --directory $KOREBUILD_ROOT
        rm -Rf $KOREBUILD_DIR
    fi
fi

cd $DIR
chmod a+x $BUILD_FILE
$BUILD_FILE "$@"
