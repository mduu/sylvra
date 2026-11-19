#!/usr/bin/env bash
# Renders the README close-ups (light and dark) from the screenshots in docs/screenshots.
#   scripts/readme/closeups.sh      (take the screenshots first, see scripts/screenshot.sh)
# Regions: x,y,w,h in units of a 1400 px wide preview of the 2940 px captures.
set -euo pipefail
cd "$(dirname "$0")/../.."
D=docs/screenshots
TOOL=.build/closeup
[ "$TOOL" -nt scripts/readme/closeup.swift ] || swiftc -O -o "$TOOL" scripts/readme/closeup.swift

closeup() { # name h|v shot:region …
  local name=$1 layout=$2; shift 2
  for mode in light dark; do
    local suffix=""; [ "$mode" = dark ] && suffix="-dark"
    local regions=()
    for spec in "$@"; do regions+=("$D/${spec%%:*}$suffix.png:${spec#*:}"); done
    "$TOOL" "$D/closeup-$name$suffix.png" "$mode" "$layout" "${regions[@]}"
  done
  echo "closeup-$name"
}

closeup inbox h app-30-overview:0,48,210,424 app-26-repository-browser:0,48,210,424
closeup pr-at-a-glance v app-30-overview:218,62,288,236 app-30-overview:221,501,283,104
closeup new-commits v app-38-new-commits:520,52,570,112
closeup commit-by-commit h app-31-commit-by-commit:218,232,285,350 app-31-commit-by-commit:520,98,575,350
closeup check-report v app-32-check-report:398,175,608,286
closeup reading-order v app-42-reading-order:224,182,278,228
closeup ai-finding v app-36-ai-box:515,234,885,86 app-36-ai-box:622,566,770,220
closeup ai-panel v app-30-overview:1105,62,290,390
closeup ai-chat h app-33-ai-chat:585,300,505,248 app-33-ai-chat:1105,160,290,360
closeup finding-to-comment v app-37-finding-to-comment:585,447,505,372
closeup tone-check v app-21-tone-check:585,568,505,210
closeup conversation v app-35-conversation:218,230,285,415
closeup compact v app-34-compact:0,0,1400,879
