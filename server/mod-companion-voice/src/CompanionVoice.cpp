// mod-companion-voice: the realm side of the Companion Voice mod (~/Projects/CompanionVoice). Two hidden addon
// messages (prefix "CVOX") to real players' clients:
//   "<style>\t<FNV-1a 32 of the line's text>", from the bot, for every party or whisper line the LLM chat bridge
//       queues (llm_chatter_messages): how it sounds spoken aloud (speech_style: urgent, amused, weary; NULL is
//       neutral). The add-on speaks a line in its style; and a bot's line WITHOUT a label is one the model did not
//       write (playerbots' "Quest Incomplete: ..." status whispers), so it is not spoken.
//   "bots\t<Name,Name,...>", from the player to themselves, the bots in their group: sent when it changes and every
//       minute, so the add-on knows whose unlabelled lines to leave silent.
// Nothing else reads these.
//
// It only reads the bridge's table and shares nothing with any other module. Without the column (the bridge's
// characters update 20261105_speech_style not applied) it logs once and stays idle.

#include "Chat.h"
#include "Config.h"
#include "DatabaseEnv.h"
#include "Group.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#include <unordered_map>

namespace
{
    char const* const ADDON_PREFIX = "CVOX";

    struct Config
    {
        bool enable = true;
        uint32 pollMs = 500;
    } cfg;

    uint32 g_lastId = 0;        // the newest line already handled
    bool g_started = false;     // g_lastId read: lines queued before the server started are not labelled
    bool g_idle = false;        // no speech_style column: nothing to do until the next config reload
    uint32 g_timer = 0;

    uint32 Fnv1a(std::string const& s)    // the add-on hashes the chat line the same way
    {
        uint32 h = 2166136261u;
        for (unsigned char c : s) { h ^= c; h *= 16777619u; }
        return h;
    }

    bool Hears(Player* p)                 // a player at a real client (bots never get these)
    {
        return p && p->IsInWorld() && p->GetSession() && !p->GetSession()->IsBot();
    }

    void Send(Player* bot, Player* to, std::string const& wire)
    {
        WorldPacket data;
        ChatHandler::BuildChatPacket(data, CHAT_MSG_WHISPER, LANG_ADDON, bot, to, wire);
        to->SendDirectMessage(&data);
    }

    bool Start()
    {
        QueryResult has = CharacterDatabase.Query(
            "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() "
            "AND TABLE_NAME = 'llm_chatter_messages' AND COLUMN_NAME = 'speech_style'");
        if (!has || !has->Fetch()[0].Get<uint64>())
        {
            LOG_INFO("module", "mod-companion-voice: llm_chatter_messages has no speech_style column; idle");
            g_idle = true;
            return false;
        }
        QueryResult top = CharacterDatabase.Query("SELECT COALESCE(MAX(id), 0) FROM llm_chatter_messages");
        g_lastId = top ? top->Fetch()[0].Get<uint32>() : 0;
        g_started = true;
        LOG_INFO("module", "mod-companion-voice: sending speech styles from line {} on", g_lastId + 1);
        return true;
    }

    void Poll()
    {
        if (!g_started && !Start())
            return;
        QueryResult r = CharacterDatabase.Query(
            "SELECT id, bot_guid, channel, player_guid, message, speech_style FROM llm_chatter_messages "
            "WHERE id > {} AND channel IN ('party', 'whisper') ORDER BY id LIMIT 100",
            g_lastId);
        if (!r)
            return;
        do
        {
            Field* f = r->Fetch();
            g_lastId = f[0].Get<uint32>();
            std::string channel = f[2].Get<std::string>(), message = f[4].Get<std::string>();
            std::string style = f[5].IsNull() ? "neutral" : f[5].Get<std::string>();
            if (style != "urgent" && style != "amused" && style != "weary")
                style = "neutral";
            Player* bot = ObjectAccessor::FindPlayer(ObjectGuid::Create<HighGuid::Player>(f[1].Get<uint32>()));
            if (!bot)
                continue;
            std::string wire = std::string(ADDON_PREFIX) + "\t" + style + "\t" + std::to_string(Fnv1a(message));
            if (channel == "whisper")
            {
                Player* to = ObjectAccessor::FindPlayer(ObjectGuid::Create<HighGuid::Player>(f[3].Get<uint32>()));
                if (to != bot && Hears(to))
                    Send(bot, to, wire);
            }
            else if (Group* group = bot->GetGroup())
            {
                for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
                {
                    Player* m = ref->GetSource();
                    if (m != bot && Hears(m))
                        Send(bot, m, wire);
                }
            }
        } while (r->NextRow());
    }
}

namespace
{
    // the bots in each real player's group, sent when it changes and every minute (a /reload forgets nothing that
    // matters: the add-on keeps the names it has learned)
    std::unordered_map<uint32, std::pair<std::string, uint32>> g_rosters;   // player guid -> (names, ms since sent)
    uint32 g_rosterTimer = 0;

    void Rosters(uint32 elapsed)
    {
        std::unordered_map<uint32, std::pair<std::string, uint32>> next;
        for (auto const& [guid, player] : ObjectAccessor::GetPlayers())
        {
            if (!Hears(player))
                continue;
            Group* group = player->GetGroup();
            if (!group)
                continue;
            std::string names;
            for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            {
                Player* m = ref->GetSource();
                if (m && m != player && m->GetSession() && m->GetSession()->IsBot())
                    names += (names.empty() ? "" : ",") + m->GetName();
            }
            if (names.empty())
                continue;
            uint32 key = player->GetGUID().GetCounter();
            auto old = g_rosters.find(key);
            uint32 since = old == g_rosters.end() ? 0 : old->second.second + elapsed;
            bool send = old == g_rosters.end() || old->second.first != names || since >= 60000;
            if (send)
            {
                Send(player, player, std::string(ADDON_PREFIX) + "\tbots\t" + names.substr(0, 200));
                since = 0;
            }
            next[key] = {names, since};
        }
        g_rosters.swap(next);   // players who left or logged out drop out
    }
}

class companion_voice_world : public WorldScript
{
public:
    companion_voice_world() : WorldScript("companion_voice_world", { WORLDHOOK_ON_AFTER_CONFIG_LOAD, WORLDHOOK_ON_UPDATE }) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        cfg.enable = sConfigMgr->GetOption<bool>("CompanionVoice.Enable", true);
        cfg.pollMs = std::max<uint32>(250, sConfigMgr->GetOption<uint32>("CompanionVoice.PollMs", 500));
        g_idle = false;   // look for the column again (the update may have been applied since)
    }

    void OnUpdate(uint32 diff) override
    {
        if (!cfg.enable || g_idle)
            return;
        g_timer += diff;
        g_rosterTimer += diff;
        if (g_rosterTimer >= 5000)
        {
            Rosters(g_rosterTimer);
            g_rosterTimer = 0;
        }
        if (g_timer < cfg.pollMs)
            return;
        g_timer = 0;
        Poll();
    }
};

void AddCompanionVoiceScripts()
{
    new companion_voice_world();
}
