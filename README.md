# Companion Voice

Party and whisper chat in World of Warcraft 3.3.5a, spoken aloud on the player's own computer, each speaker in a
designed voice that fits their race and sex. Made for servers with talking playerbots (for example
[mod-llm-chatter](https://github.com/Hokken/mod-llm-chatter)), but it voices players' lines too. `/say`, yell and
channels are never spoken.

**Players:** download `CompanionVoice-<version>.zip` from [Releases](../../releases) and follow its `README.txt`.
It's one zip: the add-on, its speech engine, and the small [Living Voices](https://github.com/Crono141/LivingVoices)
client patch that lets the game load it. You do not need Living Voices' quest voice-over to use it.

## How it works

- **The add-on** (`addon/CompanionVoice`) listens to party and whisper chat, picks a voice for each speaker from their
  race and sex (a stable choice per name; 40 designed voices × 3 pitch variants), applies a pronunciation guide for
  Warcraft names, and queues the line. Settings: channels, whose lines, combat, volume, speed, a skip list, a chosen
  voice per person (`/cvoice`).
- **The speech helper** (`helper/cvoice.cpp`) is a 64-bit process running [Pocket TTS](https://github.com/kyutai-labs/pocket-tts)
  through [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) on the CPU (2 threads, below-normal priority). It
  clones each line from the speaker's reference clip and plays it with miniaudio. First audio is usually under a
  second after the text.
- **The engine host** is `LivingVoices.dll` 0.5+ (`client/cv_module.h` in the Living Voices repo): the 32-bit game
  can't run the model itself, so the DLL gives the add-on a `CompanionVoiceEngine` Lua API and starts the helper.
- **The server module** (`server/mod-companion-voice`, optional) is for AzerothCore realms running an LLM chat
  bridge. It tells the add-on which party/whisper lines a bot's language model wrote and which group members are bots,
  so a bot's canned status whispers stay silent. Without it, the add-on's skip list does that job. See its README.

The design and the listening tests behind each choice are in [DESIGN.md](DESIGN.md).

## Building the release

    tools/fetch_sherpa.sh                     # sherpa-onnx v2.0.1 (Linux + Windows x64) and the Pocket TTS models, pinned
    python tools/export_encoder.py --language english_2026-01 --out third_party/encoder-dynamic-2026-01.onnx
    helper/build.sh                           # cvoice for Linux (tests) and Windows x64 (ships)
    python tools/build_pack.py --takes DIR    # the voice pack from the designed reference takes (needs parselmouth, ffmpeg)
    python tools/build_pronounce.py --guide pronounce.json
    LV=path/to/LivingVoices tools/package.sh  # build/package/CompanionVoice-<version>/ and its zip

`export_encoder.py` exists because sherpa's packaged Pocket TTS encoder reads only the first ~1 s of a reference,
which clipped the first word of every sentence; it re-exports the encoder from Kyutai's weights with dynamic length.
`tools/measure_drift.py` measures how far the engine lifts each voice's pitch; `build_pack.py` takes that off the
reference (`pack/drift.json`).

The designed reference takes and the pronunciation guide come from the Living Voices project's data; the built clips
ship in each release.

## Tests

    python3 helper/test_cvoice.py build/linux/cvoice MODEL_DIR REF1 REF2 OUTDIR
    (cd addon/test && lua5.1 sim.lua)
    server/tools/syntax-check.sh PROJECT      # compile-checks the server module, borrowing a configured AzerothCore
                                              # build's compile_commands.json (PROJECT/build-test/build)

## Licence

GPL-3.0 (`LICENSE`); the server module is AGPL-3.0 (`server/mod-companion-voice/LICENSE`), like AzerothCore.
Third-party works and their licences: [THIRD_PARTY.txt](THIRD_PARTY.txt). Every voice is designed from a text
description; none is cloned from a real person (Kyutai's use policy forbids that without consent).

A fan work: not affiliated with, endorsed by or sponsored by Blizzard Entertainment.
