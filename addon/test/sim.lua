-- Run the add-on against a stubbed client: chat events in, engine calls out. lua5.1 sim.lua (from addon/test)
local spoken, now, cvars = {}, 100, { Sound_EnableAllSound = "1", Sound_EnableSoundWhenGameIsInBG = "1", Sound_MasterVolume = "0.8" }
local speaking = nil
CompanionVoiceEngine = {
  Speak = function(ref, text, vol) speaking = #spoken + 1; spoken[#spoken + 1] = { ref = ref, text = text, vol = vol }; return speaking end,
  IsSpeaking = function() return speaking end, Stop = function() speaking = nil end,
  SetVolume = function() end, Status = function() return "ready" end }
LivingVoices = { IsPlaying = function() return nil end, IsForeground = function() return 1 end }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("[chat] " .. m) end }
function GetTime() return now end
function GetRealmName() return "Living Azeroth" end
function GetCVar(k) return cvars[k] end
function UnitName(u) return u == "player" and "Me" or (u == "party1" and "Brogg" or nil) end
function UnitExists(u) return u == "party1" end
function UnitRace(u) return u == "party1" and "Orc" or "Human", u == "party1" and "Orc" or "Human" end
function UnitSex(u) return u == "party1" and 2 or 3 end
function GetPlayerInfoByGUID(g) if g == "0x01" then return "Mage", "MAGE", "Night Elf", "NightElf", 3, "Lyra" end end
SlashCmdList = {}
local frame
-- a stand-in for any client frame: scripts are kept, text/checked/value are remembered, every other method is a no-op
local function stub(name)
  local o = { scripts = {}, _text = "", name = name }
  return setmetatable(o, { __index = function(t, k)
    if k == "SetScript" then return function(self, e, f) self.scripts[e] = f end
    elseif k == "GetScript" then return function(self, e) return self.scripts[e] end
    elseif k == "SetText" then return function(self, v) self._text = v end
    elseif k == "GetText" then return function(self) return self._text end
    elseif k == "SetChecked" then return function(self, v) self._checked = v end
    elseif k == "GetChecked" then return function(self) return self._checked and 1 or nil end
    elseif k == "SetValue" then return function(self, v) self._value = v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
    elseif k == "CreateFontString" then return function() return stub() end
    elseif k == "RegisterEvent" then return function() end
    end
    return function() end
  end })
end
function CreateFrame(kind, name)
  local o = stub(name)
  if name then _G[name] = o; _G[name .. "Text"] = stub(); _G[name .. "Low"] = stub(); _G[name .. "High"] = stub() end
  frame = frame or o            -- the add-on's own event frame is the first one made
  return o
end
UIParent = stub(); ChatFontNormal = {}
function InterfaceOptions_AddCategory() end
function InterfaceOptionsFrame_OpenToCategory() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText(d, t) d._text = t end
function UIDropDownMenu_Initialize(d, f) d.init = f end
local ddButtons = {}
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) ddButtons[#ddButtons + 1] = info end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetNumFriends() return 1 end
function GetFriendInfo(i) return "Kael" end
function IsInGuild() return nil end
function GuildRoster() end
function UnitAffectingCombat() return nil end
dofile("../CompanionVoice/Voices.lua"); dofile("../CompanionVoice/Pronounce.lua"); dofile("../CompanionVoice/CompanionVoice.lua"); dofile("../CompanionVoice/Options.lua")
local function ev(e, ...) frame.scripts.OnEvent(frame, e, ...) end
local function tick() frame.scripts.OnUpdate(frame, 0.2) end
ev("PLAYER_LOGIN")
-- a party orc, a whispering night elf woman (known by GUID), an unknown whisperer, my own line, a link, a stale line
ev("CHAT_MSG_PARTY", "*grins* Careful, |cff1eff00|Hitem:2589:0|h[Linen Cloth]|h|r is {skull} here!", "Brogg", "Orcish", "", "", "", 0, 0, "", 0, 1, "0x02")
-- the realm labels the next whisper as urgent (its text hash), then the line arrives
local src = io.open("../CompanionVoice/CompanionVoice.lua"):read("*a")
local fnv = loadstring(src:match("(local function xor8.-\nend\nlocal function fnv.-\nend)") .. "\nreturn fnv")()
local line = "Behind you! Move!"
ev("CHAT_MSG_WHISPER", line, "Lyra", "Common", "", "", "", 0, 0, "", 0, 2, "0x01")
ev("CHAT_MSG_ADDON", "CVOX", "urgent\t" .. fnv(line), "WHISPER", "Lyra")   -- the label after the line, before it is spoken
ev("CHAT_MSG_WHISPER", "hi there", "Stranger-OtherRealm", "Common", "", "", "", 0, 0, "", 0, 3, "0x99")
ev("CHAT_MSG_PARTY", "my own line", "Me", "Common", "", "", "", 0, 0, "", 0, 4, "0x00")
ev("CHAT_MSG_PARTY", "*She offers a small friendly smile*", "Brogg", "Orcish", "", "", "", 0, 0, "", 0, 7, "0x02")
ev("CHAT_MSG_PARTY", ":) !!", "Brogg", "Orcish", "", "", "", 0, 0, "", 0, 5, "0x02")
tick(); speaking = nil; tick(); speaking = nil
ev("CHAT_MSG_PARTY", "Waited too long.", "Brogg", "Orcish", "", "", "", 0, 0, "", 0, 6, "0x02")
now = now + 40; tick()   -- waited 40 s: dropped
for i, s in ipairs(spoken) do print(i, s.ref, ("%q"):format(s.text), s.vol) end
assert(#spoken == 2, "expected two lines spoken")
assert(spoken[1].text == "Careful, Linen Cloth is here!", spoken[1].text)
assert(spoken[1].ref:find("orc_m"), spoken[1].ref)
assert(spoken[2].ref:find("nightelf_f") and spoken[2].ref:find("_neutral"), "every line uses the neutral reference")
SlashCmdList.COMPANIONVOICE("status"); SlashCmdList.COMPANIONVOICE("test")
-- a bot's line in two quick parts, the first long: the second waits behind it and is still spoken
speaking = nil; tick(); spoken = {}; speaking = nil   -- (the /cvoice test line queued above goes first)
ev("CHAT_MSG_PARTY", "First half of a long thought, which takes a while to say aloud.", "Brogg", "Orcish", "", "", "", 0, 0, "", 0, 8, "0x02")
ev("CHAT_MSG_PARTY", "And the second half.", "Brogg", "Orcish", "", "", "", 0, 0, "", 0, 9, "0x02")
tick(); now = now + 12; tick(); speaking = nil; tick()
assert(#spoken == 2 and spoken[2].text == "And the second half.", "the second part was dropped")
for i = 1, 9 do ev("CHAT_MSG_PARTY", "Line " .. i, "Brogg", "Orcish", "", "", "", 0, 0, "", 0, 20 + i, "0x02") end
spoken = {}; speaking = nil; tick()
assert(spoken[1].text == "Line 4", "a long backlog keeps the newest six: " .. spoken[1].text)
-- on the realm: it names my group's bots; a bot's canned status whisper (no label) stays silent, its model-written
-- line (labelled) is spoken, a label that comes just after its line still counts, and a real player is always spoken
for _ = 1, 8 do speaking = nil; tick() end   -- (the backlog test's lines go first)
spoken = {}; speaking = nil
ev("CHAT_MSG_ADDON", "CVOX", "bots\tDougan,Brogg", "WHISPER", "Me")
ev("CHAT_MSG_WHISPER", "Quest Incomplete: Fargodeep Mine", "Dougan", "Common", "", "", "", 0, 0, "", 0, 30, "0x01")
tick(); now = now + 0.5; tick(); now = now + 1.5; tick()
assert(#spoken == 0, "the canned whisper was spoken")
local said = "Still haven't cleared the mine? Let's go."
ev("CHAT_MSG_WHISPER", said, "Dougan", "Common", "", "", "", 0, 0, "", 0, 31, "0x01")
tick(); now = now + 0.4
ev("CHAT_MSG_ADDON", "CVOX", "neutral\t" .. fnv(said), "WHISPER", "Dougan")
tick()
assert(#spoken == 1 and spoken[1].text == said and spoken[1].ref:find("_neutral"), "the labelled line was not spoken")
speaking = nil
ev("CHAT_MSG_WHISPER", "hey, want to group?", "Kael", "Common", "", "", "", 0, 0, "", 0, 32, "0x01")
tick()
assert(#spoken == 2 and spoken[2].text == "hey, want to group?", "a real player was not spoken")
-- a bot naming itself in a roster sent by someone else is ignored
ev("CHAT_MSG_ADDON", "CVOX", "bots\tKael", "WHISPER", "Brogg")
speaking = nil; ev("CHAT_MSG_WHISPER", "still a player", "Kael", "Common", "", "", "", 0, 0, "", 0, 33, "0x01"); tick()
assert(spoken[3] and spoken[3].text == "still a player", "a forged roster silenced a player")
-- settings: whispers off silences a whisper; friends off silences Kael (a friend); a skip-list line is silent
local db = CompanionVoiceDB
spoken = {}; speaking = nil
db.whisper = false
ev("CHAT_MSG_WHISPER", "whisper while whispers are off", "Lyra2", "Common", "", "", "", 0, 0, "", 0, 40, "0x01"); tick()
db.whisper = true; db.fromFriends = false
ev("CHAT_MSG_WHISPER", "a friend while friends are off", "Kael", "Common", "", "", "", 0, 0, "", 0, 41, "0x01"); tick()
db.fromFriends = true
ev("CHAT_MSG_WHISPER", "Quest Incompleted: Fargodeep Mine", "Stranger", "Common", "", "", "", 0, 0, "", 0, 42, "0x01"); tick()
assert(#spoken == 0, "a switched-off or skipped line was spoken: " .. tostring(spoken[1] and spoken[1].text))
-- a chosen voice wins over the drawn one, and the speed reaches the engine
db.voices["kael"] = { take = "r2_orc_f_a", variant = 2 }; db.speed = 1.2
ev("CHAT_MSG_WHISPER", "now in my chosen voice", "Kael", "Common", "", "", "", 0, 0, "", 0, 43, "0x01"); tick()
assert(spoken[1] and spoken[1].ref:find("r2_orc_f_a_2_neutral"), "the chosen voice was not used")
-- the options pages build and work against the stand-in client
CompanionVoiceOptions.scripts.OnShow(); CompanionVoiceOptionsLines.scripts.OnShow(); CompanionVoiceOptionsVoices.scripts.OnShow()
CompanionVoiceOptions.default()
assert(db.speed == 1.0 and db.fromFriends == true, "defaults were not restored")
CompanionVoiceOptionsLines.scripts.OnHide()
assert(#db.skip == #CompanionVoice.DEFAULT_SKIP, "the skip list did not survive the editor: " .. #db.skip)
assert(CompanionVoice.takeLabel("r3_nightelf_f_a") == "Night elf woman A", CompanionVoice.takeLabel("r3_nightelf_f_a"))
SlashCmdList.COMPANIONVOICE("options")
-- the pronunciation guide: respellings (a possessive keeps its ending), -shire by accent, the troll dialect
local sp = CompanionVoice.speakable
local h = sp("Meet me in Goldshire, past Dalaran's gate. The Defias are coming!", "r2_human_m_a")
assert(h == "Meet me in Goldsher, past Dahlarawn's gate. The Defy us are coming!", h)
local n = sp("Meet me in Goldshire.", "r2_orc_m_a")
assert(n == "Meet me in Goldshyre.", n)
local t = sp("The thing is, they are bringing them to Dalaran with nothing.", "r2_troll_m_a")
assert(t == "De thing is, dey are bringin' dem to Dahlarawn wit nothin'.", t)
assert(sp("Ahn'Qiraj", "r2_human_f_b") == "On keerahzh", sp("Ahn'Qiraj", "r2_human_f_b"))
print("sim ok")
