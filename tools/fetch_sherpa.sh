#!/usr/bin/env bash
# sherpa-onnx (Apache-2.0) and the Pocket TTS ONNX models (int8 and full precision) (CC BY 4.0), pinned by version and SHA-256, into third_party/.
set -euo pipefail
cd "$(dirname "$0")/.."; mkdir -p third_party; cd third_party
get() {  # tag file sha256
    [[ -f "$2" ]] || gh release download "$1" -R k2-fsa/sherpa-onnx -p "$2"
    echo "$3  $2" | sha256sum -c --quiet
    local d="${2%.tar.bz2}"; [[ -d "$d" ]] || tar xjf "$2"
}
get v2.0.1 sherpa-onnx-v2.0.1-linux-x64-shared.tar.bz2 2e823376987c3b6960d50726b6560155e2ad92da0b8b3886325773225ec6bdec
get v2.0.1 sherpa-onnx-v2.0.1-win-x64-shared-MT-Release-lib.tar.bz2 afa4de3ca4ab0afd53bb4aab40d28ee15608364b549ffc0fe0caf6489bfc39a5
get tts-models sherpa-onnx-pocket-tts-int8-2026-01-26.tar.bz2 2f3b88823cbbb9bf0b2477ec8ae7b3fec417b3a87b6bb5f256dba66f2ad967cb
# the full-precision package: the shipped flow net and audio decoder come from it (Kyutai's split, tools/package.sh)
get tts-models sherpa-onnx-pocket-tts-2026-01-26.tar.bz2 61422a478ef09d9b2c067261fb822e11786e0c86842c76d8633b7069968be7b5
