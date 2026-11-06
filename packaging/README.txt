COMPANION VOICE -- party and whisper chat spoken aloud, for World of Warcraft 3.3.5a
=====================================================================================
Party and whisper chat is read aloud on your own computer, each speaker in a voice that fits their race and sex
(40 designed voices, 1-4 per race and sex, each in 3 pitch variants, so a party rarely has two alike). Made for
servers with talking playerbots, but it voices players too. /say, yell and channels are never spoken.

Needs: 64-bit Windows (Wine is untested), the 3.3.5a (12340) client, and about 600 MB of free memory while it talks.
Speech is made on your CPU, a little behind the text (often under a second).

Install (keep the game closed):
 1. Copy everything in this folder into your World of Warcraft folder, next to Wow.exe: LivingVoices.dll,
    LivingVoicesPatcher.exe, and the Interface folder (it merges with yours; the add-on lands in
    Interface\AddOns\CompanionVoice -- do not rename that folder).
 2. Double-click LivingVoicesPatcher.exe. It lets Wow.exe load the engine and keeps the original as Wow.exe.stock.
    (No Windows? python3 patch_wowexe.py Wow.exe does the same.) Already have Living Voices, the quest voice-over?
    Then Wow.exe is already patched: skip this step, and keep whichever LivingVoices.dll is newer (0.5 or later
    is needed here).
 3. Start the game. Type /cvoice test in chat to hear a voice.

Settings: Interface -> AddOns -> Companion Voice, or /cvoice. Which channels, whose lines (companions only, or
everyone), in combat or not, volume, speed, lines never to speak, and a chosen voice per person.
 /cvoice on | off | volume 0-100 | speed 0.7-1.5 | mute <name> | unmute <name> | stop | test | status

On a server running the optional mod-companion-voice module, only the lines a bot's language model wrote are spoken
and a bot's own status whispers ("Quest Incompleted: ...") stay silent. Elsewhere a skip list in the settings does
that job.

Undo: run LivingVoicesPatcher.exe again and answer y (unless Living Voices uses it too), then delete
Interface\AddOns\CompanionVoice and LivingVoices.dll.

Trouble:
 - "the client patch is missing": LivingVoices.dll is not next to Wow.exe, Wow.exe is not the patched one, or the
   DLL is older than 0.5.
 - Silence or "the speech engine stopped": CompanionVoice.log next to Wow.exe says what the engine saw.

Source, issues and the server module: https://github.com/Crono141/CompanionVoice
A fan work: not affiliated with, endorsed by or sponsored by Blizzard Entertainment. LICENSES.txt and
THIRD_PARTY.txt say what is whose.
