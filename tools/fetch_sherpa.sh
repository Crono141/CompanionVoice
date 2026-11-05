#!/usr/bin/env bash
# sherpa-onnx (Apache-2.0) and the Pocket TTS int8 ONNX model (CC BY 4.0), pinned by version and SHA-256, into third_party/.
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
