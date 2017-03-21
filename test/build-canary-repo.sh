#!/usr/bin/env bash

set -efo pipefail

repo_url='https://github.com/aspnet/DependencyInjection.git'
while [[ $# > 0 ]]; do
    case $1 in
        -r|--repo-url|-RepoUrl)
            shift
            repo_url=$1
            ;;
        -h|--help)
            echo "Runs KoreBuild on a sample repository as a canary test"
            echo ""
            echo "Usage: $0 [-r|--repo-url <URL>]"
            echo ""
            echo "  -r|--repo-url     The url of the repo to git clone and build with KoreBuild"
            exit 2
            ;;
        *)
            echo "Unrecognized argument $1"
            exit 1
            ;;
    esac
    shift
done

script_root="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

workdir=$script_root/obj/
rm -rf $workdir 2>/dev/null && :

git clone $repo_url $workdir
cp -R $script_root/../build/ $workdir/.build/
$workdir/build.sh
