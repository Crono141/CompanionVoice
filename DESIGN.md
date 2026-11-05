# Companion Voice: design

Party and whisper chat is spoken aloud on the player's own machine. Whispers and party lines from bots, from
stock playerbots and from real players are all voiced. /say, yell and general channels are never voiced.
The mod is independent of every other mod. It shares no code, tables or addon prefixes with the specter mods or the
Companions addon. Without the server add-on it still works on any 3.3.5 server.

## Pieces

| Piece | Where | What it does |
|---|---|---|
| `cvoice.exe` (helper) | this repo, `helper/` | 64-bit process running Pocket TTS through sherpa-onnx; text and a reference clip in, 24 kHz PCM out over pipes |
| voice module | LivingVoices repo, inside `LivingVoices.dll` | Lua functions `CompanionVoice_*`; starts the helper; plays its audio through LivingVoices' miniaudio engine |
| `CompanionVoice` addon | this repo, `addon/` | listens to party/whisper chat, picks each sender's voice, queues lines, settings |
| voice pack | this repo, `pack/` (built by `tools/`) | designed reference clips: race/sex takes x pitch variants x deliveries |
| server add-on (our realm only) | this repo, `server/` | an AzerothCore module that sends a per-line delivery label as a hidden addon message |

Wow.exe is 32-bit and the patcher hooks one DLL (LivingVoices.dll), so the voice module lives there as a separate
module. Without the CompanionVoice addon nothing calls it. Without the voice module, the addon finds `CompanionVoice_Available`
missing and does nothing. The engine cannot run inside the 32-bit game: it needs 64-bit, ~570 MB RSS, and its CPU
time would hurt the frame rate. So it is a separate process.

## Engine (measured 2026-11-05, Ryzen 9 7950X, Linux, sherpa-onnx v2.0.1, int8 model)

- Model files 194 MB on disk (98 MB compressed). Runtime libs: onnxruntime ~26 MB + sherpa C API ~5 MB.
- Load 0.3 s. RTF ~0.2 on 2 threads. First audio chunk 0.2-0.7 s (sherpa calls back per chunk, not per frame).
  Peak RSS ~570 MB.
- Voice cloning: the reference audio is passed in each generation call, and sherpa caches its embedding
  (`voice_embedding_cache_capacity`). `num_steps` = 1 (sherpa's default 5 is no better by ear-free checks so far).
- Licences: Pocket TTS weights and the ONNX export are CC BY 4.0 (attribution). sherpa-onnx is Apache-2.0.
  Kyutai's use policy forbids cloning a real person without consent, so we use designed voices only.

## Helper protocol (stdin/stdout, binary)

Requests (DLL to helper), one per line, UTF-8, fields tab-separated:
- `SPEAK\t<id>\t<reference path>\t<text>`: generate; text has no tabs or newlines
- `CANCEL\t<id>`: stop that utterance (also drops it if still queued)
- `QUIT`

Replies (helper to DLL), frames: `uint8 type, uint32 id, uint32 len, payload[len]` (little-endian)
- `R` ready (payload: version string), sent once after the model loads
- `A` audio: int16 mono 24 kHz samples
- `E` end of utterance
- `X` error: UTF-8 message

The helper runs one utterance at a time, below-normal priority, 2 threads by default. It exits when stdin closes,
so it never outlives the game.

## Voices

- A voice is a race/sex **take** (40 approved designs, 1-4 per race/sex, `pack/manifest.json`) plus a pitch/formant
  **variant**. Both are drawn from a hash of the sender's name, so a given companion always sounds the same. Variants are
  baked offline onto the reference clip (Praat Change Gender). Shifting the output at run time was rejected by ear in
  Living Voices ("audible autotune"). Variants stay inside the approved range: human_f_a is the ceiling, so it is
  shifted down only.
- Each take has four **deliveries**: neutral (the design), urgent, amused, weary. These are IndexTTS-2 emotion-vector
  references in the take's voice: full strength for women, half for men (user, 2026-11-05).
- Sender race/sex: party members from `UnitRace`/`UnitSex`; whisper senders from `GetPlayerInfoByGUID` (event arg 12).
  Unknown (no GUID info yet) means human, by sex if known, else skip.

## Delivery labels (our realm)

The model that writes a bot's line also picks its delivery (one word from the fixed list), in the same call. The
bridge stores it with the line. That is the only bridge change (a minimal hook), and the bridge knows nothing about voices.
`mod-companion-voice` reads the label when the bot's chat goes out and sends it first, as an addon message with prefix
`CVOX`: `<delivery>\t<hash of the line text>`. The client matches it to the chat line that follows. A line with no label
gets neutral. Player-typed lines are always neutral. No keyword rules anywhere.

## Playback rules (addon)

- One speaker at a time, queued in order. A line still queued after 8 s is dropped, because a stale voice is worse than none.
- Never speaks over Living Voices quest audio: waits until it ends.
- The player's own lines are never voiced. Options: on/off, volume, bots only / everyone, mute a sender.
