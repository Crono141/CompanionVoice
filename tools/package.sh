#!/usr/bin/env bash
# Assemble the add-on as players install it: build/package/CompanionVoice/ (add-on, voices, engine) and a zip.
# Needs: helper/build.sh run, tools/build_pack.py run. LivingVoices.dll 0.5+ ships with Living Voices, not here.
set -euo pipefail
cd "$(dirname "$0")/.."
M=third_party/sherpa-onnx-pocket-tts-int8-2026-01-26; P=build/package/CompanionVoice
rm -rf build/package; mkdir -p $P/voices $P/engine/model
cp addon/CompanionVoice/*.toc addon/CompanionVoice/*.lua $P/
cp pack/out/voices/*.mp3 $P/voices/
cp build/win64/cvoice.exe build/win64/*.dll $P/engine/
cp $M/lm_flow.int8.onnx $M/lm_main.int8.onnx $M/encoder.onnx $M/decoder.int8.onnx $M/text_conditioner.onnx \
   $M/vocab.json $M/token_scores.json $M/LICENSE $P/engine/model/
cp THIRD_PARTY.txt $P/
(cd build/package && rm -f CompanionVoice.zip && zip -qr CompanionVoice.zip CompanionVoice)
du -sh $P $P/voices $P/engine build/package/CompanionVoice.zip
