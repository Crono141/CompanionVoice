# mod-companion-voice

The realm side of Companion Voice. It sends each bot party or whisper line's speech style (urgent, amused, weary)
to the real players who will hear it, as a hidden addon message (prefix `CVOX`), so the CompanionVoice add-on can
speak the line that way. The style comes from the LLM chat bridge (`llm_chatter_messages.speech_style`, added by
mod-llm-chatter's characters update `20261105_speech_style.sql`). This module only reads that table. It needs a
core with `WorldSession::IsBot()` (the playerbots core), so that bots never receive the labels.

Config: `conf/mod_companion_voice.conf.dist` (`CompanionVoice.Enable`, `CompanionVoice.PollMs`).
Built into the realm's image from `WoW-LLM-Bots/modules/mod-companion-voice`, a symlink to this folder.
