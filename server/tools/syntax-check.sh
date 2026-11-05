#!/usr/bin/env bash
# Compile-check mod-companion-voice against the realm's pinned core without a build (seconds): borrows the recorded
# compile command of a realm module in WoW-LLM-Bots/build-test (they share one include set) and points it here.
#   server/tools/syntax-check.sh [path to WoW-LLM-Bots]
set -euo pipefail
HERE=$(cd "$(dirname "$0")/../mod-companion-voice" && pwd)
PROJECT=${1:-$HOME/Projects/WoW-LLM-Bots}
WORK=$PROJECT/build-test
IMAGE=localhost/wow-ac-build:ubuntu24.04
[[ -f $WORK/build/compile_commands.json ]] || { echo "!!! $WORK/build/compile_commands.json missing (run its tools/test-build.sh once)"; exit 1; }
rc=0
for src in CompanionVoice.cpp loader.cpp; do
    cmd=$(python3 - "$WORK/build/compile_commands.json" "/cv/src/$src" <<'PY'
import json, shlex, sys
cc = json.load(open(sys.argv[1]))
sib = [c for c in cc if '/modules/mod-' in c['file'] and c['file'].endswith('.cpp')]
if not sib:
    sys.exit('no recorded compile command for a module to borrow')
args, out, skip = shlex.split(sib[0]['command'].replace(sib[0]['file'], sys.argv[2])), [], 0
for i, a in enumerate(args):
    if skip: skip -= 1; continue
    if a == '-Xclang' and i + 1 < len(args) and args[i + 1] in ('-include-pch', '-include', '-emit-pch'):
        skip = 3; continue
    if a in ('-o', '-MF', '-MT'): skip = 1; continue
    if a in ('-c', '-MD', '-Winvalid-pch'): continue
    out.append(a)
print(shlex.join(out[:1] + ['-fsyntax-only', '-Wall'] + out[1:]))
PY
)
    out=$(podman run --rm -v "$WORK/src/core:/azerothcore:ro" -v "$WORK/build:/build:ro" -v "$HERE:/cv:ro" \
            -w /build "$IMAGE" bash -c "$cmd" 2>&1) || rc=$?
    [[ -n $out ]] && sed 's/^/    /' <<<"$out"
    if [[ $rc -eq 0 ]]; then echo "  ok    src/$src"; else echo "  FAIL  src/$src (exit $rc)"; exit $rc; fi
done
