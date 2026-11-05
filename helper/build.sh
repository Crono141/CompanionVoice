#!/usr/bin/env bash
# Build cvoice for Linux (testing) and Windows x64 (shipping), against the pinned sherpa-onnx (tools/fetch_sherpa.sh).
set -euo pipefail
cd "$(dirname "$0")/.."; T=third_party; mkdir -p build/linux build/win64
L=$T/sherpa-onnx-v2.0.1-linux-x64-shared; W=$T/sherpa-onnx-v2.0.1-win-x64-shared-MT-Release-lib
[[ -d $L && -d $W ]] || tools/fetch_sherpa.sh
g++ -std=c++17 -O2 -Wall -Wno-unused-function -o build/linux/cvoice helper/cvoice.cpp -I$L/include \
    -L$L/lib -lsherpa-onnx-c-api -Wl,-rpath,"$PWD/$L/lib" -lpthread -lm -ldl
# Windows: the C API's import library (MSVC .lib) links from MinGW for plain C functions; static libstdc++/winpthread
x86_64-w64-mingw32-g++ -std=c++17 -O2 -Wall -Wno-unused-function -static -static-libgcc -static-libstdc++ \
    -o build/win64/cvoice.exe helper/cvoice.cpp -I$L/include $W/lib/sherpa-onnx-c-api.lib
x86_64-w64-mingw32-strip build/win64/cvoice.exe
cp $W/lib/sherpa-onnx-c-api.dll $W/lib/onnxruntime.dll $W/lib/onnxruntime_providers_shared.dll build/win64/
ls -la build/linux/cvoice build/win64/
