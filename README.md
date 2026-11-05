# Companion Voice

Party and whisper chat spoken aloud on the player's own machine, each speaker in a designed voice that fits their
race and sex. The design is in DESIGN.md.

## Build

    tools/fetch_sherpa.sh          # sherpa-onnx v2.0.1 (Linux + Windows x64) and the Pocket TTS int8 model, pinned
    helper/build.sh                # cvoice for Linux (tests) and Windows x64 (ships)
    python tools/build_pack.py --deliveries ~/Projects/LivingVoices/data/companion_voices/deliveries
    tools/package.sh               # build/package/CompanionVoice/ and CompanionVoice.zip

The client side also needs LivingVoices.dll 0.5 or later (LivingVoices repo, client/cv_module.h).

## Test

    python3 helper/test_cvoice.py build/linux/cvoice third_party/sherpa-onnx-pocket-tts-int8-2026-01-26 REF1 REF2 OUTDIR
    (cd addon/test && lua5.1 sim.lua)
    server/tools/syntax-check.sh   # the server module against the realm's pinned core, no build

## Realm (delivery labels)

1. The column, once: mod-llm-chatter's `data/sql/characters/updates/20261105_speech_style.sql` on acore_characters.
2. The bridge: mod-llm-chatter's Python (speech_style), staged with `98-llm-chatter.sh stage`.
3. The module: `WoW-LLM-Bots/modules/mod-companion-voice` links to `server/mod-companion-voice`; the next image build
   includes it.

Third-party licences: THIRD_PARTY.txt.
