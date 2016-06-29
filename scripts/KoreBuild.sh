# Just here to isolate the build template from having to know anything about the interior structure of KoreBuild.
# You can move pretty much everything else in this repo EXCEPT this file.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
"$ROOT/src/Microsoft.AspNetCore.Build/scripts/KoreBuild.sh" "$@"
