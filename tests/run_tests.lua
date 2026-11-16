-- Out-of-game tests for Rallyhorn. Run from the folder that holds Rallyhorn/:
--   texlua tests/run_tests.lua
package.path = "tests/?.lua;" .. package.path
dofile("tests/wowstub.lua")
math.randomseed(7)

local passed, failed = 0, 0
local current

local function test(name, fn)
    current = name
    local ok, err = pcall(fn)
    if ok and #ERRORS > 0 then
        ok, err = false, "addon error: " .. ERRORS[1]
    end
    if ok then
        passed = passed + 1
        print("  ok   " .. name)
    else
        failed = failed + 1
        print("  FAIL " .. name .. "\n       " .. tostring(err))
    end
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(v, msg)
    if not v then
        error(msg or "expected truthy", 2)
    end
end

local function falsy(v, msg)
    if v then
        error((msg or "expected falsy") .. " (got " .. tostring(v) .. ")", 2)
    end
end

local function sentTo(channel)
    local out = {}
    for _, m in ipairs(SENT) do
        if m.channel == channel then
            out[#out + 1] = m
        end
    end
    return out
end

---------------------------------------------------------------------------
print("Data")
---------------------------------------------------------------------------

test("every buff definition validates", function()
    local ns = boot()
    for _, b in ipairs(ns.BUFFS) do
        local problems = ns.ValidateBuff(b)
        eq(#problems, 0, b.key .. " problems: " .. table.concat(problems, ","))
    end
    eq(#ns.ValidateBuff(ns.STANDIN), 0, "stand-in problems")
end)

test("unverified values are flagged", function()
    local ns = boot()
    -- Only buffs seen in WoW Forever may be marked verified.
    local confirmed = { rend = true }
    for _, b in ipairs(ns.BUFFS) do
        eq(b.verified, confirmed[b.key] == true, b.key .. ".verified")
    end
end)

test("validator rejects bad entries", function()
    local ns = boot()
    local bad = { key = "bad key!", name = "x", kind = "drop", duration = 0, faction = "Elves",
        triggers = { { npc = {}, all = {}, delay = 500 } } }
    truthy(#ns.ValidateBuff(bad) >= 5, "expected several problems")
end)

test("stand-in only exists when enabled", function()
    local ns = boot()
    falsy(ns.GetBuff("battleshout"), "stand-in present by default")
    ns.SetSetting("standin", true)
    truthy(ns.GetBuff("battleshout"), "stand-in missing after enabling")
    ns.SetSetting("standin", false)
    falsy(ns.GetBuff("battleshout"), "stand-in still present")
end)

---------------------------------------------------------------------------
print("Engine")
---------------------------------------------------------------------------

test("records a drop and walks through active -> cooldown -> ready", function()
    local ns = boot()
    local E = ns.Engine
    local now = ns.Now()
    local ok, reason = E:RecordDrop("ony_horde", now, "yell", "Overlord Runthak")
    truthy(ok, reason)
    eq(reason, "new")
    local st = E:GetStatus("ony_horde", now + 60)
    eq(st.state, "active")
    eq(st.remaining, 7200 - 60, "remaining")
    st = E:GetStatus("ony_horde", now + 7200 + 10)
    eq(st.state, "cooldown")
    eq(st.readyIn, 21600 - 7210, "readyIn")
    st = E:GetStatus("ony_horde", now + 21600 + 1)
    eq(st.state, "ready")
    eq(E:GetStatus("ony_alliance").state, "unknown")
end)

test("buff without a known cooldown expires instead of becoming ready", function()
    local ns = boot()
    local now = ns.Now()
    ns.Engine:RecordDrop("rend", now, "yell")
    eq(ns.Engine:GetStatus("rend", now + 3601).state, "expired")
end)

test("announce estimate shows as incoming, exact yell refines it", function()
    local ns = boot()
    local E = ns.Engine
    local now = ns.Now()
    local ok, reason = E:RecordDrop("ony_horde", now + 14, "announce")
    truthy(ok)
    local st = E:GetStatus("ony_horde", now)
    eq(st.state, "incoming")
    eq(st.eta, 14)
    ok, reason = E:RecordDrop("ony_horde", now + 12, "yell")
    eq(reason, "refined")
    eq(E:GetRecord("ony_horde").ts, now + 12)
    ok, reason = E:RecordDrop("ony_horde", now + 13, "sync")
    eq(reason, "duplicate", "lower rank must not overwrite")
    eq(E:GetRecord("ony_horde").ts, now + 12)
end)

test("rejects unknown buffs, bad times, bad sources, far future and stale", function()
    local ns = boot()
    local E = ns.Engine
    local now = ns.Now()
    eq(select(2, E:RecordDrop("nope", now, "yell")), "unknown-buff")
    eq(select(2, E:RecordDrop("rend", "soon", "yell")), "bad-time")
    eq(select(2, E:RecordDrop("rend", 0 / 0, "yell")), "bad-time")
    eq(select(2, E:RecordDrop("rend", now, "magic")), "bad-source")
    eq(select(2, E:RecordDrop("rend", now + 301, "sync")), "future")
    eq(select(2, E:RecordDrop("rend", now - 86401, "sync")), "too-old")
    truthy(E:RecordDrop("rend", now + 299, "sync"), "5 min ahead is allowed")
end)

test("older reports go to history; a newer drop pushes the old one there", function()
    local ns = boot()
    local E = ns.Engine
    local now = ns.Now()
    E:RecordDrop("ony_horde", now - 30000, "sync", "A")
    local ok, reason = E:RecordDrop("ony_horde", now - 60000, "sync", "B")
    eq(reason, "older")
    eq(E:GetRecord("ony_horde").ts, now - 30000)
    ok, reason = E:RecordDrop("ony_horde", now, "yell")
    eq(reason, "new")
    local history = ns.db.history.ony_horde
    eq(#history, 2, "history size")
    eq(history[1].ts, now - 30000, "newest first")
    for i = 1, 15 do
        E:RecordDrop("rend", now - 80000 + i * 1000, "sync")
    end
    truthy(#ns.db.history.rend <= E.MAX_HISTORY, "history capped")
end)

test("personal buffs are never accepted from sync or yells", function()
    local ns = boot()
    local now = ns.Now()
    eq(select(2, ns.Engine:RecordDrop("resist_fire", now, "sync")), "personal")
    truthy(ns.Engine:RecordDrop("resist_fire", now, "aura"))
end)

test("snapshot shares drop buffs only, no tests, no personal", function()
    local ns = boot()
    local now = ns.Now()
    ns.SetSetting("standin", true)
    ns.Engine:RecordDrop("ony_horde", now, "yell")
    ns.Engine:RecordDrop("rend", now, "test")
    ns.Engine:RecordDrop("resist_fire", now, "aura")
    ns.Engine:RecordDrop("battleshout", now, "aura")
    local snap = ns.Engine:Snapshot(now)
    eq(#snap, 1, "snapshot size")
    eq(snap[1].key, "ony_horde")
end)

test("verified cooldown blocks impossible shared drops", function()
    local ns = boot()
    local now = ns.Now()
    local buff = ns.GetBuff("ony_horde")
    buff.verified = true
    ns.Engine:RecordDrop("ony_horde", now - 3600, "yell")
    eq(select(2, ns.Engine:RecordDrop("ony_horde", now, "sync")), "cooldown-conflict")
    truthy(ns.Engine:RecordDrop("ony_horde", now, "yell"), "own yell still wins")
    buff.verified = false
end)

test("Rend drops a minute and a half apart stay separate", function()
    -- Seen in Forever on Nov 16, 2026: drops at 14:23:56 and 14:25:32 (96 s apart).
    local ns = boot()
    local E = ns.Engine
    local now = ns.Now()
    E:RecordDrop("rend", now - 96, "aura")
    local ok, reason = E:RecordDrop("rend", now, "aura")
    eq(reason, "new")
    eq(E:GetRecord("rend").ts, now)
    eq(ns.db.history.rend[1].ts, now - 96, "earlier drop kept in history")
    -- reports of the same drop a few seconds apart are still one drop
    ok, reason = E:RecordDrop("rend", now + 8, "yell")
    eq(reason, "duplicate")
end)

test("a heard drop confirmed by your buff says both", function()
    local ns = boot()
    local E = ns.Engine
    local now = ns.Now()
    E:RecordDrop("rend", now + 6, "announce", "Thrall")
    E:RecordDrop("rend", now + 1, "yell", "Thrall")
    local ok, reason = E:RecordDrop("rend", now + 1, "aura")
    eq(reason, "refined")
    local rec = E:GetRecord("rend")
    eq(rec.source, "aura")
    eq(rec.heard, true)
    local _, detail = ns.UI.StatusText(E:GetStatus("rend", now + 60))
    truthy(detail:find("heard + your buff", 1, true), detail)
end)

test("a yell heard after your buff still marks the drop as heard", function()
    local ns = boot()
    local E = ns.Engine
    local now = ns.Now()
    E:RecordDrop("rend", now, "aura")
    local _, detail = ns.UI.StatusText(E:GetStatus("rend", now + 1))
    truthy(detail:find("(your buff)", 1, true), detail)
    local ok, reason = E:RecordDrop("rend", now + 2, "yell", "Thrall")
    eq(reason, "duplicate")
    eq(E:GetRecord("rend").ts, now, "the buff's exact time is kept")
    _, detail = ns.UI.StatusText(E:GetStatus("rend", now + 3))
    truthy(detail:find("heard + your buff", 1, true), detail)
end)

test("a drop only seen on your buff is not marked heard", function()
    local ns = boot()
    local now = ns.Now()
    ns.Engine:RecordDrop("rend", now, "aura")
    eq(ns.Engine:GetRecord("rend").heard, nil)
    ns.Engine:RecordDrop("rend", now, "sync")
    eq(ns.Engine:GetRecord("rend").heard, nil, "a shared report is not hearing it")
end)

test("observed aura duration overrides the table", function()
    local ns = boot()
    local now = ns.Now()
    ns.Engine:RecordDrop("rend", now, "aura", nil, { duration = 1800 })
    eq(ns.Engine:GetStatus("rend", now + 1801).state, "expired")
end)

---------------------------------------------------------------------------
print("Matcher")
---------------------------------------------------------------------------

local function keys(matches)
    local out = {}
    for _, m in ipairs(matches) do
        out[#out + 1] = m.buff.key .. ":" .. (m.trigger.stage or "drop")
    end
    return table.concat(out, ",")
end

test("matches NPC + fragments, picks the right stage", function()
    local ns = boot()
    local M = ns.Matcher
    eq(keys(M.Match("Overlord Runthak", "People of the Horde! ONYXIA has been slain!", "Orgrimmar", "YELL")), "ony_horde:announce")
    eq(keys(M.Match("Overlord Runthak", "Be lifted by the rallying cry of your dragon slayers!", "Orgrimmar", "YELL")), "ony_horde:drop")
    eq(keys(M.Match("  overlord runthak ", "Rallying-Cry!", nil, "YELL")), "ony_horde:drop")
    eq(keys(M.Match("Major Mattingly", "Onyxia is dead.", "Stormwind City", "YELL")), "ony_alliance:announce")
    eq(keys(M.Match("Thrall", "The false Warchief, Rend Blackhand, has fallen!", "Orgrimmar", "YELL")), "rend:announce")
end)

test("Thrall's real Forever yells match Rend", function()
    -- Captured in Orgrimmar on Nov 16, 2026.
    local ns = boot()
    local M = ns.Matcher
    eq(keys(M.Match("Thrall", "Honor your heroes! On this day, they have dealt a great blow against one of our most hated enemies! The false Warchief, Rend Blackhand, has fallen!", "Orgrimmar", "YELL")), "rend:announce")
    eq(keys(M.Match("Thrall", "Be bathed in my power! Drink in my might! Battle for the glory of the Horde!", "Orgrimmar", "YELL")), "rend:drop")
end)

test("wrong NPC, wrong chat type or missing words do not match", function()
    local ns = boot()
    local M = ns.Matcher
    eq(#M.Match("Some Guard", "Onyxia has been slain!", "Orgrimmar", "YELL"), 0)
    eq(#M.Match("Overlord Runthak", "Onyxia has been slain!", "Orgrimmar", "SAY"), 0)
    eq(#M.Match("Thrall", "Rend is gone", "Orgrimmar", "YELL"), 0)
    eq(#M.Match(nil, "Onyxia", "Orgrimmar", "YELL"), 0)
end)

test("fragments match whole words only", function()
    local ns = boot()
    local buff = { key = "wb", triggers = { { npc = { "Thrall" }, all = { "rend" } } } }
    -- run through the same normalisation as the index
    ns.BUFFS[#ns.BUFFS + 1] = { key = "wb", name = "x", label = "x", faction = "Both", kind = "drop",
        duration = 60, triggers = buff.triggers }
    ns.BuildBuffIndex()
    local M = ns.Matcher
    eq(#M.Match("Thrall", "Never surrender!", nil, "YELL"), 0, "surrender")
    eq(keys(M.Match("Thrall", "Rend's head!", nil, "YELL")), "wb:drop")
    table.remove(ns.BUFFS)
    ns.BuildBuffIndex()
end)

test("zone filter applies only when the zone is known", function()
    local ns = boot()
    ns.BUFFS[#ns.BUFFS + 1] = { key = "zoned", name = "x", label = "x", faction = "Both", kind = "drop",
        duration = 60, triggers = { { npc = { "Herald" }, all = { "rejoice" }, zones = { "Orgrimmar" } } } }
    ns.BuildBuffIndex()
    local M = ns.Matcher
    eq(#M.Match("Herald", "Rejoice!", "Stormwind City", "YELL"), 0)
    eq(#M.Match("Herald", "Rejoice!", "orgrimmar", "YELL"), 1)
    eq(#M.Match("Herald", "Rejoice!", nil, "YELL"), 1)
    table.remove(ns.BUFFS)
    ns.BuildBuffIndex()
end)

test("colour codes are stripped, secret text is skipped safely", function()
    local ns = boot()
    local M = ns.Matcher
    eq(keys(M.Match("Overlord Runthak", "|cffff0000Onyxia|r falls", nil, "YELL")), "ony_horde:announce")
    eq(#M.Match("Overlord Runthak", makeSecret(), nil, "YELL"), 0)
    eq(#M.Match(makeSecret(), "Onyxia", nil, "YELL"), 0)
end)

test("SampleLine produces a line its own trigger matches", function()
    local ns = boot()
    for _, buff in ipairs(ns.buffList) do
        for _, trigger in ipairs(buff.triggers) do
            local text, npc = ns.Matcher.SampleLine(trigger)
            local found = false
            for _, m in ipairs(ns.Matcher.Match(npc, text, nil, trigger._chat == "ANY" and "YELL" or trigger._chat)) do
                if m.buff == buff then
                    found = true
                end
            end
            truthy(found, buff.key .. " sample line did not match: " .. text)
        end
    end
end)

---------------------------------------------------------------------------
print("Sync codec")
---------------------------------------------------------------------------

test("drop and query round-trip", function()
    local ns = boot()
    local S = ns.Sync
    local msg = S.EncodeDrop("ony_horde", 1800000123)
    eq(msg, "1:D:ony_horde:1800000123")
    local d = S.Decode(msg)
    eq(d.type, "D")
    eq(d.key, "ony_horde")
    eq(d.ts, 1800000123)
    eq(d.test, false)
    d = S.Decode(S.EncodeDrop("battleshout", 5, true))
    eq(d.test, true)
    local q = S.Decode(S.EncodeQuery("0.1.0"))
    eq(q.type, "Q")
    eq(q.version, "0.1.0")
    eq(S.Decode(S.EncodeQuery("1.0 beta|x")).version, "1.0betax")
    eq(S.Decode("1:Q:").version, nil)
    eq(S.EncodeDrop("bad key", 1), nil)
end)

test("state messages are chunked under the size limit and decode back", function()
    local ns = boot()
    local S = ns.Sync
    local entries = {}
    for i = 1, 45 do
        entries[#entries + 1] = { key = string.format("buff_with_a_long_name_%02d", i), ts = 1800000000 + i }
    end
    local msgs = S.EncodeState(entries)
    truthy(#msgs >= 3, "expected several chunks")
    local back = {}
    for _, m in ipairs(msgs) do
        truthy(#m <= 250, "chunk too long: " .. #m)
        local d, err = S.Decode(m)
        truthy(d, err)
        eq(d.type, "S")
        for _, e in ipairs(d.entries) do
            back[#back + 1] = e
        end
    end
    eq(#back, 45)
    eq(back[45].key, "buff_with_a_long_name_45")
    eq(back[45].ts, 1800000045)
end)

test("malformed and foreign messages are rejected", function()
    local ns = boot()
    local S = ns.Sync
    local cases = {
        { nil, "type" }, { "", "length" }, { string.rep("1", 256), "length" },
        { "x:D:a:1", "version" }, { "0:D:a:1", "version" }, { "99999:D:a:1", "version" },
        { "1:D:bad-key:1", "key" }, { "1:D:" .. string.rep("k", 33) .. ":1", "key" },
        { "1:D:rend:12a", "time" }, { "1:D:rend:1234567890123", "time" }, { "1:D:rend", "time" },
        { "1:Z:rend:1", "kind" }, { "1:S:", "empty" }, { "1:S:rend=1,ony", "pair" },
        { "1:S:rend=-5", "pair" },
    }
    for _, c in ipairs(cases) do
        local d, err = S.Decode(c[1])
        eq(d, nil, "decoded " .. tostring(c[1]))
        eq(err, c[2], "reason for " .. tostring(c[1]))
    end
    local d, err, v = S.Decode("2:D:rend:1")
    eq(err, "newer")
    eq(v, 2)
end)

test("version comparison", function()
    local ns = boot()
    local C = ns.Sync.CompareVersions
    eq(C("0.1.0", "0.1.0"), 0)
    eq(C("0.2.0", "0.1.9"), 1)
    eq(C("1.2.9", "1.2.10"), -1)
    eq(C("1.0", "1.0.0"), 0)
end)

---------------------------------------------------------------------------
print("Sync transport")
---------------------------------------------------------------------------

test("a heard yell is shared once with guild and party after it lands", function()
    local ns = boot({ fake = { group = true } })
    fireEvent("CHAT_MSG_MONSTER_YELL", "Onyxia has been slain!", "Overlord Runthak")
    eq(#SENT, 0, "nothing before the buff lands")
    advance(5)
    fireEvent("CHAT_MSG_MONSTER_YELL", "Be lifted by the rallying cry!", "Overlord Runthak")
    advance(20)
    eq(#sentTo("GUILD"), 1, "guild messages")
    eq(#sentTo("PARTY"), 1, "party messages")
    local d = ns.Sync.Decode(SENT[1].text)
    eq(d.key, "ony_horde")
    eq(d.ts, ns.Engine:GetRecord("ony_horde").ts)
    eq(SENT[1].prefix, "Rallyhorn")
    truthy(SENT[2].at - SENT[1].at >= ns.Sync.SEND_INTERVAL, "messages are spaced out")
end)

test("nothing is sent from inside an instance; held messages go out on return", function()
    local ns = boot()
    FAKE.inInstance, FAKE.instanceType = true, "party"
    ns.Engine:RecordDrop("rend", ns.Now(), "yell")
    advance(30)
    eq(#SENT, 0, "sent from an instance")
    FAKE.inInstance, FAKE.instanceType = false, "none"
    fireEvent("PLAYER_ENTERING_WORLD", false, false)
    advance(10)
    eq(#sentTo("GUILD"), 1)
end)

test("drops shared by others are recorded with the sender's two-part name", function()
    local ns = boot()
    local ts = ns.Now() - 600
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:D:ony_horde:" .. ts, "GUILD", "Bryn Holloway-Forever")
    local rec = ns.Engine:GetRecord("ony_horde")
    truthy(rec, "not recorded")
    eq(rec.source, "sync")
    eq(rec.reporter, "Bryn Holloway")
    advance(15)
    eq(#SENT, 0, "shared drops are not relayed")
end)

test("own echoes, other prefixes and whispers are ignored", function()
    local ns = boot()
    local ts = ns.Now()
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:D:rend:" .. ts, "GUILD", "Aldric Stone")
    fireEvent("CHAT_MSG_ADDON", "Other", "1:D:rend:" .. ts, "GUILD", "Bryn Holloway")
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:D:rend:" .. ts, "WHISPER", "Bryn Holloway")
    fireEvent("CHAT_MSG_ADDON", makeSecret(), makeSecret(), "GUILD", makeSecret())
    eq(ns.Engine:GetRecord("rend"), nil)
end)

test("our own query echoed under a different name format is ignored", function()
    local ns = boot()
    ns.Engine:RecordDrop("ony_horde", ns.Now() - 100, "yell")
    advance(70) -- past the query cooldown
    SENT = {}
    eq(ns.Sync:Query(nil, true), 1, "query queued")
    advance(3)
    eq(#SENT, 1)
    local mine = SENT[1].text
    truthy(mine:match("^1:Q:%d+%.%d+%.%d+:%w+$"), "query format: " .. mine)
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", mine, "GUILD", "Aldric")
    advance(10)
    eq(#SENT, 1, "answered our own query")
end)

test("a flood from one sender is cut off", function()
    local ns = boot()
    for i = 1, 30 do
        fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:Q:0.1.0", "GUILD", "Spammy Mcspam")
    end
    eq(ns.Sync.stats.received, ns.Sync.SENDER_LIMIT)
end)

test("queries get one reply; a faster reply from someone else suppresses ours", function()
    local ns = boot()
    ns.Engine:RecordDrop("ony_horde", ns.Now() - 100, "yell")
    advance(15)
    SENT = {}
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:Q:0.1.0", "GUILD", "Bryn Holloway")
    advance(10)
    eq(#SENT, 1, "one reply")
    eq(ns.Sync.Decode(SENT[1].text).type, "S")
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:Q:0.1.0", "GUILD", "Cora Vale")
    advance(10)
    eq(#SENT, 1, "reply cooldown")
    advance(40)
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:Q:0.1.0", "GUILD", "Dain Ash")
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:S:ony_horde=" .. (ns.Now() - 100), "GUILD", "Cora Vale")
    advance(10)
    eq(#SENT, 1, "suppressed by someone else's answer")
end)

test("someone else sharing the same drop first silences us", function()
    local ns = boot()
    local now = ns.Now()
    fireEvent("CHAT_MSG_MONSTER_YELL", "Be lifted by the rallying cry!", "Overlord Runthak")
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:D:ony_horde:" .. (now + 1), "GUILD", "Bryn Holloway")
    advance(20)
    eq(#SENT, 0)
end)

test("test drops stay local unless shared, and then go to the group only", function()
    local ns = boot({ fake = { group = true } })
    slash("test rend 5")
    advance(15)
    eq(#SENT, 0, "unshared test drop was sent")
    slash("clear rend")
    slash("test rend share")
    advance(15)
    eq(#sentTo("GUILD"), 0, "test drop sent to guild")
    eq(#sentTo("PARTY"), 1)
    truthy(SENT[1].text:find(":T$"), "test flag missing")
end)

test("test-flagged drops from guild are refused; from party they are labelled test", function()
    local ns = boot()
    local ts = ns.Now()
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:D:rend:" .. ts .. ":T", "GUILD", "Bryn Holloway")
    eq(ns.Engine:GetRecord("rend"), nil)
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:D:rend:" .. ts .. ":T", "PARTY", "Bryn Holloway")
    eq(ns.Engine:GetRecord("rend").source, "test")
    truthy(printed("test via Bryn Holloway"), "announcement should say test")
end)

test("throttled sends are retried, lockdown pauses sending", function()
    local ns = boot()
    FAKE.sendResult = 3
    ns.Engine:RecordDrop("rend", ns.Now(), "yell")
    advance(12)
    eq(#SENT, 0)
    eq(#ns.Sync.queue, 1, "still queued")
    FAKE.sendResult = 11
    advance(5)
    truthy(ns.Sync.lockedUntil > FAKE.game, "lockdown not noted")
    FAKE.sendResult = 0
    advance(70)
    eq(#SENT, 1, "sent after lockdown")
end)

test("turning sharing off stops sending and receiving", function()
    local ns = boot()
    slash("sync off")
    ns.Engine:RecordDrop("rend", ns.Now(), "yell")
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:D:ony_horde:" .. ns.Now(), "GUILD", "Bryn Holloway")
    advance(15)
    eq(#SENT, 0)
    eq(ns.Engine:GetRecord("ony_horde"), nil)
end)

test("a newer version is mentioned once", function()
    local ns = boot()
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:Q:0.9.0", "GUILD", "Bryn Holloway")
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:Q:0.9.1", "GUILD", "Cora Vale")
    local n = 0
    for _, line in ipairs(PRINTS) do
        if line:find("Consider updating") then
            n = n + 1
        end
    end
    eq(n, 1)
end)

test("/rhorn testyell records a test drop and shares nothing", function()
    local ns = boot({ fake = { group = true } })
    slash("testyell ony_horde")
    eq(ns.Engine:GetRecord("ony_horde").source, "test")
    advance(30)
    eq(#SENT, 0, "fake yell was shared")
end)

test("a better report replaces a later estimate or a bad shared time", function()
    local ns = boot()
    local now = ns.Now()
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:D:rend:" .. (now + 280), "GUILD", "Bryn Holloway")
    eq(ns.Engine:GetRecord("rend").ts, now + 280)
    local ok, reason = ns.Engine:RecordDrop("rend", now, "yell")
    eq(reason, "new")
    eq(ns.Engine:GetRecord("rend").ts, now)
    eq(ns.Engine:GetRecord("rend").source, "yell")
    eq(ns.db.history.rend, nil, "bad value kept in history")
    -- but a real earlier yell never overrides a real later one
    ns.Engine:RecordDrop("ony_horde", now, "yell")
    eq(select(2, ns.Engine:RecordDrop("ony_horde", now - 200, "aura")), "older")
end)

test("leaving an instance asks for timers again (cooldown saved across reloads)", function()
    local ns = boot()
    eq(ns.db.syncState.lastQuery.GUILD ~= nil, true, "login query not recorded")
    local saved = RallyhornDB
    ns = boot({ db = saved })
    eq(#SENT, 0, "reload re-queried inside the cooldown")
    advance(400)
    FAKE.inInstance, FAKE.instanceType = true, "party"
    fireEvent("PLAYER_ENTERING_WORLD", false, false)
    advance(10)
    eq(#SENT, 0, "queried from inside an instance")
    FAKE.inInstance, FAKE.instanceType = false, "none"
    fireEvent("PLAYER_ENTERING_WORLD", false, false)
    advance(10)
    eq(#SENT, 1, "no query after leaving the instance")
    eq(ns.Sync.Decode(SENT[1].text).type, "Q")
end)

test("replies only carry what other answers left out", function()
    local ns = boot()
    local now = ns.Now()
    ns.Engine:RecordDrop("ony_horde", now - 100, "yell")
    ns.Engine:RecordDrop("rend", now - 50, "yell")
    advance(15)
    SENT = {}
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:Q:0.1.0:abc", "GUILD", "Dain Ash")
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:S:ony_horde=" .. (now - 100), "GUILD", "Cora Vale")
    advance(10)
    eq(#SENT, 1)
    local d = ns.Sync.Decode(SENT[1].text)
    eq(#d.entries, 1)
    eq(d.entries[1].key, "rend")
end)

test("a queued drop is dropped if someone shares it before it goes out", function()
    local ns = boot()
    local now = ns.Now()
    FAKE.inInstance, FAKE.instanceType = true, "party" -- hold the queue
    ns.Engine:RecordDrop("rend", now, "yell")
    advance(10)
    eq(#ns.Sync.queue, 1)
    fireEvent("CHAT_MSG_ADDON", "Rallyhorn", "1:D:rend:" .. now, "GUILD", "Bryn Holloway")
    FAKE.inInstance, FAKE.instanceType = false, "none"
    advance(10)
    eq(#SENT, 0)
end)

---------------------------------------------------------------------------
print("Detection")
---------------------------------------------------------------------------

test("yell events flow to the engine and the window", function()
    local ns = boot()
    local now = ns.Now()
    fireEvent("CHAT_MSG_MONSTER_YELL", "Onyxia has been slain!", "Overlord Runthak")
    local rec = ns.Engine:GetRecord("ony_horde")
    eq(rec.ts, now + 14)
    eq(rec.source, "announce")
    ns.UI:Refresh()
    local row = ns.UI.frame.rows[1]
    eq(row.buff.key, "ony_horde")
    truthy(row.status.text:find("Lands in"), row.status.text)
    truthy(printed("lands in"), "chat announcement")
    eq(#SOUNDS, 1, "alert sound")
end)

test("Battle Shout stand-in is picked up from the aura out of combat", function()
    local ns = boot()
    slash("standin on")
    FAKE.auras = { { spellId = 6673, name = "Battle Shout", duration = 120, expirationTime = FAKE.game + 118, auraInstanceID = 1 } }
    fireEvent("UNIT_AURA", "player", {})
    advance(1)
    local rec = ns.Engine:GetRecord("battleshout")
    truthy(rec, "no record")
    eq(rec.source, "aura")
    eq(rec.ts, ns.Now() - 3)
    eq(rec.dur, 120)
end)

test("stand-in casts are shared to the party as tests, whatever Battle Shout's length", function()
    local ns = boot({ fake = { group = true } })
    slash("standin on")
    FAKE.auras = { { spellId = 6673, name = "Battle Shout", duration = 3600, expirationTime = FAKE.game + 3600 } }
    fireEvent("UNIT_AURA", "player", {})
    advance(10)
    eq(#sentTo("PARTY"), 1)
    eq(#sentTo("GUILD"), 0)
    truthy(SENT[1].text:find("^1:D:battleshout:%d+:T$"), SENT[1].text)
end)

test("auras are not read in combat; the scan runs when combat ends", function()
    local ns = boot()
    slash("standin on")
    FAKE.combat = true
    FAKE.auras = { { spellId = 6673, name = "Battle Shout", duration = 120, expirationTime = FAKE.game + 120 } }
    fireEvent("UNIT_AURA", "player", {})
    advance(2)
    eq(ns.Engine:GetRecord("battleshout"), nil, "read in combat")
    FAKE.combat = false
    fireEvent("PLAYER_REGEN_ENABLED")
    advance(1)
    truthy(ns.Engine:GetRecord("battleshout"), "not read after combat")
end)

test("secret aura fields never raise errors", function()
    local ns = boot()
    slash("standin on")
    FAKE.auras = {
        { spellId = makeSecret(), name = makeSecret(), duration = makeSecret(), expirationTime = makeSecret() },
        makeSecret(),
    }
    fireEvent("UNIT_AURA", "player", {})
    advance(1)
    eq(ns.Engine:GetRecord("battleshout"), nil)
end)

test("an old world buff aura never starts a new shared timer", function()
    local ns = boot()
    FAKE.auras = { { spellId = 22888, name = "Rallying Cry of the Dragonslayer", duration = 7200, expirationTime = FAKE.game + 3600 } }
    fireEvent("UNIT_AURA", "player", {})
    advance(15)
    eq(ns.Engine:GetRecord("ony_horde"), nil, "stale aura created a timer")
    eq(#SENT, 0)
    -- with a matching known drop, the aura refines it
    ns.Engine:RecordDrop("ony_horde", ns.Now() - 3600 - 20, "sync")
    fireEvent("UNIT_AURA", "player", {})
    advance(1)
    eq(ns.Engine:GetRecord("ony_horde").source, "aura")
end)

test("a world buff aura with an unexpected length is tracked locally, not shared", function()
    local ns = boot()
    FAKE.auras = { { spellId = 22888, name = "Rallying Cry of the Dragonslayer", duration = 1800, expirationTime = FAKE.game + 1800 } }
    fireEvent("UNIT_AURA", "player", {})
    advance(20)
    local rec = ns.Engine:GetRecord("ony_horde")
    truthy(rec, "no local record")
    eq(rec.dur, 1800)
    eq(#SENT, 0, "shared a doubtful drop")
end)

test("a line that applies the buff wins over the heads-up trigger", function()
    local ns = boot()
    local m = ns.Matcher.Match("Overlord Runthak", "Onyxia is slain! Be lifted by the rallying cry!", nil, "YELL")
    eq(#m, 1)
    eq(m[1].trigger.stage, nil)
end)

test("aura name fallback picks the player's faction", function()
    local ns = boot({ fake = { faction = "Alliance" } })
    FAKE.auras = { { spellId = 999999, name = "Rallying Cry of the Dragonslayer", duration = 7200, expirationTime = FAKE.game + 7190 } }
    fireEvent("UNIT_AURA", "player", {})
    advance(1)
    truthy(ns.Engine:GetRecord("ony_alliance"), "alliance record missing")
    eq(ns.Engine:GetRecord("ony_horde"), nil)
end)

test("personal buffs are tracked from auras even when not fresh", function()
    local ns = boot()
    FAKE.auras = { { spellId = 15123, name = "Resist Fire", duration = 3600, expirationTime = FAKE.game + 3000 } }
    fireEvent("UNIT_AURA", "player", {})
    advance(1)
    local st = ns.Engine:GetStatus("resist_fire")
    eq(st.state, "active")
    eq(st.remaining, 3000 - 1)
    advance(15)
    eq(#SENT, 0, "personal buff was shared")
end)

test("Alliance: Might of Stormwind is picked up from your buff", function()
    local ns = boot({ fake = { faction = "Alliance" } })
    FAKE.auras = { { spellId = 1304678, name = "Might of Stormwind", duration = 3600, expirationTime = FAKE.game + 3598 } }
    fireEvent("UNIT_AURA", "player", {})
    advance(1)
    local rec = ns.Engine:GetRecord("rend_alliance")
    truthy(rec, "no record")
    eq(rec.source, "aura")
    eq(ns.Engine:GetRecord("rend"), nil, "Horde entry touched")
    eq(ns.Engine:GetStatus("rend_alliance").state, "active")
end)

test("Alliance: Might of Stormwind is matched by name when the spell ID is new", function()
    local ns = boot({ fake = { faction = "Alliance" } })
    FAKE.auras = { { spellId = 999998, name = "Might of Stormwind", duration = 3600, expirationTime = FAKE.game + 3599 } }
    fireEvent("UNIT_AURA", "player", {})
    advance(1)
    truthy(ns.Engine:GetRecord("rend_alliance"), "no record")
end)

test("Alliance window lists the Alliance buffs", function()
    local ns = boot({ fake = { faction = "Alliance" } })
    local out = {}
    for _, b in ipairs(ns.UI.visible) do
        out[#out + 1] = b.key
    end
    eq(table.concat(out, ","), "ony_alliance,rend_alliance,resist_fire,songflower")
end)

test("Herald of Thrall's version of Warchief's Blessing counts as Rend", function()
    local ns = boot()
    FAKE.auras = { { spellId = 355366, name = "Warchief's Blessing", duration = 3600, expirationTime = FAKE.game + 3599 } }
    fireEvent("UNIT_AURA", "player", {})
    advance(1)
    truthy(ns.Engine:GetRecord("rend"), "no record")
end)

---------------------------------------------------------------------------
print("Capture")
---------------------------------------------------------------------------

test("capture logs yells (deduped, capped) and new auras", function()
    local ns = boot()
    slash("capture on")
    FAKE.subzone = "Valley of Strength"
    fireEvent("CHAT_MSG_MONSTER_YELL", "For the Horde!", "Grunt Gar")
    fireEvent("CHAT_MSG_MONSTER_YELL", "For the Horde!", "Grunt Gar")
    fireEvent("CHAT_MSG_MONSTER_SAY", "Hello there.", "Grunt Gar")
    fireEvent("CHAT_MSG_MONSTER_YELL", makeSecret(), "Grunt Gar")
    local log = ns.db.capture.chat
    eq(#log, 3)
    eq(log[1].count, 2)
    eq(log[1].npc, "Grunt Gar")
    eq(log[1].zone, "Orgrimmar")
    eq(log[1].subzone, "Valley of Strength")
    eq(log[2].event, "SAY")
    eq(log[3].text, "<secret>")
    eq(log[3].secret, true)
    for i = 1, 400 do
        fireEvent("CHAT_MSG_MONSTER_YELL", "line " .. i, "Spammer")
    end
    eq(#log, ns.Capture.MAX_CHAT)
    FAKE.auras = { { spellId = 6673, name = "Battle Shout", duration = 120, expirationTime = FAKE.game + 120 } }
    fireEvent("UNIT_AURA", "player", {})
    advance(1)
    fireEvent("UNIT_AURA", "player", {})
    advance(1)
    eq(ns.db.capture.auraCount, 1)
    eq(ns.db.capture.auras[6673].name, "Battle Shout")
end)

test("matched yells are marked in the capture log", function()
    local ns = boot()
    slash("capture on")
    fireEvent("CHAT_MSG_MONSTER_YELL", "Onyxia has been slain!", "Overlord Runthak")
    eq(ns.db.capture.chat[1].matched, "ony_horde")
end)

test("nothing is captured while capture is off", function()
    local ns = boot()
    fireEvent("CHAT_MSG_MONSTER_YELL", "For the Horde!", "Grunt Gar")
    eq(#ns.db.capture.chat, 0)
end)

---------------------------------------------------------------------------
print("Saved variables, UI, slash commands")
---------------------------------------------------------------------------

test("saved timers survive a reload and old saves get new defaults", function()
    local ns = boot()
    ns.Engine:RecordDrop("ony_horde", ns.Now() - 50, "yell")
    local saved = RallyhornDB
    saved.settings.sound = nil
    ns = boot({ db = saved })
    truthy(ns.Engine:GetRecord("ony_horde"), "timer lost")
    eq(ns.db.settings.sound, true, "default restored")
end)

test("status text for every state", function()
    local ns = boot()
    local now = ns.Now()
    local states = {}
    ns.Engine:RecordDrop("ony_horde", now, "yell")
    for _, t in ipairs({ -10, 60, 7300, 21700 }) do
        local st = ns.Engine:GetStatus("ony_horde", now + t)
        local status, detail = ns.UI.StatusText(st)
        truthy(type(status) == "string" and type(detail) == "string")
        states[#states + 1] = st.state
    end
    eq(table.concat(states, ","), "incoming,active,cooldown,ready")
    eq(ns.UI.StatusText(ns.Engine:GetStatus("rend")), "|cff888888No data|r")
end)

test("window only lists the player's faction unless asked", function()
    local ns = boot()
    local function listed()
        local out = {}
        for _, b in ipairs(ns.UI.visible) do
            out[#out + 1] = b.key
        end
        return table.concat(out, ",")
    end
    eq(listed(), "ony_horde,rend,resist_fire,songflower")
    slash("faction all")
    eq(listed(), "ony_horde,ony_alliance,rend,rend_alliance,resist_fire,songflower")
    slash("buff zandalar show")
    truthy(listed():find("zandalar"))
    slash("buff rend hide")
    falsy(("," .. listed() .. ","):find(",rend,", 1, true), "rend still listed")
    truthy(("," .. listed() .. ","):find(",rend_alliance,", 1, true), "hid the wrong row")
end)

test("dragging saves the position; lock blocks dragging", function()
    local ns = boot()
    local f = ns.UI.frame
    f.scripts.OnDragStart(f)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100.4, -200.6)
    f.scripts.OnDragStop(f)
    eq(ns.db.settings.point[1], "TOPLEFT")
    eq(ns.db.settings.point[3], 100)
    slash("lock")
    f.scripts.OnDragStart(f)
    falsy(f.movingNow, "moved while locked")
    slash("hide")
    falsy(f:IsShown())
    slash("")
    truthy(f:IsShown(), "toggle")
end)

test("every slash command runs without errors", function()
    local ns = boot()
    local commands = {
        "help", "toggle", "show", "hide", "lock", "unlock", "reset", "scale 1.2", "scale 9",
        "minimap off", "minimap on", "minimap reset", "minimap maybe",
        "status", "list", "clear rend", "clear all", "clear nope", "buff rend show", "buff rend",
        "faction own", "faction", "announce off", "announce on", "sound", "sync status", "sync query",
        "sync guild off", "sync group on", "sync maybe", "test ony_horde", "test ony_horde", "test resist_fire 10",
        "test nope", "testyell ony_horde", "testyell rend", "testyell resist_fire", "standin on", "testyell battleshout",
        "standin off", "capture on", "capture show", "capture show 3", "capture stats", "capture clear", "capture off",
        "options", "debug on", "debug off", "version", "bogus",
    }
    for _, c in ipairs(commands) do
        slash(c)
    end
    advance(20)
    truthy(printed("not recorded: duplicate"), "duplicate test message")
    truthy(printed("matched 1 buff"), "testyell message")
    eq(OPENED_SETTINGS[1], 42, "settings opened")
end)

test("addon compartment callbacks work", function()
    local ns = boot()
    local shown = ns.db.settings.shown
    Rallyhorn_OnAddonCompartmentClick("Rallyhorn", "LeftButton")
    eq(ns.db.settings.shown, not shown)
    Rallyhorn_OnAddonCompartmentClick("Rallyhorn", "RightButton")
    eq(#OPENED_SETTINGS, 1)
    Rallyhorn_OnAddonCompartmentClick("Rallyhorn", { buttonName = "RightButton" })
    eq(#OPENED_SETTINGS, 2, "11.0+ table argument")
    Rallyhorn_OnAddonCompartmentEnter("Rallyhorn", UIParent)
    Rallyhorn_OnAddonCompartmentLeave("Rallyhorn", UIParent)
end)

test("minimap button: clicks, dragging around the edge, hiding", function()
    local ns = boot()
    local b = _G.RallyhornMinimapButton
    truthy(b, "button not created")
    eq(b.parent, Minimap)
    truthy(b:IsShown(), "hidden by default")
    -- default spot: 225 degrees, radius 140/2 + 10 = 80
    eq(math.floor(b.point[4] + 0.5), -57)
    eq(math.floor(b.point[5] + 0.5), -57)
    local shown = ns.db.settings.shown
    b.scripts.OnClick(b, "LeftButton")
    eq(ns.db.settings.shown, not shown, "left-click toggles the window")
    b.scripts.OnClick(b, "RightButton")
    eq(OPENED_SETTINGS[1], 42, "right-click opens settings")
    FAKE.cursorX, FAKE.cursorY = 500, 480 -- straight above the minimap centre
    b.scripts.OnDragStart(b)
    truthy(b.scripts.OnUpdate, "not following the cursor")
    b.scripts.OnUpdate(b, 0.1)
    b.scripts.OnDragStop(b)
    eq(ns.db.settings.minimapAngle, 90)
    eq(math.floor(b.point[4] + 0.5), 0)
    eq(math.floor(b.point[5] + 0.5), 80)
    eq(b.scripts.OnUpdate, nil, "still following after the drag")
    b.scripts.OnEnter(b)
    truthy(#GameTooltip.lines >= 3, "tooltip")
    slash("minimap off")
    falsy(b:IsShown(), "minimap off")
    slash("minimap reset")
    truthy(b:IsShown(), "reset shows it again")
    eq(ns.db.settings.minimapAngle, 225)
    -- the angle survives a reload
    ns.db.settings.minimapAngle = 0
    boot({ db = RallyhornDB })
    eq(math.floor(_G.RallyhornMinimapButton.point[4] + 0.5), 80)
end)

test("settings panel checkboxes write through", function()
    local ns = boot()
    for _, item in ipairs(ns.Options.ITEMS) do
        if item.key == "sound" then
            item.check:SetChecked(false)
            item.check.scripts.OnClick(item.check)
        end
    end
    eq(ns.db.settings.sound, false)
end)

test("tooltip renders for every row", function()
    local ns = boot()
    slash("faction all")
    ns.Engine:RecordDrop("ony_horde", ns.Now(), "yell")
    for _, row in ipairs(ns.UI.frame.rows) do
        if row.buff then
            row.scripts.OnEnter(row)
            truthy(#GameTooltip.lines > 2, "tooltip empty for " .. row.buff.key)
        end
    end
end)

test("Rend tooltip: confirmed, no long cooldown, heard + your buff", function()
    local ns = boot()
    local now = ns.Now()
    ns.Engine:RecordDrop("rend", now, "yell", "Thrall")
    ns.Engine:RecordDrop("rend", now, "aura", nil, { duration = 3600 })
    local row
    for _, r in ipairs(ns.UI.frame.rows) do
        if r.buff and r.buff.key == "rend" then
            row = r
        end
    end
    truthy(row, "no Rend row")
    row.scripts.OnEnter(row)
    local text = table.concat(GameTooltip.lines, "\n")
    truthy(text:find("no long cooldown", 1, true), text)
    falsy(text:find("Unverified", 1, true), "still says unverified")
    truthy(text:find("Source: heard + your buff", 1, true), text)
    falsy(row.name.text:find("*", 1, true), "row still has the unverified star")
end)

test("helpers: names, durations, open world", function()
    local ns = boot()
    eq(ns.NormalizeName("Bryn Holloway"), "Bryn Holloway")
    eq(ns.NormalizeName("Bryn Holloway-Forever"), "Bryn Holloway")
    eq(ns.NormalizeName("Mary Smith-Jones"), "Mary Smith-Jones")
    eq(ns.NormalizeName(makeSecret()), nil)
    truthy(ns.IsSelf("aldric stone"))
    falsy(ns.IsSelf("Aldric"))
    eq(ns.FormatDuration(3725), "1h 02m")
    eq(ns.FormatDuration(125), "2m 05s")
    eq(ns.FormatDuration(-4), "0s")
    truthy(ns.InOpenWorld())
    FAKE.inInstance, FAKE.instanceType = true, "raid"
    falsy(ns.InOpenWorld())
    FAKE.inInstance = makeSecret()
    falsy(ns.InOpenWorld(), "secret counts as not open world")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
