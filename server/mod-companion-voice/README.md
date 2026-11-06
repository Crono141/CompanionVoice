# mod-companion-voice

The realm side of Companion Voice, and optional. It tells players' CompanionVoice add-ons which party and whisper
lines a bot's language model wrote (labels on every line the LLM chat bridge queues in `llm_chatter_messages`) and
which group members are bots, so a bot's own status text ("Quest Incompleted: ...") is not spoken aloud. Without
it, the add-on's skip list does the same job by text. It only reads the bridge's table. It needs a core with
`WorldSession::IsBot()` (the playerbots core), so that bots never receive the messages.

Config: `conf/mod_companion_voice.conf.dist` (`CompanionVoice.Enable`, `CompanionVoice.PollMs`).
Install like any AzerothCore module: copy or link this folder into `modules/` and rebuild the worldserver.
