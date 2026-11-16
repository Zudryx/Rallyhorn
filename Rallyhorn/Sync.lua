-- Rallyhorn - Copyright (C) 2026 Zudryx - GPL-3.0-or-later (see LICENSE, NOTICE.md)
--
-- Sync: shares drop timers with guild and party/raid over addon messages.
--
-- Wire format (protocol 1), fields separated by ":"
--   1:D:<key>:<ts>[:T]          one drop; T marks a test drop (party/raid only)
--   1:Q:<addonVersion>:<nonce>  "what do you know?" (sent on login / joining a group)
--   1:S:<key>=<ts>,<key>=<ts>   reply to Q with everything we know
-- <key> is a buff key from Data.lua, <ts> is server epoch seconds.
-- Receivers ignore unknown buff keys, unknown message types and newer protocols.
--
-- Messages are only sent in the open world: the Midnight engine blocks addon
-- messages inside instances. Everything sent is queued and spaced out well
-- under the per-prefix allowance (10 messages, +1 per second).

local ADDON_NAME, ns = ...

local Sync = {}
ns.Sync = Sync

Sync.PROTOCOL = 1
Sync.MAX_LEN = 250
Sync.MAX_KEY_LEN = 32
Sync.MAX_STATE_ENTRIES = 20

Sync.SEND_INTERVAL = 1.5     -- seconds between our messages
Sync.MAX_QUEUE = 20
Sync.QUEUE_TTL = 600         -- drop queued messages older than this
Sync.SENDER_LIMIT = 15       -- messages accepted per sender per minute
Sync.QUERY_COOLDOWN = 60     -- per channel, for /rhorn sync query
Sync.AUTO_QUERY_COOLDOWN = 300 -- per channel, for automatic queries (login, reload, group, leaving an instance)
Sync.REPLY_COOLDOWN = 30     -- per channel
Sync.ECHO_WINDOW = 60
Sync.SHARE_JITTER = 5        -- extra random seconds before sharing a local drop

---------------------------------------------------------------------------
-- Codec (pure functions, tested out of game)
---------------------------------------------------------------------------

function Sync.ValidKey(key)
    return type(key) == "string" and #key > 0 and #key <= Sync.MAX_KEY_LEN
        and string.match(key, "^[%w_]+$") ~= nil
end

local function validTime(text)
    return type(text) == "string" and #text > 0 and #text <= 12 and string.match(text, "^%d+$") ~= nil
end

function Sync.EncodeDrop(key, ts, isTest)
    if not Sync.ValidKey(key) or type(ts) ~= "number" then
        return nil
    end
    local msg = string.format("%d:D:%s:%d", Sync.PROTOCOL, key, math.floor(ts))
    if isTest then
        msg = msg .. ":T"
    end
    return msg
end

-- The nonce makes every query unique, so the echo filter can tell our own
-- query from someone else's identical one.
function Sync.EncodeQuery(version, nonce)
    version = string.gsub(tostring(version or ""), "[^%w%.%-]", "")
    nonce = string.gsub(tostring(nonce or ""), "[^%w]", "")
    return string.format("%d:Q:%s:%s", Sync.PROTOCOL, string.sub(version, 1, 20), string.sub(nonce, 1, 8))
end

function Sync.NewNonce()
    local chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    local out = {}
    for i = 1, 6 do
        local n = math.random(1, #chars)
        out[i] = string.sub(chars, n, n)
    end
    return table.concat(out)
end

-- entries = { { key =, ts = }, ... } -> list of messages, each <= MAX_LEN
function Sync.EncodeState(entries)
    local messages = {}
    local head = string.format("%d:S:", Sync.PROTOCOL)
    local current, count = nil, 0
    for _, e in ipairs(entries or {}) do
        if Sync.ValidKey(e.key) and type(e.ts) == "number" then
            local part = e.key .. "=" .. string.format("%d", math.floor(e.ts))
            if current and #current + 1 + #part <= Sync.MAX_LEN and count < Sync.MAX_STATE_ENTRIES then
                current = current .. "," .. part
                count = count + 1
            else
                if current then
                    messages[#messages + 1] = current
                end
                current = head .. part
                count = 1
            end
        end
    end
    if current then
        messages[#messages + 1] = current
    end
    return messages
end

local function splitFields(msg)
    local fields = {}
    for field in string.gmatch(msg .. ":", "([^:]*):") do
        fields[#fields + 1] = field
    end
    return fields
end

-- Returns a message table, or nil plus a reason ("newer" comes with the version).
function Sync.Decode(msg)
    if type(msg) ~= "string" then
        return nil, "type"
    end
    if #msg == 0 or #msg > 255 then
        return nil, "length"
    end
    local f = splitFields(msg)
    if not f[1] or not string.match(f[1], "^%d+$") or #f[1] > 4 then
        return nil, "version"
    end
    local version = tonumber(f[1])
    if version > Sync.PROTOCOL then
        return nil, "newer", version
    end
    if version < 1 then
        return nil, "version"
    end
    local kind = f[2]
    if kind == "D" then
        if not Sync.ValidKey(f[3]) then
            return nil, "key"
        end
        if not validTime(f[4]) then
            return nil, "time"
        end
        return { v = version, type = "D", key = f[3], ts = tonumber(f[4]), test = (f[5] == "T") }
    elseif kind == "Q" then
        local ver = f[3]
        if ver == "" or (ver and not string.match(ver, "^[%w%.%-]+$")) then
            ver = nil
        end
        return { v = version, type = "Q", version = ver }
    elseif kind == "S" then
        local entries = {}
        for pair in string.gmatch(f[3] or "", "[^,]+") do
            local key, ts = string.match(pair, "^([%w_]+)=(%d+)$")
            if not key or not Sync.ValidKey(key) or not validTime(ts) then
                return nil, "pair"
            end
            entries[#entries + 1] = { key = key, ts = tonumber(ts) }
            if #entries > Sync.MAX_STATE_ENTRIES then
                return nil, "too-many"
            end
        end
        if #entries == 0 then
            return nil, "empty"
        end
        return { v = version, type = "S", entries = entries }
    end
    return nil, "kind"
end

-- "1.2.10" > "1.2.9"; non-numeric parts count as 0.
function Sync.CompareVersions(a, b)
    local function parts(v)
        local out = {}
        for n in string.gmatch(tostring(v or ""), "%d+") do
            out[#out + 1] = tonumber(n)
        end
        return out
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then
            return x < y and -1 or 1
        end
    end
    return 0
end

---------------------------------------------------------------------------
-- Transport
---------------------------------------------------------------------------

Sync.queue = {}
Sync.sentRecently = {}
Sync.senderLog = {}
Sync.senderCount = 0
Sync.lastBroadcast = {}
Sync.lastReply = {}
Sync.replyPending = {}
Sync.heard = {}
Sync.lockedUntil = 0
Sync.pumpScheduled = false
Sync.stats = { sent = 0, received = 0, rejected = 0, dropsAccepted = 0 }

local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

function Sync:Enabled()
    return ns.db and ns.db.settings.sync
end

function Sync:CanSend()
    if not self:Enabled() then
        return false, "disabled"
    end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        return false, "unavailable"
    end
    if not ns.InOpenWorld() then
        return false, "instance"
    end
    if ns.GameTime() < self.lockedUntil then
        return false, "lockdown"
    end
    if C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and ns.SafeBool(locked) ~= false then
            return false, "lockdown"
        end
    end
    return true
end

-- opts.guild / opts.group = false to leave that side out.
function Sync:Channels(opts)
    opts = opts or {}
    local out = {}
    local s = ns.db.settings
    if opts.guild ~= false and s.syncGuild and ns.IsInGuild() then
        out[#out + 1] = "GUILD"
    end
    if opts.group ~= false and s.syncGroup then
        if ns.IsInRaid() then
            out[#out + 1] = "RAID"
        elseif ns.IsInGroup() then
            out[#out + 1] = "PARTY"
        end
    end
    return out
end

-- drop = { key =, ts = } for drop messages, so they can be skipped at send
-- time if someone else shares the same drop while ours waits in the queue.
function Sync:Enqueue(text, channel, drop)
    if not text or not channel then
        return false
    end
    for _, item in ipairs(self.queue) do
        if item.text == text and item.channel == channel then
            return false
        end
    end
    self.queue[#self.queue + 1] = {
        text = text,
        channel = channel,
        at = ns.GameTime(),
        key = drop and drop.key,
        ts = drop and drop.ts,
    }
    while #self.queue > self.MAX_QUEUE do
        table.remove(self.queue, 1)
    end
    self:SchedulePump(0.1)
    return true
end

function Sync:SchedulePump(delay)
    if self.pumpScheduled then
        return
    end
    self.pumpScheduled = true
    if not ns.After(delay or self.SEND_INTERVAL, function()
        Sync.pumpScheduled = false
        Sync:Pump()
    end) then
        self.pumpScheduled = false
    end
end

function Sync:RawSend(text, channel)
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, self.prefix or ns.SYNC_PREFIX, text, channel)
    if not ok then
        ns.Debug("send failed: %s", tostring(result))
        return "error"
    end
    local R = _G.Enum and _G.Enum.SendAddonMessageResult
    if ns.IsSecret(result) then
        -- unreadable result: assume it went out
        result = nil
    elseif R and type(result) == "number" then
        if result == R.AddonMessageThrottle or result == R.ChannelThrottle then
            return "throttle"
        end
        if R.AddOnMessageLockdown and result == R.AddOnMessageLockdown then
            return "lockdown"
        end
        if result ~= R.Success then
            ns.Debug("send to %s refused (result %d)", channel, result)
            return "error"
        end
    elseif result == false then
        return "error"
    end
    self.sentRecently[text] = ns.GameTime()
    self.stats.sent = self.stats.sent + 1
    return "ok"
end

function Sync:Pump()
    local item = self.queue[1]
    if not item then
        return
    end
    local now = ns.GameTime()
    if now - item.at > self.QUEUE_TTL or (item.key and self:HeardOn(item.channel, item.key, item.ts)) then
        table.remove(self.queue, 1) -- too old, or someone else already shared it
        self:SchedulePump(0.1)
        return
    end
    self:PruneSent(now)
    local ok, why = self:CanSend()
    if not ok then
        if why == "disabled" or why == "unavailable" then
            self.queue = {}
            return
        end
        self:SchedulePump(5) -- in an instance or locked down: hold and retry
        return
    end
    local result = self:RawSend(item.text, item.channel)
    if result == "throttle" then
        self:SchedulePump(3)
        return
    elseif result == "lockdown" then
        self.lockedUntil = now + 60
        self:SchedulePump(60)
        return
    end
    table.remove(self.queue, 1)
    if #self.queue > 0 then
        self:SchedulePump(self.SEND_INTERVAL)
    end
end

function Sync:PruneSent(now)
    self.sentCount = (self.sentCount or 0) + 1
    if self.sentCount < 50 then
        return
    end
    self.sentCount = 0
    for text, at in pairs(self.sentRecently) do
        if now - at > self.ECHO_WINDOW then
            self.sentRecently[text] = nil
        end
    end
end

-- Called for every new/refined local record.
function Sync:OnTimerChanged(key, record, reason, opts)
    if (reason ~= "new" and reason ~= "refined") or not record then
        return
    end
    if record.source == "sync" then
        return -- never relay what we were told
    end
    if opts and opts.noShare then
        return -- e.g. an aura whose length does not match the table
    end
    local buff = ns.GetBuff(key)
    if not buff or buff.kind ~= "drop" then
        return
    end
    local isTest = buff.testOnly or record.source == "test"
    if record.source == "test" and not (opts and opts.share) then
        return -- test drops stay local unless asked for
    end
    -- Wait until the buff has landed (an announce yell is usually refined by
    -- the exact yell by then), plus a random 1-6 s so that when a whole city
    -- hears the same yell, the first player to share it silences the rest.
    local wait = math.max(0, record.ts - ns.Now()) + 1 + math.random() * self.SHARE_JITTER
    local ts = record.ts
    ns.After(wait, function()
        local current = ns.Engine:GetRecord(key)
        if current and math.abs(current.ts - ts) <= ns.Engine:Window(buff) then
            Sync:ShareRecord(key, current, buff, isTest)
        end
    end)
end

function Sync:NoteHeard(channel, key, ts)
    local id = channel .. ":" .. key
    if self.heard[id] == nil then
        self.heardCount = (self.heardCount or 0) + 1
        if self.heardCount > 200 then
            self.heard = {}
            self.heardCount = 1
        end
    end
    self.heard[id] = { ts = ts, at = ns.GameTime() }
end

-- Someone else shared this drop on this channel (optionally: since `since`).
function Sync:HeardOn(channel, key, ts, since)
    local buff = ns.GetBuff(key)
    local heard = self.heard[channel .. ":" .. key]
    if not heard or not buff or type(ts) ~= "number" then
        return false
    end
    if since and heard.at < since then
        return false
    end
    return math.abs(heard.ts - ts) <= ns.Engine:Window(buff)
end

function Sync:ShareRecord(key, record, buff, isTest)
    local last = self.lastBroadcast[key]
    if last and math.abs(last - record.ts) <= ns.Engine:Window(buff) then
        return 0
    end
    self.lastBroadcast[key] = record.ts
    local text = Sync.EncodeDrop(key, record.ts, isTest)
    local n = 0
    for _, channel in ipairs(self:Channels(isTest and { guild = false } or nil)) do
        if not self:HeardOn(channel, key, record.ts) and self:Enqueue(text, channel, { key = key, ts = record.ts }) then
            n = n + 1
        end
    end
    return n
end

-- manual = true for /rhorn sync query (shorter cooldown). The last query
-- time is saved, so /reload does not make the whole guild answer again.
function Sync:Query(opts, manual)
    if not self:Enabled() then
        return 0
    end
    local now = ns.Now()
    local last = ns.db.syncState.lastQuery
    local cooldown = manual and self.QUERY_COOLDOWN or self.AUTO_QUERY_COOLDOWN
    local n = 0
    for _, channel in ipairs(self:Channels(opts)) do
        if (tonumber(last[channel]) or 0) + cooldown <= now then
            last[channel] = now
            if self:Enqueue(Sync.EncodeQuery(ns.VERSION, Sync.NewNonce()), channel) then
                n = n + 1
            end
        end
    end
    return n
end

function Sync:ScheduleReply(channel)
    local now = ns.GameTime()
    if (self.lastReply[channel] or -1000) + self.REPLY_COOLDOWN > now or self.replyPending[channel] then
        return false
    end
    if #ns.Engine:Snapshot() == 0 then
        return false
    end
    self.replyPending[channel] = true
    local askedAt = now
    -- random delay so a whole guild does not answer at once; whoever answers
    -- first suppresses the rest
    ns.After(1 + math.random() * 4, function()
        Sync.replyPending[channel] = nil
        -- only send what nobody has answered with since the question
        local missing = {}
        for _, e in ipairs(ns.Engine:Snapshot()) do
            if not Sync:HeardOn(channel, e.key, e.ts, askedAt) then
                missing[#missing + 1] = e
            end
        end
        if #missing == 0 then
            return
        end
        Sync.lastReply[channel] = ns.GameTime()
        for _, text in ipairs(Sync.EncodeState(missing)) do
            Sync:Enqueue(text, channel)
        end
    end)
    return true
end

function Sync:AllowSender(sender)
    local now = ns.GameTime()
    local entry = self.senderLog[sender]
    if not entry or now - entry.start > 60 then
        if not entry then
            self.senderCount = self.senderCount + 1
            if self.senderCount > 500 then
                self.senderLog = {}
                self.senderCount = 1
            end
        end
        entry = { start = now, count = 0 }
        self.senderLog[sender] = entry
    end
    entry.count = entry.count + 1
    return entry.count <= self.SENDER_LIMIT
end

function Sync:NoteVersion(version, sender)
    if not version or self.newerNoted then
        return
    end
    if Sync.CompareVersions(version, ns.VERSION) > 0 then
        self.newerNoted = true
        ns.Print("%s has version %s (you have %s). Consider updating.", sender or "someone", version, ns.VERSION)
    end
end

function Sync:OnAddonMessage(prefix, text, channel, sender)
    prefix = ns.SafeString(prefix)
    if not prefix or prefix ~= (self.prefix or ns.SYNC_PREFIX) then
        return
    end
    if not self:Enabled() then
        return
    end
    text = ns.SafeString(text)
    channel = ns.SafeString(channel)
    if not text or not channel then
        return
    end
    if channel ~= "GUILD" and not GROUP_CHANNELS[channel] then
        return
    end
    sender = ns.NormalizeName(sender) or "?"
    if ns.IsSelf(sender) then
        return
    end
    local sentAt = self.sentRecently[text]
    if sentAt and ns.GameTime() - sentAt < self.ECHO_WINDOW then
        return -- our own message echoed back (name formats can differ in Forever)
    end
    if not self:AllowSender(sender) then
        self.stats.rejected = self.stats.rejected + 1
        return
    end
    self.stats.received = self.stats.received + 1

    local msg, err, newer = Sync.Decode(text)
    if not msg then
        self.stats.rejected = self.stats.rejected + 1
        if err == "newer" then
            ns.Debug("%s uses sync protocol %s; update to read it", sender, tostring(newer))
        end
        return
    end

    if msg.type == "D" then
        local buff = ns.GetBuff(msg.key)
        local isTest = msg.test or (buff and buff.testOnly)
        if isTest and not GROUP_CHANNELS[channel] then
            self.stats.rejected = self.stats.rejected + 1
            return
        end
        self:NoteHeard(channel, msg.key, msg.ts)
        local ok = ns.Engine:RecordDrop(msg.key, msg.ts, isTest and "test" or "sync", sender, { channel = channel })
        if ok then
            self.stats.dropsAccepted = self.stats.dropsAccepted + 1
        end
    elseif msg.type == "S" then
        for _, e in ipairs(msg.entries) do
            local buff = ns.GetBuff(e.key)
            self:NoteHeard(channel, e.key, e.ts)
            if buff and not buff.testOnly then
                local ok = ns.Engine:RecordDrop(e.key, e.ts, "sync", sender, { channel = channel })
                if ok then
                    self.stats.dropsAccepted = self.stats.dropsAccepted + 1
                end
            end
        end
    elseif msg.type == "Q" then
        self:NoteVersion(msg.version, sender)
        self:ScheduleReply(channel)
    end
end

ns.On("INIT", function()
    Sync.prefix = ns.SYNC_PREFIX
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, Sync.prefix)
    end
end)

ns.On("TIMER_CHANGED", function(key, record, reason, opts)
    Sync:OnTimerChanged(key, record, reason, opts)
end)

ns.On("SETTING_CHANGED", function(key, value)
    if key == "sync" and not value then
        Sync.queue = {}
    end
end)

ns.RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
    Sync:OnAddonMessage(prefix, text, channel, sender)
end)

-- Inside instances incoming addon messages are unreadable, so ask again on
-- the way out (the saved cooldown keeps this cheap).
local wasInInstance = false
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
    local open = ns.InOpenWorld()
    if isInitialLogin or isReloadingUi then
        ns.After(10, function()
            Sync:Query()
        end)
    elseif open and wasInInstance then
        ns.After(5, function()
            Sync:Query()
        end)
    end
    if open and #Sync.queue > 0 then
        Sync:SchedulePump(2) -- back in the world: flush anything held during an instance
    end
    wasInInstance = not open
end)

local wasInGroup = false
ns.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    local inGroup = ns.IsInGroup()
    if inGroup and not wasInGroup then
        ns.After(5, function()
            Sync:Query({ guild = false })
        end)
    end
    wasInGroup = inGroup
end)
