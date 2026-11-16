-- Rallyhorn - Copyright (C) 2026 Zudryx - GPL-3.0-or-later (see LICENSE, NOTICE.md)
--
-- Engine: the timer core. It knows nothing about chat, auras or the network.
-- Every drop, real or fake, goes through Engine:RecordDrop(), so it can be
-- driven by tests and by /rhorn test exactly like by the detectors.

local ADDON_NAME, ns = ...

local Engine = {}
ns.Engine = Engine

-- Higher rank = more trustworthy timestamp. A same-event report only replaces
-- the stored one when it ranks higher.
Engine.RANK = {
    test = 1,
    sync = 2,
    manual = 3,
    announce = 3, -- heads-up yell; the landing time is an estimate
    yell = 4,     -- the yell that applies the buff
    aura = 5,     -- read from our own buff: exact
}

Engine.MAX_FUTURE = 300      -- reject drops more than 5 minutes ahead (announce delays are seconds)
Engine.MAX_AGE = 86400       -- ignore drops older than a day
Engine.DEFAULT_WINDOW = 90   -- reports within this many seconds are the same drop
Engine.MAX_HISTORY = 10

-- store = { timers = {}, history = {} }; normally the saved variables table.
function Engine:Attach(store)
    store.timers = store.timers or {}
    store.history = store.history or {}
    self.store = store
end

function Engine:Rank(source)
    return self.RANK[source] or 0
end

function Engine:Window(buff)
    return buff.dedupeWindow or self.DEFAULT_WINDOW
end

function Engine:AddHistory(key, ts, source, reporter)
    local buff = ns.GetBuff(key)
    local window = buff and self:Window(buff) or self.DEFAULT_WINDOW
    local list = self.store.history[key]
    if not list then
        list = {}
        self.store.history[key] = list
    end
    for _, h in ipairs(list) do
        if math.abs(h.ts - ts) <= window then
            return false
        end
    end
    list[#list + 1] = { ts = ts, source = source, reporter = reporter }
    table.sort(list, function(a, b)
        return a.ts > b.ts
    end)
    while #list > self.MAX_HISTORY do
        table.remove(list)
    end
    return true
end

local function changed(key, record, reason, opts)
    ns.Fire("TIMER_CHANGED", key, record, reason, opts or {})
end

-- Records a buff drop.
--   key       buff key from Data.lua
--   ts        server epoch seconds when the buff lands (may be a little in the future)
--   source    "yell", "announce", "aura", "sync", "test" or "manual"
--   reporter  who/what reported it (NPC or player name), optional
--   opts      optional { duration = observed aura seconds, share = true for /test share }
-- Returns accepted (boolean), reason (string), record.
function Engine:RecordDrop(key, ts, source, reporter, opts)
    opts = opts or {}
    local buff = ns.GetBuff(key)
    if not buff then
        return false, "unknown-buff"
    end
    ts = tonumber(ts)
    if not ts or ts ~= ts or ts == math.huge or ts == -math.huge then
        return false, "bad-time"
    end
    ts = math.floor(ts + 0.5)
    source = source or "manual"
    if not self.RANK[source] then
        return false, "bad-source"
    end
    if buff.kind == "personal" and (source == "sync" or source == "yell" or source == "announce") then
        return false, "personal"
    end

    local now = ns.Now()
    if ts > now + self.MAX_FUTURE then
        return false, "future"
    end
    if ts < now - self.MAX_AGE then
        return false, "too-old"
    end

    local duration = ns.SafeNumber(opts.duration)
    if duration and (duration <= 0 or duration > 6 * 3600) then
        duration = nil
    end

    local timers = self.store.timers
    local current = timers[key]
    local window = self:Window(buff)
    -- Remember that the NPC was heard even after our own buff (a better
    -- timestamp) takes over, so the window can say "heard + your buff".
    local heard = (source == "yell" or source == "announce") or nil

    if current then
        local diff = ts - current.ts
        if math.abs(diff) <= window then
            if self:Rank(source) > self:Rank(current.source) then
                current.ts = ts
                current.source = source
                current.reporter = reporter
                current.seen = now
                if duration then
                    current.dur = duration
                end
                if heard then
                    current.heard = true
                end
                changed(key, current, "refined", opts)
                return true, "refined", current
            end
            if duration and not current.dur then
                current.dur = duration
            end
            if heard and not current.heard then
                current.heard = true
                changed(key, current, "heard", opts)
            end
            return false, "duplicate", current
        end
        if diff < 0 then
            -- Earlier than what we have. If what we have is only an estimate
            -- still in the future, or second-hand, and this report is better,
            -- this one is right (e.g. a wrong announce delay or a bad peer clock).
            local weak = current.ts > now or current.source == "sync" or current.source == "test"
            if not (weak and self:Rank(source) > self:Rank(current.source)) then
                -- an older drop we had not heard about; keep it for the history only
                self:AddHistory(key, ts, source, reporter)
                return false, "older", current
            end
            current = nil -- replaced below, without keeping the bad value in history
        end
        -- Sanity check for shared reports: once a cooldown is confirmed, a
        -- second drop inside it cannot be real.
        if current and source == "sync" and buff.verified and buff.cooldown and diff < buff.cooldown - window then
            return false, "cooldown-conflict", current
        end
        if current then
            self:AddHistory(key, current.ts, current.source, current.reporter)
        end
    end

    local record = { ts = ts, source = source, reporter = reporter, seen = now, dur = duration, heard = heard }
    timers[key] = record
    changed(key, record, "new", opts)
    return true, "new", record
end

function Engine:Clear(key)
    if self.store.timers[key] then
        self.store.timers[key] = nil
        self.store.history[key] = nil
        changed(key, nil, "cleared")
        return true
    end
    return false
end

function Engine:ClearAll()
    for key in pairs(self.store.timers) do
        self.store.timers[key] = nil
    end
    for key in pairs(self.store.history) do
        self.store.history[key] = nil
    end
    changed(nil, nil, "cleared")
end

function Engine:GetRecord(key)
    return self.store.timers[key]
end

-- Status for display.
--   state: "unknown"   no drop known
--          "incoming"  drop announced, buff lands in eta seconds
--          "active"    buff is up for `remaining` seconds
--          "cooldown"  buff is gone; next drop possible in `readyIn` seconds
--          "ready"     cooldown over (only when the cooldown is known)
--          "expired"   buff is gone and no cooldown is known
function Engine:GetStatus(key, now)
    local buff = ns.GetBuff(key)
    if not buff then
        return nil
    end
    now = now or ns.Now()
    local record = self.store.timers[key]
    local st = { key = key, buff = buff, record = record }
    if not record then
        st.state = "unknown"
        return st
    end
    local duration = record.dur or buff.duration or 0
    st.dropAt = record.ts
    st.endsAt = record.ts + duration
    st.readyAt = buff.cooldown and (record.ts + buff.cooldown) or nil
    if record.ts > now then
        st.state = "incoming"
        st.eta = record.ts - now
    elseif now < st.endsAt then
        st.state = "active"
        st.remaining = st.endsAt - now
    elseif st.readyAt and now < st.readyAt then
        st.state = "cooldown"
        st.readyIn = st.readyAt - now
    else
        st.state = st.readyAt and "ready" or "expired"
        st.since = now - record.ts
    end
    return st
end

-- What we can share: drop-kind buffs, no tests, nothing stale.
function Engine:Snapshot(now)
    now = now or ns.Now()
    local out = {}
    for key, record in pairs(self.store.timers) do
        local buff = ns.GetBuff(key)
        if buff and buff.kind == "drop" and not buff.testOnly and record.source ~= "test"
            and record.ts >= now - self.MAX_AGE and record.ts <= now + self.MAX_FUTURE then
            out[#out + 1] = { key = key, ts = record.ts }
        end
    end
    table.sort(out, function(a, b)
        return a.key < b.key
    end)
    return out
end

ns.On("INIT", function()
    Engine:Attach(ns.db)
end)
