# Companion Voice: design

Party and whisper chat is spoken aloud on the player's own machine. Whispers and party lines from bots, from
stock playerbots and from real players are all voiced. /say, yell and general channels are never voiced.
The mod is independent of every other mod. It shares no code, tables or addon prefixes with the realm mods it was
built beside. Without the server add-on it still works on any 3.3.5 server.

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
  (`voice_embedding_cache_capacity`). `num_steps` = 1.
- A whole line is generated at once (`--sentences 10`) with the engine's own pause between sentences
  (`--silence 1.0`). One sentence at a time (0.2 pause) reset prosody at every full stop and sounded rushed; the whole
  line matched the Python trials' pace (2.79 vs 2.77 words/s), first audio as quick, first words heard right 34/50 vs
  29/50 (faster-whisper, 2026-11-05). The full-precision model heard 36/50 but doubled the first-audio wait and the
  download (472 MB).
- Precision, decided 2026-11-05 by blind listening (20 lines, 4 voices, fixed encoder, same seed): the shipped split is
  Kyutai's own, only the language model (lm_main) int8, the flow net and audio decoder full precision. Best picks:
  full 6, split 3, all-int8 5, can't tell 6; the all-int8 take was most often the one that sounded clearly off, and
  the split and full were hard to tell apart. Model files 240 MB, first audio median 0.79 s (all-int8 194 MB, 0.70 s;
  full 472 MB, 1.18 s). No measurable 2-5 kHz roughness in any of them; the difference is in delivery.
- Speed: sherpa's speed setting moves Pocket TTS only 2-4%. Pocket speaks at its reference's pace, so a speed other
  than 1 stretches the REFERENCE in time, pitch kept (WSOLA, cached per voice and speed): 0.8 -> 3.09, 1.0 -> 3.49,
  1.25 -> 4.33 words/s, clarity unchanged. The output is never processed.
- Licences: Pocket TTS weights and the ONNX export are CC BY 4.0 (attribution). sherpa-onnx is Apache-2.0.
  Kyutai's use policy forbids cloning a real person without consent, so we use designed voices only.

## Helper protocol (stdin/stdout, binary)

Requests (DLL to helper), one per line, UTF-8, fields tab-separated:
- `SPEAK\t<id>\t<reference path>\t<text>[\t<speed>]`: generate; text has no tabs or newlines; speed 0.5-2.0 (1 = the reference's own pace; the engine honours it)
- `CANCEL\t<id>`: stop that utterance (also drops it if still queued)
- `QUIT`

Replies (helper to DLL), frames: `uint8 type, uint32 id, uint32 len, payload[len]` (little-endian)
- `R` ready (payload: version string), sent once after the model loads
- `A` audio: int16 mono 24 kHz samples
- `E` end of utterance
- `X` error: UTF-8 message (still followed by `E`: every SPEAK ends with exactly one `E`, cancelled or not)

The helper runs one utterance at a time, below-normal priority, 2 threads by default. It exits when stdin closes,
so it never outlives the game.

## Voices

- A voice is a race/sex **take** (40 approved designs, 1-4 per race/sex, `pack/manifest.json`) plus a pitch/formant
  **variant**. Both are drawn from a hash of the sender's name, so a given companion always sounds the same. Variants are
  baked offline onto the reference clip (Praat Change Gender). Shifting the output at run time was rejected by ear in
  Living Voices ("audible autotune"). Men: design, +1.5 and -1.5 semitones (mirrored down above the race's highest
  approved take). Women only go down (design, -1.2, -2.5): Pocket already lifts women's excited lines far above their
  reference, and a raised one reached 485 Hz, which sounds autotuned.
- Each take has four **deliveries**: neutral (the design), urgent, amused, weary. These are IndexTTS-2 emotion-vector
  references in the take's voice: full strength for women, half for men (user, 2026-11-05); half also for deep
  women whose clip rose more than 7 semitones (night elf A/B/D, tauren B, draenei B urgent, orc A amused). Weary is
  full for everyone.
- Sender race/sex: party members from `UnitRace`/`UnitSex`; whisper senders from `GetPlayerInfoByGUID` (event arg 12).
  Unknown (no GUID info yet) means human, by sex if known, else skip.

## Delivery labels (our realm)

The model that writes a bot's line also picks its delivery (one word from the fixed list), in the same call. The
bridge stores it with the line (`llm_chatter_messages.speech_style`, NULL = neutral). That is the only bridge change
(a minimal hook), and the bridge knows nothing about voices. `mod-companion-voice` reads every party and whisper line
the bridge queues and sends a label as an addon message with prefix `CVOX`: `<delivery>\t<FNV-1a 32 of the line
text>`, usually before the bot says it. It also sends each real player `bots\t<names>`, the bots in their group
(when it changes and every minute). The client keeps labels 60 s and matches one when the line is about to be spoken.
Once a realm has sent the bot list, a known bot's line with no label (playerbots' canned status text) is not spoken;
players are always spoken. No keyword rules anywhere.

## Playback rules (addon)

- One speaker at a time, queued in order. A line may wait 30 s (setting) behind others; past 6 waiting, the oldest goes.
- Never speaks over Living Voices quest audio: waits until it ends.
- The player's own lines are never voiced; *actions* are never spoken (the bridge asks the model for the matching
  emote, which the core plays). Settings (Options.lua, /cvoice): on/off, party/whispers, who is heard (group, friends,
  guild, everyone else), only realm-labelled lines, quiet in combat, volume, speed, longest line, longest wait, a skip
  list (starts with stock playerbots' status texts), a voice chosen per person, mute.
