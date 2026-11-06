#!/usr/bin/env bash
# Assemble the release as players install it: build/package/CompanionVoice-<version>/ laid out like the World of
# Warcraft folder (the add-on under Interface\AddOns, the Living Voices engine and patcher beside Wow.exe), and a zip.
# Needs: helper/build.sh run, tools/build_pack.py run, and Living Voices' client built (LV=path, default
# ~/Projects/LivingVoices; client/build.sh there): the engine DLL that hosts Companion Voice is Living Voices' own.
set -euo pipefail
cd "$(dirname "$0")/.."
LV=${LV:-$HOME/Projects/LivingVoices}
VERSION=$(sed -n 's/^## Version: *//p' addon/CompanionVoice/CompanionVoice.toc | tr -d '\r')
M=third_party/sherpa-onnx-pocket-tts-int8-2026-01-26; F=third_party/sherpa-onnx-pocket-tts-2026-01-26
R=build/package/CompanionVoice-$VERSION; P=$R/Interface/AddOns/CompanionVoice
rm -rf build/package; mkdir -p $P/voices $P/engine/model
cp addon/CompanionVoice/*.toc addon/CompanionVoice/*.lua $P/
cp pack/out/voices/*_neutral.mp3 $P/voices/
cp build/win64/cvoice.exe build/win64/*.dll $P/engine/
# the voice encoder is OUR export (tools/export_encoder.py): sherpa's packaged encoder.onnx only ever reads the first
# ~1 s of a reference, which clipped the first word of every sentence
E=third_party/encoder-dynamic-2026-01.onnx
[[ -f $E ]] || { echo "!!! $E missing: run tools/export_encoder.py --language english_2026-01 --out $E"; exit 1; }
# Kyutai's recommended split: only the language model int8; the flow net and audio decoder full precision (blind
# listening 2026-11-05: the all-int8 take was the odd one out more often; +46 MB, +0.09 s first audio)
cp $M/lm_main.int8.onnx $M/text_conditioner.onnx $M/vocab.json $M/token_scores.json $M/LICENSE $P/engine/model/
cp $F/lm_flow.onnx $F/decoder.onnx $P/engine/model/
cp $E $P/engine/model/encoder.onnx
cp THIRD_PARTY.txt $P/
# the engine host: Living Voices' DLL (0.5+ carries cv_module.h) and its Wow.exe patcher, GPL-3.0, same author
[[ -f $LV/client/build/LivingVoices.dll ]] || { echo "!!! $LV/client/build/LivingVoices.dll missing: run client/build.sh there"; exit 1; }
grep -qa 'CompanionVoiceEngine' $LV/client/build/LivingVoices.dll \
    || { echo "!!! that LivingVoices.dll has no Companion Voice module (needs 0.5 or later)"; exit 1; }
cp $LV/client/build/LivingVoices.dll $LV/client/build/LivingVoicesPatcher.exe $LV/client/patch_wowexe.py $R/
cp packaging/README.txt packaging/LICENSES.txt THIRD_PARTY.txt $R/
(cd build/package && rm -f CompanionVoice-$VERSION.zip && zip -qr CompanionVoice-$VERSION.zip CompanionVoice-$VERSION)
du -sh $R $P/voices $P/engine build/package/CompanionVoice-$VERSION.zip
