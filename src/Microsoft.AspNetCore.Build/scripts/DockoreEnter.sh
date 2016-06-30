#!/usr/bin/env bash
# Stop the script on any error
set -e

echo "Not yet updated"
exit 1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Colors
GREEN="\033[1;32m"
BLACK="\033[0;30m"
CYAN="\033[0;36m"
RESET="\033[0m"

IMAGE_NAME=$1
shift

echo -e "${GREEN}Setting up DockoreBuild ...${RESET}"
if ! type -p docker >/dev/null; then
    echo "Can't use DockoreBuild without docker!" 1>&2
    exit 1
fi

if [[ $IMAGE_NAME = korebuild/* ]]; then
    echo -e "${GREEN}Ensuring KoreBuild image $IMAGE_NAME is built ..."
    IMAGE_REL_PATH="$(echo "$IMAGE_NAME" | sed s/korebuild\///g s/:/\//g)"
    IMAGE_PATH="$DIR/docker/$IMAGE_REL_PATH"
    if [ ! -e $IMAGE_PATH ]; then
        echo "Could not find Dockerfile in $IMAGE_PATH" 1>&2
        exit 1
    fi

    # Build the image
    docker build -t $IMAGE_NAME $IMAGE_PATH
fi

# Run the build
echo -e "${GREEN}Launching Docker Image '$IMAGE_NAME' for build ..."
docker run -it --rm -v "$PWD:/opt/code" $IMAGE_NAME "$@"
