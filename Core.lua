--[[
    记仇 · 核心层
    《魔兽世界：无限》(WoW Forever) / 客户端 1.60.1 / Interface 16001

    背景：这个客户端把 COMBAT_LOG_EVENT_UNFILTERED 和
    CombatLogGetCurrentEventInfo 对第三方插件关闭了，注册会弹
    「该功能只对暴雪的UI开放」并禁用插件。所以整套记录链路绕开战斗日志，
    只用下面这些在本服实测可用的信号：

      击杀（我杀了谁）
        1. PLAYER_PVP_KILLS_CHANGED      击杀数一变就查，唯一的可靠触发器
        2. NAME_PLATE_UNIT_REMOVED       姓名板消失的玩家，主力取名字
        3. target / mouseover / focus    已死亡的玩家，选中兜底
        4. PARTY_KILL                    带受害者 GUID，辅助
        5. CHAT_MSG_COMBAT_MISC_INFO     「你 杀死了 XXX」，本服收不到，留着备用
        6. CHAT_MSG_COMBAT_HONOR_GAIN    荣誉消息不带名字，只当信号

      死亡（谁杀了我）
        C_DeathRecap.GetRecapEvents      死亡回顾里挑出唯一的 Player GUID

    本服玩家名一律是「名 + 空格 + 姓」两段，NPC 一般一个词。
    这条形状判断是「是不是玩家」的最后一道闸。
]]

local ADDON, ns = ...

ns.version = "2.1.43"

--------------------------------------------------------------
-- 名单本体：每个角色一份，InitDB 里指向 KillListDB.chars[角色名].players
--------------------------------------------------------------
local PLAYERS = {}

--------------------------------------------------------------
-- 默认设置
--------------------------------------------------------------
local DEFAULTS = {
    maxHistory    = 20,
    campingWindow = 600,
    campingCount  = 3,
    nearbyWarn    = 120,
    nameplate     = true,    -- 姓名板缓存（提供等级/职业 + 仇人接近提醒）
    nearbySound   = true,    -- 仇人接近时播放提示音
    alertSound    = 1,       -- 提示音音源编号（见 UI 里的 SOUNDS 表，1=自动/亡灵号角优先）
    nearbyScreen  = true,    -- 仇人接近时屏幕中央弹一行字
    enemyBar      = true,    -- 仇人在视野内时常驻一条「敌情条」
    tooltip       = true,    -- 鼠标悬停玩家时显示交手记录
    debug         = false,
}

-- 角色键：本服没有 realm，直接用角色名。改过名的角色会当成新角色（老数据仍留在旧名下）
-- 第二个返回值表示这个名字是否可信：登录流程早期拿不到名字时不能做存档迁移，
-- 否则整份老数据会锁进「未知角色」这个桶里再也回不来
local function CharKey()
    local n = UnitName("player")
    if type(n) == "string" and n ~= "" then return n, true end
    return "未知角色", false
end

-- 判断当前是否在 PVP 副本（战场 / 竞技场）。多接口兜底：
--   返回 true  = 在战场/竞技场；false = 在野外；nil = 接口都拿不到值（不确定）
-- 第二个返回值是判定来源，方便探针核对口径。
local function InPvpInstance()
    -- 1) GetInstanceInfo：第 2 个返回值是 instanceType（none/pvp/arena/party/raid）
    local ok, ret = pcall(function() return { GetInstanceInfo() } end)
    if ok and type(ret) == "table" and type(ret[2]) == "string" then
        local itype = ret[2]
        if itype == "pvp" or itype == "arena" then return true, "instance:" .. itype end
        if itype == "none" then return false, "instance:none" end
    end
    -- 2) IsInBattleground()
    if type(IsInBattleground) == "function" then
        local ok2, v2 = pcall(IsInBattleground)
        if ok2 and type(v2) == "boolean" then return v2, "IsInBattleground" end
    end
    -- 3) C_PvP.IsInBattleground()
    if type(C_PvP) == "table" and type(C_PvP.IsInBattleground) == "function" then
        local ok3, v3 = pcall(C_PvP.IsInBattleground)
        if ok3 and type(v3) == "boolean" then return v3, "C_PvP" end
    end
    return nil, "unknown"
end
ns.InPvpInstance = InPvpInstance

local function InitDB()
    if type(KillListDB) ~= "table" then KillListDB = {} end
    local db = KillListDB
    if type(db.settings) ~= "table" then db.settings = {} end
    for k, v in pairs(DEFAULTS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end

    -- 2.1.0：名单从「账号级」改成「每个角色一份」
    if type(db.chars) ~= "table" then db.chars = {} end
    local key, nameOK = CharKey()
    local bucket = db.chars[key]
    if type(bucket) ~= "table" then bucket = {}; db.chars[key] = bucket end
    if type(bucket.players) ~= "table" then bucket.players = {} end
    bucket.name = key
    bucket.lastSeen = time()

    -- 老存档：players 直接挂在根上，整份并给当前登录的角色，然后从根上摘掉
    -- （不摘掉的话同一份数据会被写进存档两次，读回来还会变成两份独立的表）
    if nameOK and type(db.players) == "table" then
        if next(db.players) ~= nil then
            for k, v in pairs(db.players) do
                if type(v) == "table" and bucket.players[k] == nil then
                    bucket.players[k] = v
                end
            end
        end
        db.players = nil
    end

    PLAYERS = bucket.players

    -- 1.9.1：老存档里 debug 是当初排障时手动打开的，强制关一次；之后用户自己开就保留
    if not db.settings.debugReset then
        db.settings.debug = false
        db.settings.debugReset = true
    end
    -- 2.0.0：清掉历史遗留的测试数据（旧版 /kl test 插进去的假玩家）
    if not db.settings.testPurged then
        for k, v in pairs(PLAYERS) do
            if type(v) == "table" and v.test then PLAYERS[k] = nil end
        end
        db.settings.testPurged = true
    end
    db.version = 3
end
ns.InitDB = InitDB

-- 界面层用：拿当前角色的名单表
function ns.Players() return PLAYERS end

--------------------------------------------------------------
-- 界面刷新回调
--------------------------------------------------------------
ns.listeners = {}
function ns.RegListener(fn) ns.listeners[#ns.listeners + 1] = fn end

function ns.Notify(what)
    for i = 1, #ns.listeners do
        local ok, err = pcall(ns.listeners[i], what)
        if not ok and KillListDB and KillListDB.settings and KillListDB.settings.debug then
            print("|cffff7777[记仇]|r 界面刷新异常：" .. tostring(err))
        end
    end
end

--------------------------------------------------------------
-- 日志：先进插件自己的日志窗，debug 开着才额外打到聊天框
--------------------------------------------------------------
local LOG_MAX = 400
ns.logs  = {}
ns.onLog = nil          -- 界面层挂进来的回调，收到一条就刷一行

local LOG_COLORS = {
    info  = { 0.58, 0.58, 0.58 },
    kill  = { 0.40, 0.90, 0.45 },
    death = { 1.00, 0.36, 0.36 },
    warn  = { 1.00, 0.66, 0.20 },
}

function ns.Log(msg, kind)
    if type(msg) ~= "string" or msg == "" then return end
    local c = LOG_COLORS[kind] or LOG_COLORS.info
    local line = {
        t = time(), text = msg, kind = kind or "info",
        r = c[1], g = c[2], b = c[3],
    }
    ns.logs[#ns.logs + 1] = line
    while #ns.logs > LOG_MAX do table.remove(ns.logs, 1) end
    if ns.onLog then pcall(ns.onLog, line) end
end

function ns.ClearLog()
    ns.logs = {}
    if ns.onLog then pcall(ns.onLog, nil) end
end

-- 调试输出：只进日志窗，不打扰聊天框，除非 debug 真开着
function ns.Debug(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local msg = table.concat(parts, " ")

    local dbg = KillListDB and KillListDB.settings and KillListDB.settings.debug
    if dbg then
        print("|cff8ab4ff[记仇 调试]|r", msg)
        ns.Log(msg, "info")
    end
end

--------------------------------------------------------------
-- 工具
--------------------------------------------------------------
function ns.TimeAgo(t)
    if not t then return "未知" end
    local d = time() - t
    if d < 60 then return "刚刚" end
    if d < 3600 then return math.floor(d / 60) .. " 分钟前" end
    if d < 86400 then return math.floor(d / 3600) .. " 小时前" end
    if d < 604800 then return math.floor(d / 86400) .. " 天前" end
    return date("%m-%d", t)
end

--------------------------------------------------------------
-- 玩家缓存：按名字和 GUID 各存一份
--------------------------------------------------------------
local cacheByName = {}
local cacheByGUID = {}

-- 无限服的角色名是「名 + 姓」两段，不同接口给的段数不一样。
-- 实测（/kl name）：只有 GetUnitName(unit, true) 会返回「名 姓」全名，
-- UnitName / UnitName(true) / UnitFullName 都只给前半截。
-- 所以这里先取 GetUnitName，再跟其余接口比长度，谁最长用谁。
local function BestName(unit)
    local best

    local function take(v)
        if type(v) == "string" and v ~= "" then
            if not best or #v > #best then best = v end
        end
    end

    pcall(function() take(GetUnitName(unit, true)) end)
    pcall(function() take(select(1, UnitFullName(unit))) end)
    pcall(function() take(select(1, UnitName(unit, true))) end)
    pcall(function() take(select(1, UnitName(unit))) end)

    return best
end

-- 只拿到「名」的时候，去缓存里找同一个人的「名 姓」全名
local function LookupCacheByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local hit = cacheByName[name]
    if hit then return hit end
    for k, v in pairs(cacheByName) do
        if k:sub(1, #name + 1) == name .. " " then return v end
    end
    return nil
end

local function CacheUnit(unit)
    local name = BestName(unit)
    local guid = UnitGUID(unit)
    if not name then return nil end

    local info = {
        name  = name,
        guid  = guid,
        level = UnitLevel(unit),
        class = select(2, UnitClass(unit)),
        race  = select(2, UnitRace(unit)),
    }
    cacheByName[name] = info
    if guid then cacheByGUID[guid] = info end
    return info
end

--------------------------------------------------------------
-- 记录
--------------------------------------------------------------
local recentKill   = {}   -- 名字 -> 时间戳，用于两条信号去重
local recentDeath  = {}   -- 名字 -> 时间戳，用于防止一次死亡记两次

-- 队友判定。组队打 PVP 时这是个高度污染源：
-- PLAYER_PVP_KILLS_CHANGED 会因为队友的战果而变化，而 target / 姓名板消失
-- 又经常指向身边的队友，两个凑一起就会把队友记成「我杀了他」。
-- 所以每条击杀记录落库前，先按队伍名单硬挡一道。
local function IsTeammate(name)
    if type(name) ~= "string" or name == "" then return false end

    local function hit(unit)
        if not UnitExists(unit) then return false end
        local n = BestName(unit)
        if not n then return false end
        return n == name
            or n:sub(1, #name + 1) == name .. " "
            or name:sub(1, #n + 1) == n .. " "
    end

    local nr = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    for i = 1, nr do
        if hit("raid" .. i) then return true end
    end

    local np = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    for i = 1, np do
        if hit("party" .. i) then return true end
    end

    return false
end

-- PARTY_KILL 原始参数留档，`/kl pk` 可以回看最近 8 次到底传了什么。
-- 每条都记下「事件发生那一刻的队伍人数」：如果某人单练时也收到带别人 GUID 的通报，
-- 就说明这条事件在这服是广播式的，得再加一道判定
ns.pkRaw = {}
function ns.NotePartyKill(raw, victim, dropped, killer)
    local t = ns.pkRaw
    if #t >= 8 then table.remove(t, 1) end
    t[#t + 1] = {
        t       = time(),
        raw     = table.concat(raw, " │ "),
        victim  = victim or "无",
        dropped = dropped and true or false,
        killer  = killer,
        np      = (GetNumPartyMembers and GetNumPartyMembers()) or 0,
        nr      = (GetNumRaidMembers and GetNumRaidMembers()) or 0,
    }
end

local function partyKillLines()
    local out = {}
    local t = ns.pkRaw or {}
    if #t == 0 then
        out[#out + 1] = "PARTY_KILL：还没有捕获到，进游戏打个玩家再看"
    else
        out[#out + 1] = format("最近 %d 次 PARTY_KILL（时间 · 队伍人数 · 原始参数 → 判定结果）", #t)
        for _, v in ipairs(t) do
            out[#out + 1] = format("  %s  小队%d/团队%d  %s  →  %s%s",
                date("%H:%M:%S", v.t), v.np or 0, v.nr or 0, v.raw,
                v.dropped and "丢弃（击杀者不是我）" or v.victim,
                v.dropped and (" · 击杀者 " .. tostring(v.killer)) or "")
        end
    end

    -- 顺带把队伍接口一起打出来：判断「队友识别」到底有没有生效，就看这一段
    local np = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    local nr = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    out[#out + 1] = format("队伍状态：小队 %d 人 · 团队 %d 人", np, nr)
    for i = 1, np do
        out[#out + 1] = format("    party%d：%s · %s", i,
            tostring(BestName("party" .. i)), tostring(UnitGUID("party" .. i)))
    end
    for i = 1, math.min(nr, 10) do
        out[#out + 1] = format("    raid%d：%s · %s", i,
            tostring(BestName("raid" .. i)), tostring(UnitGUID("raid" .. i)))
    end
    return out
end

function ns.PartyKillText()
    return table.concat(partyKillLines(), "\n")
end

function ns.DumpPartyKill()
    for _, line in ipairs(partyKillLines()) do
        print("|cff8ab4ff[记仇]|r " .. line)
    end
end

-- 通用原始参数留档（/kl raw）。2.1.25 游戏更新后 PARTY_KILL 不再推送，
-- 击杀侧只剩荣誉消息和计数事件；它们到底带几段、每段是名字还是 GUID，
-- 不能再拍脑袋猜，先把原始参数连类型一起留档，打一场再回看。
-- 2.1.27：SYSTEM（离队/找玩家/排队这类刷屏消息）不进缓冲，免得把荣誉、计数记录挤掉。
ns.rawBuf = {}
local RAW_KEEP = { HONOR_GAIN = true, PVP_KILLS = true, MISC_INFO = true, PARTY_KILL = true, BG_SYS = true }

-- 安全转字符串：本服存在 secret 等非常规类型，tostring/format 不一定返回字符串，
-- 每一步都断言最终是原生 string，不是就替换占位，避免 table.concat 混入 secret 崩溃。
-- 安全转字符串：本服 secret string 被打上 tainted 标记，插件对它做比较/拼接/读取都会抛错。
-- 所有可能触碰 secret 的操作都放进 pcall，失败一律换成 <类型> 占位，绝不把原值带出来。
local function SafeStr(v)
    local ty = type(v)
    local ok, s = pcall(function()
        if ty == "string" then return v end
        if ty == "number" or ty == "boolean" then return tostring(v) end
        if ty == "nil" then return "nil" end
        return tostring(v)
    end)
    if not ok or type(s) ~= "string" then return "<" .. ty .. ">" end
    -- 可比较/可拼接校验，仍在 pcall 内；secret 过不了这一关
    local ok2 = pcall(function()
        local _ = (s ~= "") and ("" .. s)
    end)
    if not ok2 then return "<" .. ty .. ">" end
    return s
end

-- 逐段字符串累加；每段已经过 SafeStr 兜底成普通字符串，不再做内容比较。
local function Join(arr, sep)
    local out = ""
    for _, x in ipairs(arr) do
        local s = SafeStr(x)
        if out == "" then out = s else out = out .. sep .. s end
    end
    return out
end

-- 参数序列化：普通值转字符串；table（或不可读的包装对象）展开一层键值。
-- 用来排查事件参数 / 结构化表里是否藏着受害者 GUID/名字。
local function ExpandTable(v)
    local parts = {}
    local cnt = 0
    local okP = pcall(function()
        for k, x in pairs(v) do
            cnt = cnt + 1
            if cnt <= 20 then
                parts[#parts + 1] = SafeStr(k) .. "=" .. type(x) .. ":" .. SafeStr(x)
            end
        end
    end)
    if okP and cnt > 0 then
        return "table", "{" .. Join(parts, ", ") .. "}"
    end
    return nil
end

local function ArgText(v)
    local ty = type(v)
    -- table 优先展开一层；空表/不可遍历才退回地址串
    if ty == "table" then
        local exp = ExpandTable(v)
        if exp then return exp end
        return "table", SafeStr(v)
    end
    local plain = SafeStr(v)
    if plain:sub(1, 1) ~= "<" then return ty, plain end
    -- 非 table 但不可读：可能是 secret 包装对象，再尝试 pairs 展开；失败标注受保护
    local exp = ExpandTable(v)
    if exp then return exp end
    return ty, plain .. "（不可读/受保护）"
end

function ns.NoteRaw(event, ...)
    -- SYSTEM 单独走关键词过滤：只留击杀/死亡/荣誉/据点相关，丢弃找玩家、排队、离队等刷屏
    if event == "SYSTEM" then
        local msg = ...
        if type(msg) ~= "string" then return end
        if not (msg:find("杀死") or msg:find("击杀") or msg:find("死亡")
            or msg:find("击败") or msg:find("消灭") or msg:find("荣誉")
            or msg:find("突袭") or msg:find("占领") or msg:find("夺取")) then
            return
        end
    elseif not RAW_KEEP[event] then
        return
    end
    local t = ns.rawBuf
    if #t >= 40 then table.remove(t, 1) end
    local args = {}
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        local okA, ty, val = pcall(ArgText, v)
        if okA then
            args[i] = { type = SafeStr(ty), val = SafeStr(val) }
        else
            args[i] = { type = "error", val = SafeStr(ty) }
        end
    end
    t[#t + 1] = { t = time(), event = event, n = n, args = args }
end

local function rawLines()
    local out = {}
    local t = ns.rawBuf or {}
    if #t == 0 then
        out[#out + 1] = "还没有捕获到信号，打一场 PVP 再看"
    else
        out[#out + 1] = "最近 " .. #t .. " 条信号原始参数（时间 · 事件 · 段数 · 每段 类型=值）"
        for _, v in ipairs(t) do
            local parts = {}
            for i, a in ipairs(v.args) do
                local seg = SafeStr(i) .. ":" .. SafeStr(a.type) .. "=" .. SafeStr(a.val)
                if type(seg) == "string" then parts[#parts + 1] = seg end
            end
            local body = Join(parts, " │ ")
            if body == "" then body = "（无参数）" end
            out[#out + 1] = SafeStr(date("%H:%M:%S", v.t)) .. "  " .. SafeStr(v.event)
                .. "（" .. SafeStr(v.n) .. " 段）  " .. SafeStr(body)
        end
    end
    return out
end

function ns.RawText()
    return Join(rawLines(), "\n")
end

function ns.DumpRaw()
    for _, line in ipairs(rawLines()) do
        print("|cff8ab4ff[记仇]|r " .. line)
    end
end

local function Sanitize(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or name == "Unknown" or name == "未知" then return nil end
    -- GUID 形状的东西不是人名（Player-1-xxx / Creature-0-xxx / Pet-0-xxx）
    if name:find("^[A-Za-z]+%-[%x%d]") then return nil end
    if #name > 60 then name = name:sub(1, 60) end
    return name
end

-- 把历史里“名字存成了 GUID”的脏数据清掉（老版本留下的）
local function PurgeGarbage()
    local players = PLAYERS
    if type(players) ~= "table" then return 0 end
    local n = 0
    for k, e in pairs(players) do
        local bad = (type(k) == "string" and k:find("^[A-Za-z]+%-[%x%d]"))
                     or (type(e) == "table" and type(e.name) == "string"
                         and e.name:find("^[A-Za-z]+%-[%x%d]"))
        if bad then players[k] = nil; n = n + 1 end
    end
    return n
end

-- 两个名字是不是同一个人：相等，或互为「半名 ↔ 全名」（空格分隔）
local function NamesMatch(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    if a == b then return true end
    return a:sub(1, #b + 1) == b .. " " or b:sub(1, #a + 1) == a .. " "
end

local function FindEntry(name, guid)
    local players = PLAYERS
    if players[name] then return players[name], name end

    if guid and guid ~= "" then
        for k, v in pairs(players) do
            -- GUID 相同但名字完全对不上（私服 GUID 复用/错绑），不当同一个人，避免并到别人条目
            if type(v) == "table" and v.guid == guid and NamesMatch(k, name) then return v, k end
        end
    end

    -- 半名和全名当成同一个人：「极道王」↔「极道王 夺心魄」
    -- 靠空格分隔，所以「张三」不会被「张三丰」误吞
    for k, v in pairs(players) do
        if type(v) == "table" and type(k) == "string" and k ~= name then
            if NamesMatch(k, name) then
                return v, k
            end
        end
    end

    return nil, nil
end

-- 名字变长说明补上了「姓」，把键名迁移过去
local function EnsureName(e, oldKey, name)
    if e and oldKey and oldKey ~= name and #name > #oldKey then
        PLAYERS[oldKey] = nil
        e.name = name
        e.key  = name
        PLAYERS[name] = e
        ns.Log("名字补全：" .. oldKey .. " → " .. name, "kill")
    end
    return e
end

local function GetEntry(name, guid)
    local e, oldKey = FindEntry(name, guid)
    if e then
        EnsureName(e, oldKey, name)
        return e
    end

    e = {
        key     = name,
        name    = name,
        kills   = 0,
        deaths  = 0,
        history = {},
    }
    PLAYERS[name] = e
    return e
end

local function Record(name, kind, guid, noDedupe, src)
    name = Sanitize(name)
    if not name then return nil end

    local me = UnitName("player")
    if me and name == me then return nil end

    -- 战场/竞技场里不做自动统计（只记野外交手）；手动补记 src="manual" 不受此限。
    -- 判定拿不到值（nil）时不拦截，避免把野外误判成战场而漏记。
    if src ~= "manual" then
        local inPvp = InPvpInstance()
        if inPvp == true then
            ns.Debug("PVP 副本内，自动记录已跳过：" .. name)
            return nil
        end
    end

    -- 队友永远不算「我杀过的」，挡在落库之前
    if kind == "kill" and IsTeammate(name) then
        ns.Debug("队友不算击杀，已跳过：" .. name)
        return nil
    end

    local now = time()

    -- PARTY_KILL 和荣誉击杀消息往往几乎同时到，8 秒内同名只记一次
    if kind == "kill" and not noDedupe then
        local last = recentKill[name]
        if last and (now - last) <= 8 then return nil end
        recentKill[name] = now
    end

    -- 一次死亡只算一次：死亡回顾可能被重复触发，15 秒内同一个人不重复计入。
    -- 优先按 GUID 去重（碎片名一场内可能变），拿不到 GUID 才退回按名字
    if kind == "death" and not noDedupe then
        local dkey = guid or name
        local last = recentDeath[dkey]
        if last and (now - last) <= 15 then return nil end
        recentDeath[dkey] = now
    end

    local e = GetEntry(name, guid)

    local info = LookupCacheByName(name) or (guid and cacheByGUID[guid])
    if info then
        if info.level and info.level > 0 then e.level = info.level end
        e.class = info.class or e.class
        e.race  = info.race  or e.race
    end
    if guid and not e.guid then e.guid = guid end

    local zone = (GetZoneText and GetZoneText()) or ""

    if kind == "kill" then
        e.kills     = (e.kills or 0) + 1
        e.firstKill = e.firstKill or now
        e.lastKill  = now
    else
        e.deaths     = (e.deaths or 0) + 1
        e.firstDeath = e.firstDeath or now
        e.lastDeath  = now
    end

    e.lastSeen = now
    if zone ~= "" then e.lastZone = zone end
    if src then e.lastSrc = src end

    local h = e.history
    if not h then h = {}; e.history = h end
    table.insert(h, 1, {
        t = now, kind = kind, zone = zone, src = src,
        myLevel = UnitLevel("player") or 0,
    })
    local cap = KillListDB.settings.maxHistory
    while #h > cap do table.remove(h) end

    ns.Notify("record")
    return e
end

--------------------------------------------------------------
-- 备用路径：从「命中」消息里记下我正在打谁
-- 宠物攻击也会以「你的 <宠物名> 命中 <目标>」出现，能覆盖宝宝补最后一刀的情况
-- 注意：本服 SELF_HITS / SELF_SPELLS / PET_HITS / PET_SPELLS 四个事件实测
-- 全部注册不上（/kl env 显示 false），这里只是留着，换环境或哪天放开就能用
--------------------------------------------------------------
ns.lastHit = nil
ns.plateGone     = {}  -- guid -> {name, t}，姓名板消失的时刻，用来判断谁刚被放倒
ns.plateUnitGUID = {}  -- unit -> guid，REMOVED 触发时 unit 已经失效，只能提前存
ns.plateUnitName = {}  -- unit -> 名字，同上，缓存里查不到时用它兜底


-- 2.1.24 删掉了 RecordFromLastHit（2.1.10 到 2.1.23 一直挂着的「猜」兜底）。
-- 它靠「最近命中过谁」加「谁的姓名板刚从视野里消失」来推断击杀，是唯一还在造成
-- 误记的路：3v5 混战时敌方五个人来回跑动、倒下、隐身，姓名板一消失就被记成
-- 「我杀的」。实测一场里 Leung Bao 被记 3 次，而同一时刻日志还在报
-- 「附近出现 Leung Bao」和「你已死亡」。这服没有任何「是我打死的」强信号
-- （CLEU 被封、SELF_HITS 注册失败、「你 杀死了 X」收不到），所以这条路做不准。
-- 现在只认「PARTY_KILL 第一段是我」的通报；宠物补尾刀会漏记，认了。
-- ns.lastHit 仍然保留（HandleHit 会写），只用于日志排查展示，不再写名单。

--------------------------------------------------------------
-- 守尸提醒
--------------------------------------------------------------
local function CheckCamping(e)
    if not e or e.ignored then return end
    local s   = KillListDB.settings
    local now = time()

    local n = 0
    for _, h in ipairs(e.history) do
        if h.kind == "death" and (now - h.t) <= s.campingWindow then
            n = n + 1
        else
            break
        end
    end

    if n >= s.campingCount then
        if not e.campingNotified or (now - e.campingNotified) > s.campingWindow then
            e.campingNotified = now
            local mins = math.floor(s.campingWindow / 60)
            print(format("|cffff3333[仇人名单]|r %s 在 %d 分钟内放倒你 %d 次，可能正在守尸。",
                e.name, mins, n))
            ns.Log(format("%s 在 %d 分钟内放倒你 %d 次，可能正在守尸", e.name, mins, n), "warn")
        end
    end
end

--------------------------------------------------------------
-- 信号 1：PARTY_KILL
--------------------------------------------------------------
local function HandlePartyKill(...)
    local myGUID = UnitGUID("player")
    local n = select("#", ...)
    local victimGUID, victimName
    local killer, killerIdx
    local raw = {}

    -- 本服的形态是「击杀者 GUID + 受害者」，第一个参数就是击杀者。
    -- 所以只要第一段 Player GUID 不是我本人，这条通报就不是我的击杀——
    -- 队友、路人、任何别人，一个标准处理，根本不用去判队伍关系。
    for i = 1, n do
        local v = select(i, ...)
        -- 类型一起留档：raw 每条写成 `string=xxx` / `number=123` / `nil`；
        -- secret 受保护值用 SafeStr 兜底，不能读就标占位，不让 tostring/拼接抛错中断整条。
        raw[i] = type(v) .. "=" .. SafeStr(v)
        pcall(function()
            if type(v) ~= "string" or v == "" then return end
            local isPlayer = v:find("^Player%-") ~= nil
            if isPlayer then
                if not killer then killer, killerIdx = v, i end
                if v ~= myGUID then victimGUID = victimGUID or v end
            elseif not v:find("^[A-Za-z]+%-") and #v <= 24 and not victimName then
                victimName = v
            end
        end)
    end

    -- 只有一个参数时没有「击杀者」可言（那段只能是受害者），所以这条判定只在
    -- 「参数 ≥ 2 且第一段是 Player GUID」的形态下生效，不会误伤单参数形态
    local notMine = killer and killerIdx == 1 and n >= 2 and killer ~= myGUID
    ns.NotePartyKill(raw, victimGUID or victimName, notMine, killer)

    if notMine then
        ns.Debug("击杀通报不是我发的（击杀者 " .. tostring(killer) .. "）：" .. table.concat(raw, " | "))
        return
    end

    -- 参数里既没有别的 Player GUID、也没有任何名字：被杀的是怪或宠物。
    -- 2.1.24 起这里不再做任何推断——以前会拿「此刻选中的死玩家」或「最近命中过的人」兜底，
    -- 混战里躺在旁边的尸体、只挨了几枪的敌人都会被算成我的击杀
    -- （2.1.10 杀玛格拉姆掠夺者时把躺尸的「真爱坤 小黑子」记上了；2.1.23 之前又把 Leung Bao 记了 3 次）。
    if not victimGUID and not victimName then
        -- 2.1.24：这里原来会去「猜」最近命中过谁、谁的姓名板刚消失，混战必错。
        -- 没有受害者 Player GUID 就当场跳过，不猜。
        ns.Debug("PARTY_KILL 没有受害者 Player GUID（多半是宠物或怪），跳过不猜")
        return
    end

    -- 名字只有半截时，去缓存里换回「名 姓」全名并带上 GUID
    local info = (victimGUID and cacheByGUID[victimGUID]) or LookupCacheByName(victimName)
    if info then
        if info.name and (not victimName or #info.name > #victimName) then victimName = info.name end
        if not victimGUID then victimGUID = info.guid end
    end

    -- 有 GUID 但缓存里没有名字：多半是姓名板没缓存过他。
    -- 先把 GUID 挂住，等「你 杀死了 XXX」那条带名字的消息到了直接配上
    if victimGUID and not victimName then
        ns.pendingKillGUID = victimGUID
        ns.pendingKillAt = time()
        ns.Log("击杀了一个玩家，但还没拿到他的名字（GUID " .. victimGUID .. "），等他进姓名板再补", "warn")
        return
    end

    -- 关键判断：既没有 GUID，姓名板也从来没见过这个人，判定为 NPC 丢弃。
    -- 杀怪、杀宠物、杀 NPC 都走不到这里。但姓名板缓存可能晚一步到，先等 1 秒再判
    if not victimGUID and not info then
        local pendingName = victimName
        C_Timer.After(1.0, function()
            local infoLate = LookupCacheByName(pendingName)
            if infoLate then
                local eLate = Record(infoLate.name, "kill", infoLate.guid, nil, "party_kill_late")
                if eLate then ns.Log("击杀记录（延迟补上）：" .. eLate.name, "kill") end
            else
                ns.Log("丢弃 NPC 击杀：「" .. tostring(pendingName) .. "」（姓名板从没见过）", "warn")
            end
        end)
        return
    end

    local e = Record(victimName, "kill", victimGUID, nil, "party_kill")
    if e then ns.Log("击杀记录：" .. e.name, "kill") end
end

--------------------------------------------------------------
-- 信号 2：荣誉击杀消息
--------------------------------------------------------------
local honorPattern

local function GetHonorPattern()
    if honorPattern ~= nil then return honorPattern or nil end

    local tmpl = _G["COMBATLOG_HONORGAIN"]
    if type(tmpl) ~= "string" or tmpl == "" or not tmpl:find("%%s") then
        honorPattern = false
        return nil
    end

    -- 先把 %s / %d 换成占位符，转义其余字符，再把占位符换成捕获
    local p = tmpl:gsub("%%s", "\1"):gsub("%%d", "\2")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("\1", "(.-)"):gsub("\2", "%%d")
    honorPattern = p
    return p
end

local function CleanMsg(msg)
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", "")
    msg = msg:gsub("|r", "")
    msg = msg:gsub("|H[^|]*|h(.-)|h", "%1")
    msg = msg:gsub("|T[^|]*|t", "")
    return msg
end

local function HandleHit(msg)
    if type(msg) ~= "string" then return end
    if msg:find("未命中") or msg:find("闪避") or msg:find("招架")
        or msg:find("格挡") or msg:find("抵抗") then
        return
    end

    local m = CleanMsg(msg)
    -- 「你的 瞄准射击 命中 狗熊哆嗦毛 中二 245 物理」
    local target = m:match("命中%s(.-)%s%d")
    if not target then return end

    target = target:gsub("^%s+", ""):gsub("%s+$", "")
    if target == "" or #target > 40 then return end

    -- 姓名板缓存里存的全是 UnitIsPlayer 的单位，命中就算玩家；
    -- 缓存里没有时才退回形状判断：本服玩家名多为「名 + 姓」，NPC 一般一个词。
    -- 注意名字可能被截半（「燃烧的精灵」就是半名），缓存命中的不能因为没空格被丢掉
    local cachedInfo = LookupCacheByName(target)
    if not cachedInfo and not target:find(" ") then return end

    local me = UnitName("player")
    if me and target == me then return end

    local guid = cachedInfo and cachedInfo.guid
    if not guid then
        for _, u in ipairs({ "target", "focus", "mouseover" }) do
            if UnitExists(u) and UnitName(u) == target then
                guid = UnitGUID(u)
                break
            end
        end
    end

    ns.lastHit = { name = target, guid = guid, t = time() }
end
local function HandleHonorGain(msg)
    if type(msg) ~= "string" then return end

    local m = CleanMsg(msg)
    local name

    local pat = GetHonorPattern()
    if pat then
        name = m:match(pat)
    end

    -- 兜底：客户端模板里名字永远在“死亡”两个字前面，
    -- 万一哪天模板变了也能抓到人
    if not name or name == "" then
        name = m:match("^(.-)死亡")
    end

    if not name then
        ns.Debug("荣誉消息不带名字（不再靠最近命中猜）：" .. m)
        return
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    -- 空名字或抓到标点说明匹配串了，宁可漏记也不记错
    if name == "" or name:find("[（(：:，,、。%.]") then return end

    -- 荣誉消息只带半截名字，靠姓名板缓存换回全名并补上 GUID
    local info = LookupCacheByName(name)
    if info and info.name and #info.name > #name then name = info.name end

    local e = Record(name, "kill", info and info.guid or nil, nil, "honor")
    if e then ns.Log("荣誉击杀消息：" .. e.name, "kill") end
end

--------------------------------------------------------------
-- 信号 2b：战斗信息里的「你 杀死了 XXX」
-- 这条消息带完整名字（名 + 姓），是 PARTY_KILL 只给 GUID 时的关键补充
-- 不依赖 COMBATLOG_VICTIM 模板：本服该模板缺失，直接按中文结构切
--------------------------------------------------------------
local function HandleMiscInfo(msg)
    if type(msg) ~= "string" then return end

    local m = CleanMsg(msg)

    -- 「你 杀死了 XXX」/「勇敢牛宝 不怕困难 杀死了 XXX」
    -- 不依赖 COMBATLOG_VICTIM 模板：本服模板还没实证过，直接用中文结构切
    local killer, victim = m:match("^(.-)杀死了(.+)$")
    if not victim then
        -- 不含击杀结构的系统消息（离队、查不到玩家、队伍解散、被移出团队等）直接静默，
        -- 不往日志窗刷「没解析出」的噪音
        return
    end

    -- 聊天里的名字常被包成超链接 [名字]，CleanMsg 拆掉 |H…|h 之后还留着方括号
    local function trimName(s)
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
        s = s:gsub("^%[", ""):gsub("%]$", "")
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
        return s
    end
    killer = trimName(killer)
    victim = trimName(victim)

    -- 只认「我杀死的」，别把别人互相击杀记成我的
    local me = UnitName("player")
    if killer ~= "你" and killer ~= me then return end
    if victim == "" or victim == "你" or victim == me then return end

    -- 优先用姓名板缓存确认是玩家（缓存只收 UnitIsPlayer 的单位，最准）；
    -- 姓名板没开时缓存是空的，才退回形状判断：玩家名多为「名 + 姓」，
    -- 但名字可能被截成半段（「燃烧的精灵」），形状只能当参考
    local info = LookupCacheByName(victim)
    if not info then
        if not victim:find(" ") then
            ns.Log("丢弃非玩家击杀：「" .. victim .. "」（姓名板从没见过）", "warn")
            return
        end
        ns.Log("注意：「" .. victim .. "」名字像玩家，但姓名板没缓存过，这次先记下", "warn")
    end

    local g = info and info.guid
    if not g and ns.pendingKillGUID and ns.pendingKillAt and (time() - ns.pendingKillAt) <= 10 then
        g = ns.pendingKillGUID
    end
    local e = Record(info and info.name or victim, "kill", g, nil, "victim")
    if e then ns.Log("击杀（战斗信息）：" .. e.name, "kill") end
end

--------------------------------------------------------------
-- 信号 3：死亡回顾，找出杀你的人
--------------------------------------------------------------
-- 同一次死亡事件指纹：来源 GUID + 受击时间戳 + 技能 + 伤害。
-- recap 会在重试、脱离战斗补读时被反复读取，靠指纹把「同一次死亡」只记一次，
-- 而不是按 15 秒时间窗（跨分钟的重试仍会漏挡）。
local recapSeen = {}

local function RecordDeathFromRecap()
    if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then
        ns.Debug("没有 C_DeathRecap 接口，无法自动识别凶手")
        return
    end

    local ok, events = pcall(C_DeathRecap.GetRecapEvents)
    if not ok or type(events) ~= "table" then
        ns.Debug("死亡回顾读取失败：" .. tostring(events))
        return
    end

    local myGUID = UnitGUID("player")
    ns.Debug(format("死亡回顾共 %d 条", #events))

    for i = #events, 1, -1 do
        local e = events[i]
        if type(e) == "table" then
            local guid = e.sourceGUID or e.casterGUID
            local name = e.sourceName or e.casterName
            ns.Debug(format("  第 %d 条：%s / %s", i, tostring(name), tostring(guid)))
            if type(guid) == "string" and guid:find("^Player%-") and guid ~= myGUID then
                -- 事件指纹：同一次死亡无论被重试/脱战补读读几遍，只记一次
                local fp = guid .. "|" .. SafeStr(e.timestamp) .. "|" ..
                    SafeStr(e.spellId or e.spellName) .. "|" .. SafeStr(e.amount)
                if recapSeen[fp] then
                    ns.Debug("  同一次死亡已记过，跳过：" .. SafeStr(name))
                    return true
                end
                recapSeen[fp] = true
                local seenN = 0
                for _ in pairs(recapSeen) do seenN = seenN + 1 end
                if seenN > 80 then recapSeen = {}; recapSeen[fp] = true end

                -- 把这条来源事件的全部字段打出来，排查名字是否取自错位字段 / 另有全名字段
                local fields = {}
                for k, v in pairs(e) do
                    fields[#fields + 1] = SafeStr(k) .. "=" .. type(v) .. ":" .. SafeStr(v)
                end
                ns.Debug("  来源字段：" .. Join(fields, ", "))
                local info = cacheByGUID[guid]
                -- 名字可信度：明文能在姓名板缓存里对上才用明文；对不上（残缺/错位字段）就回退 GUID 缓存的全名
                local n
                if type(name) == "string" and name ~= "" and LookupCacheByName(name) then
                    n = name
                elseif info and info.name then
                    n = info.name
                else
                    n = name
                end
                local entry = Record(n, "death", guid, nil, "recap")
                if entry then
                    CheckCamping(entry)
                    ns.Log("死亡记录：" .. entry.name, "death")
                end
                return true

            elseif type(name) == "string" and name ~= "" and LookupCacheByName(name) then
                local info2 = LookupCacheByName(name)
                local entry = Record(info2.name, "death", info2.guid, nil, "recap")
                if entry then
                    CheckCamping(entry)
                    ns.Log("死亡记录（按缓存匹配）：" .. entry.name, "death")
                end
                return true
            end
        end
    end

    ns.Debug("死亡回顾里没有找到玩家来源")
    return false
end

--------------------------------------------------------------
-- 姓名板：缓存资料 + 仇人接近提醒 + 视野内敌情
--------------------------------------------------------------
-- 「敌情条」的数据源：此刻姓名板范围内还挂着的仇人，按 GUID 记着。
-- 名字板添加时进、移除时出，所以条上的名字和人真的在不在你眼前是一致的。
ns.nearby = ns.nearby or {}

local function NearbyAdd(guid, name, deaths, star)
    if not guid or type(guid) ~= "string" or not guid:find("^Player%-") then return end
    local cur = ns.nearby[guid]
    ns.nearby[guid] = {
        name   = name,
        deaths = deaths,
        star   = star and true or false,
        t      = time(),
        since  = (cur and cur.since) or time(),
    }
    ns.Notify("nearby")
end

local function NearbyDrop(guid)
    if guid and ns.nearby[guid] then
        ns.nearby[guid] = nil
        ns.Notify("nearby")
    end
end

function ns.GetNearby()
    local out, now = {}, time()
    for g, v in pairs(ns.nearby) do
        -- 兜底：移除事件万一漏了，在视野里挂了超过 5 分钟就当已经离开
        if (now - (v.since or now)) > 300 then
            ns.nearby[g] = nil
        else
            out[#out + 1] = v
        end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
    return out
end

local function HandlePlate(unit)
    if not KillListDB or not KillListDB.settings or not PLAYERS then return end

    -- 无条件登记 unit → GUID + 名字：REMOVED 触发时 unit 已经失效，只能提前存。
    -- 不能等确认是玩家再存 —— 灰名小号等情况下 UnitIsPlayer 可能给 nil，
    -- 那样移除时就既没 GUID 也没名字，整条击杀直接丢掉
    ns.plateUnitGUID[unit] = UnitGUID(unit)
    ns.plateUnitName[unit] = BestName(unit)

    if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end

    local info = CacheUnit(unit)
    if not info then return end
    if info.guid then ns.plateUnitGUID[unit] = info.guid end

    -- 按名字或 GUID 找已有条目，名字变长（补上姓）时顺手迁移键名
    local e, oldKey = FindEntry(info.name, info.guid)
    local plateGUID = info.guid or ns.plateUnitGUID[unit]
    if not e then
        -- 不是名单里的人，顺手把它从敌情条里摘掉（可能是被删掉的条目）
        NearbyDrop(plateGUID)
        return
    end
    EnsureName(e, oldKey, info.name)

    if info.level and info.level > 0 then e.level = info.level end
    e.class = info.class or e.class
    e.race  = info.race  or e.race
    ns.Notify("update")

    -- 敌情条：只要他杀过你且没被忽略，就挂在视野内直到血条消失
    if (e.deaths or 0) > 0 and not e.ignored then
        NearbyAdd(plateGUID, e.name, e.deaths, e.star)
    else
        NearbyDrop(plateGUID)
    end

    if not KillListDB.settings.nameplate then return end
    if (e.deaths or 0) > 0 and not e.ignored then
        local now = time()
        if not e.lastWarn or (now - e.lastWarn) > KillListDB.settings.nearbyWarn then
            e.lastWarn = now
            local extra = e.star and "，重点目标" or ""
            print(format("|cffff3333[记仇]|r 附近出现 %s（杀过你 %d 次%s）",
                e.name, e.deaths, extra))
            ns.Log(format("附近出现 %s（杀过你 %d 次%s）", e.name, e.deaths, extra), "warn")
            -- 打架时没人看聊天框：同时走声音 + 屏幕中央文字
            if ns.NearbyAlert then
                ns.NearbyAlert(e.name, e.deaths, e.star == true)
            end
        end
    end
end

local function CacheCurrentUnits()
    for _, u in ipairs({ "target", "mouseover", "focus" }) do
        if UnitExists(u) and UnitIsPlayer(u) and not UnitIsUnit(u, "player") then
            CacheUnit(u)
        end
    end
end

local function HandlePlateGone(unit)
    local guid = (ns.plateUnitGUID and ns.plateUnitGUID[unit]) or UnitGUID(unit)
    local seenName = ns.plateUnitName and ns.plateUnitName[unit]
    ns.plateUnitGUID[unit] = nil
    ns.plateUnitName[unit] = nil
    if not guid or type(guid) ~= "string" or not guid:find("^Player%-") then return end

    -- 血条消失 = 离开视野（或者被打死了，那种情况击杀记录另走一条链路）
    NearbyDrop(guid)

    local info = cacheByGUID[guid]
    local name = (info and info.name) or seenName
    if not name or name == "" then return end

    ns.plateGone[guid] = { name = name, guid = guid, t = time() }

    -- 顺手清掉 30 秒前的
    local now = time()
    for g, v in pairs(ns.plateGone) do
        if (now - v.t) > 30 then ns.plateGone[g] = nil end
    end
end

--------------------------------------------------------------
-- 对外接口
--------------------------------------------------------------
function ns.GetList(kind, keyword, includeIgnored)
    local out = {}
    if not KillListDB or not PLAYERS then return out end

    local kw = keyword and string.lower(keyword:gsub("^%s+", ""):gsub("%s+$", "")) or ""
    if kw == "" then kw = nil end

    for _, p in pairs(PLAYERS) do
        local count = (kind == "kill") and (p.kills or 0) or (p.deaths or 0)
        if count > 0 then
            if includeIgnored or not p.ignored then
                if not kw or (p.name and string.lower(p.name):find(kw, 1, true)) then
                    out[#out + 1] = p
                end
            end
        end
    end

    table.sort(out, function(a, b)
        local sa = a.star and 1 or 0
        local sb = b.star and 1 or 0
        if sa ~= sb then return sa > sb end

        local ca = (kind == "kill") and (a.kills or 0) or (a.deaths or 0)
        local cb = (kind == "kill") and (b.kills or 0) or (b.deaths or 0)
        if ca ~= cb then return ca > cb end

        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)

    return out
end

function ns.GetStats()
    local kills, deaths, n = 0, 0, 0
    if not KillListDB or not PLAYERS then return 0, 0, 0 end
    for _, p in pairs(PLAYERS) do
        kills  = kills  + (p.kills or 0)
        deaths = deaths + (p.deaths or 0)
        n      = n + 1
    end
    return kills, deaths, n
end

-- 今天 / 本周的战绩。按 history 里每条的时间戳现算，不额外占存档空间
local function StartOfDay()
    local ok, t = pcall(date, "*t")
    if not ok or type(t) ~= "table" or not t.hour then
        return time() - 86400          -- 拿不到本地时间就退回「最近 24 小时」
    end
    return time() - (t.hour * 3600 + t.min * 60 + t.sec)
end

local function StartOfWeek()
    local ok, t = pcall(date, "*t")
    if not ok or type(t) ~= "table" or not t.wday then
        return time() - 7 * 86400
    end
    -- wday：1=周日 2=周一 …… 7=周六，这里按「周一为一周开始」
    local daysFromMonday = (t.wday == 1) and 6 or (t.wday - 2)
    return StartOfDay() - daysFromMonday * 86400
end

function ns.GetPeriodStats()
    local todayStart, weekStart = StartOfDay(), StartOfWeek()
    local kt, dt, kw, dw = 0, 0, 0, 0

    local players = PLAYERS or {}
    for _, e in pairs(players) do
        if type(e) == "table" and type(e.history) == "table" then
            for _, h in ipairs(e.history) do
                if type(h) == "table" and type(h.t) == "number" and h.t >= weekStart then
                    local isKill = (h.kind == "kill")
                    if isKill then kw = kw + 1 else dw = dw + 1 end
                    if h.t >= todayStart then
                        if isKill then kt = kt + 1 else dt = dt + 1 end
                    end
                end
            end
        end
    end

    return kt, dt, kw, dw
end

-- 彻底清空名单（测试期从零开始用）
function ns.Reset()
    for k in pairs(PLAYERS) do PLAYERS[k] = nil end
    recentKill  = {}
    recentDeath = {}
    ns.Notify("record")
    print("|cff8ab4ff[记仇]|r 名单已清空，从现在开始记真的了。")
end

-- 手动清掉非玩家痕迹
function ns.Clean()
    local n = PurgeGarbage()
    print(format("|cff8ab4ff[记仇]|r 清掉了 %d 条无效记录。", n))
    ns.Notify("record")
    return n
end

-- 姓名接口诊断：对着一个玩家敲 /kl name，把各接口给的名字打出来
function ns.DumpName()
    print("|cff8ab4ff[记仇]|r 姓名接口诊断（先选中一个玩家当目标）")
    local unit = "target"
    print("  target 存在：" .. ((UnitExists and UnitExists(unit)) and "是" or "否"))
    print("  UnitName：" .. tostring(select(1, UnitName(unit))))
    print("  UnitName(true)：" .. tostring(select(1, UnitName(unit, true))))
    print("  UnitFullName：" .. tostring(select(1, (UnitFullName and UnitFullName(unit)) or nil)))
    print("  GetUnitName(true)：" .. tostring((GetUnitName and GetUnitName(unit, true)) or nil))
    print("  UnitGUID：" .. tostring(UnitGUID(unit)))
    print("  本插件最终采用：" .. tostring(BestName(unit)))
end

function ns.BuildExport(kind)
    local list  = ns.GetList(kind, nil, true)
    local label = (kind == "kill") and "我杀过的" or "杀过我的"
    local lines = { format("【%s】共 %d 人（%s 导出）", label, #list, date("%Y-%m-%d")) }

    for i, p in ipairs(list) do
        local n = (kind == "kill") and (p.kills or 0) or (p.deaths or 0)
        local extra = p.star and "★" or ""
        lines[#lines + 1] = format("%d. %s · %d 次 · 最近 %s",
            i, p.name .. extra, n, ns.TimeAgo(p.lastSeen))
    end

    if #list == 0 then lines[#lines + 1] = "（暂无记录）" end
    return table.concat(lines, "\n")
end

function ns.RemovePlayer(entry)
    if entry and entry.key and KillListDB then
        PLAYERS[entry.key] = nil
        ns.Notify("record")
    end
end

-- 手动补记：自动链路万一漏了（比如杀灰名小号没有荣誉），用这个补
function ns.AddManual(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local guid
    if name == "" then
        -- 没给名字：自动取当前选中目标，不用手敲全名
        local okN, tName = pcall(BestName, "target")
        local okG, tGuid = pcall(UnitGUID, "target")
        local okP, isPlayer = pcall(UnitIsPlayer, "target")
        local okU, isMe = pcall(UnitIsUnit, "target", "player")
        name = (okN and type(tName) == "string") and tName or ""
        guid = (okG and type(tGuid) == "string") and tGuid or nil
        if name == "" then
            print("|cff8ab4ff[记仇]|r 用法：/kl add 名字；或先选中对方玩家再 /kl add（自动取当前目标）")
            return
        end
        if (okP and not isPlayer) or (okU and isMe) then
            print("|cff8ab4ff[记仇]|r 当前目标不是敌方玩家，未补记")
            return
        end
    end
    local info = LookupCacheByName(name)
    if not guid and info then guid = info.guid end
    local e = Record(info and info.name or name, "kill", guid, true, "manual")
    if e then
        print("|cff8ab4ff[记仇]|r 已补记一条击杀：" .. e.name)
        ns.Log("手动补记击杀：" .. e.name, "kill")
    else
        print("|cff8ab4ff[记仇]|r 没记上（名字无效，或这是你自己/队友）")
    end
end

-- 名单条目右键：对已有的人直接补记一条击杀
function ns.ManualKill(entry)
    if type(entry) ~= "table" or not entry.name then return end
    local e = Record(entry.name, "kill", entry.guid, true, "manual")
    if e then
        print("|cff8ab4ff[记仇]|r 已补记击杀：" .. e.name)
        ns.Log("手动补记击杀（右键）：" .. e.name, "kill")
    else
        print("|cff8ab4ff[记仇]|r 没记上（自己/队友或名字无效）")
    end
end

-- 供界面层查询：按 GUID 或名字找名单里的人（鼠标提示、后续的功能都靠它）
ns.BestName = BestName
function ns.FindPlayer(guid, name)
    if not PLAYERS then return nil end
    local e = FindEntry(name or "", guid)
    if e then return e end
    -- 名字是半名、GUID 也对不上时，再借姓名板缓存换一次全名
    if guid then
        local info = cacheByGUID[guid]
        if info and info.name then
            return FindEntry(info.name, guid)
        end
    end
    return nil
end

--------------------------------------------------------------
-- 环境诊断
--------------------------------------------------------------
function ns.PrintEnv()
    local ver, build, _, toc = GetBuildInfo()
    print(format("|cff8ab4ff[记仇]|r 客户端 %s · build %s · interface %s",
        tostring(ver), tostring(build), tostring(toc)))
    print("|cff8ab4ff[记仇]|r 我的 GUID：" .. tostring(UnitGUID("player")))
    print("|cff8ab4ff[记仇]|r 消息事件：战斗信息=" .. tostring(ns.miscOK) .. " · 系统消息=" .. tostring(ns.systemOK))
    print("|cff8ab4ff[记仇]|r 命中消息=" .. tostring(ns.selfHitsOK) .. " · 法术命中=" .. tostring(ns.selfSpellsOK)
        .. " · 宠物命中=" .. tostring(ns.petHitsOK) .. " · 宠物法术=" .. tostring(ns.petSpellsOK)
        .. " · PVP击杀数=" .. tostring(ns.pvpKillsOK) .. " · 姓名板移除=" .. tostring(ns.plateGoneOK) .. " · 选中变化=" .. tostring(ns.targetOK))

    local s = KillListDB and KillListDB.settings
    print(format("|cff8ab4ff[记仇]|r 姓名板 %s · 调试 %s",
        (s and s.nameplate) and "开" or "关",
        (s and s.debug) and "开" or "关"))

    print("|cff8ab4ff[记仇]|r 旧战斗日志接口：" ..
        (CombatLogGetCurrentEventInfo and "存在" or "已被移除（正常）"))
    print("|cff8ab4ff[记仇]|r PARTY_KILL 事件：" ..
        (ns.partyKillOK and "可注册" or "不可用"))
    print("|cff8ab4ff[记仇]|r 死亡回顾 C_DeathRecap：" ..
        ((C_DeathRecap and C_DeathRecap.GetRecapEvents) and "存在" or "不存在"))
    print("|cff8ab4ff[记仇]|r 荣誉击杀模板：" ..
        (GetHonorPattern() and ("已解析 → " .. GetHonorPattern()) or "缺失"))
    -- 更新后把模板原文也打出来：模板被裁成什么样、名字占位符还在不在，一眼看清
    print("|cff8ab4ff[记仇]|r honor 模板原文：COMBATLOG_HONORGAIN=" .. tostring(_G["COMBATLOG_HONORGAIN"])
        .. " · COMBATLOG_PVPKILL=" .. tostring(_G["COMBATLOG_PVPKILL"]))
    print("|cff8ab4ff[记仇]|r 声音接口：PlaySound=" .. tostring(PlaySound ~= nil)
        .. " · PlaySoundFile=" .. tostring(PlaySoundFile ~= nil)
        .. " · 当前音源 " .. tostring((s and s.alertSound) or 1)
        .. "（/kl snd 挨个试）")
    local cvOK, cvAll = pcall(GetCVar, "Sound_EnableAllSound")
    local cvSFX = select(2, pcall(GetCVar, "Sound_EnableSFX"))
    local cvMV  = select(2, pcall(GetCVar, "Sound_MasterVolume"))
    local cvSV  = select(2, pcall(GetCVar, "Sound_SFXVolume"))
    print("|cff8ab4ff[记仇]|r 声音开关：总音=" .. tostring(cvOK and cvAll)
        .. " · 音效=" .. tostring(cvSFX)
        .. " · 主音量=" .. tostring(cvMV)
        .. " · 音效音量=" .. tostring(cvSV))

    local k, d, n = ns.GetStats()
    print(format("|cff8ab4ff[记仇]|r 名单 %d 人 · 击杀 %d · 死亡 %d", n, k, d))

    -- 本服没有 GetPVPKills，别的可能在。挨个试一遍，能用的直接显示数值
    local probes = {
        "GetPVPKills", "GetPVPDeaths", "GetHonorKills", "GetPVPHonor", "GetPVPRankProgress",
        "GetNumBattlefieldScores", "GetBattlefieldScore", "GetBattlefieldTeamInfo", "GetBattlefieldWinner",
    }
    local found = {}
    for _, fn in ipairs(probes) do
        local f = _G[fn]
        if type(f) == "function" then
            local ok, a, b = pcall(f)
            found[#found + 1] = fn .. "() → "
                .. (ok and (tostring(a) .. (b ~= nil and (" / " .. tostring(b)) or ""))
                    or ("报错 " .. tostring(a)))
        end
    end
    print("|cff8ab4ff[记仇]|r PVP 计数接口：" ..
        (#found > 0 and table.concat(found, " · ") or "一个都不存在"))

    -- 新版记分板：旧接口报错提示里写的是 C_PvPScoreInfo(offsetindex)，
    -- 探测这个命名空间是 table 还是 function、有哪些成员
    if type(C_PvPScoreInfo) == "table" then
        local members = {}
        for k, v in pairs(C_PvPScoreInfo) do
            members[#members + 1] = tostring(k) .. ":" .. type(v)
        end
        print("|cff8ab4ff[记仇]|r 记分板 C_PvPScoreInfo：table，成员 " ..
            (#members > 0 and table.concat(members, ", ") or "（空表）"))
    else
        print("|cff8ab4ff[记仇]|r 记分板 C_PvPScoreInfo：" .. type(C_PvPScoreInfo))
    end
end

--------------------------------------------------------------
-- 诊断摘要：一小段可以直接贴给作者看的文本
-- 报问题时让玩家点「复制诊断信息」，比教他敲 /kl env 友好
--------------------------------------------------------------
local function YN(v)
    if v == true then return "可用" end
    if v == nil then return "未测" end
    if v == false then return "禁用" end
    return "报错"
end

function ns.DiagText()
    local ver, build, _, toc = GetBuildInfo()
    local lines = {}

    lines[#lines + 1] = format("记仇 %s 诊断 · 客户端 %s build %s · interface %s",
        tostring(ns.version), tostring(ver), tostring(build), tostring(toc))

    local me = UnitName("player") or "?"
    local _, class = UnitClass("player")
    local okLv, lv = pcall(UnitLevel, "player")
    lines[#lines + 1] = format("角色：%s · %s · %s级", me, tostring(class or "?"),
        tostring(okLv and lv or "?"))

    lines[#lines + 1] = "接口：PARTY_KILL " .. YN(ns.partyKillOK)
        .. " · 死亡回顾 " .. ((C_DeathRecap and C_DeathRecap.GetRecapEvents) and "可用" or "不存在")
        .. " · 荣誉模板 " .. (GetHonorPattern() and "已解析" or "缺失")
        .. " · 姓名板移除 " .. YN(ns.plateGoneOK)
        .. " · PVP击杀数 " .. YN(ns.pvpKillsOK)
        .. " · 命中消息 " .. YN(ns.selfHitsOK)

    -- 新版记分板命名空间：旧接口报错提示里出现的 C_PvPScoreInfo
    local scoreKind = type(C_PvPScoreInfo)
    if scoreKind == "table" then
        local members = {}
        for k, v in pairs(C_PvPScoreInfo) do members[#members + 1] = tostring(k) .. ":" .. type(v) end
        lines[#lines + 1] = "记分板 C_PvPScoreInfo：table，成员 " ..
            (#members > 0 and table.concat(members, ", ") or "（空表）")
    else
        lines[#lines + 1] = "记分板 C_PvPScoreInfo：" .. tostring(scoreKind)
    end

    local s = (KillListDB and KillListDB.settings) or {}
    lines[#lines + 1] = format("设置：姓名板 %s · 提示音 %s · 屏幕提示 %s · 敌情条 %s · 调试 %s",
        (s.nameplate and "开" or "关"), tostring(s.alertSound or 1),
        (s.nearbyScreen ~= false and "开" or "关"),
        (s.enemyBar ~= false and "开" or "关"),
        (s.debug and "开" or "关"))

    local k, d, n = ns.GetStats()
    lines[#lines + 1] = format("数据：名单 %d 人 · 击杀 %d · 死亡 %d", n, k, d)

    -- 场景判定：现在算野外还是战场/竞技场，以及判定来源；再把 GetInstanceInfo 原始各段打出来核对
    local inPvp, pvpSrc = InPvpInstance()
    local pvpText = inPvp == nil and "不确定" or (inPvp and "战场/竞技场" or "野外")
    lines[#lines + 1] = format("场景判定：%s（%s）", pvpText, SafeStr(pvpSrc))
    local okInst, inst = pcall(function() return { GetInstanceInfo() } end)
    if okInst and type(inst) == "table" then
        local parts = {}
        for i = 1, math.min(#inst, 6) do parts[#parts + 1] = i .. "=" .. SafeStr(inst[i]) end
        lines[#lines + 1] = "  GetInstanceInfo：" .. Join(parts, ", ")
    end

    -- 分桶诊断：确认写入和读取落在同一个角色桶，避免名字全/半不一致把数据写进空桶
    local curKey = select(1, CharKey())
    local direct = 0
    if PLAYERS then for _ in pairs(PLAYERS) do direct = direct + 1 end end
    lines[#lines + 1] = format("分桶：当前 key=%s · 内存名单 %d 条", SafeStr(curKey), direct)
    if KillListDB and type(KillListDB.chars) == "table" then
        local buckets = {}
        for bk, bv in pairs(KillListDB.chars) do
            local cnt = 0
            if type(bv) == "table" and type(bv.players) == "table" then
                for _ in pairs(bv.players) do cnt = cnt + 1 end
            end
            buckets[#buckets + 1] = SafeStr(bk) .. "(" .. cnt .. ")"
        end
        lines[#lines + 1] = "存档桶：" .. (#buckets > 0 and Join(buckets, ", ") or "（无）")
    end

    -- 逐条内存清单：名字 / GUID / 击杀 / 死亡 / 是否忽略，便于核对哪个人在表里、计数多少
    if PLAYERS then
        local rows = {}
        for _, e in pairs(PLAYERS) do
            if type(e) == "table" then
                rows[#rows + 1] = format("  · %s [%s] 杀%d 死%d%s",
                    SafeStr(e.name), SafeStr(e.guid or "-"),
                    e.kills or 0, e.deaths or 0,
                    e.ignored and " [忽略]" or "")
            end
        end
        if #rows > 0 then
            lines[#lines + 1] = "内存条目："
            for _, r in ipairs(rows) do lines[#lines + 1] = r end
        end
    end

    return table.concat(lines, "\n")
end

-- 探针窗汇总：环境诊断 + PARTY_KILL 留档 + 全部信号原始参数，一窗可复制导出
-- 每段各自容错：某一段报错不拖垮整窗，错误文本直接写进结果里方便排查
function ns.ProbeText()
    local function safe(fn)
        if type(fn) ~= "function" then return "（接口缺失）" end
        local ok, txt = pcall(fn)
        if ok and type(txt) == "string" then return txt end
        return "（本段读取失败：" .. tostring(txt) .. "）"
    end
    local parts = { safe(ns.DiagText) }
    parts[#parts + 1] = "\n===== PARTY_KILL 记录 =====\n" .. safe(ns.PartyKillText)
    parts[#parts + 1] = "\n===== 信号原始参数 =====\n" .. safe(ns.RawText)
    return table.concat(parts, "\n")
end

--------------------------------------------------------------
-- 事件注册
--------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
local okMisc, errMisc = pcall(frame.RegisterEvent, frame, "CHAT_MSG_COMBAT_MISC_INFO")
ns.miscOK = okMisc and true or tostring(errMisc)
local okSys, errSys = pcall(frame.RegisterEvent, frame, "CHAT_MSG_SYSTEM")
ns.systemOK = okSys and true or tostring(errSys)
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")

-- 没有的事件用 pcall 注册，避免直接红字报错
ns.partyKillOK = pcall(frame.RegisterEvent, frame, "PARTY_KILL")
ns.pvpKillsOK  = pcall(frame.RegisterEvent, frame, "PLAYER_PVP_KILLS_CHANGED")
ns.selfHitsOK   = pcall(frame.RegisterEvent, frame, "CHAT_MSG_COMBAT_SELF_HITS")
ns.selfSpellsOK = pcall(frame.RegisterEvent, frame, "CHAT_MSG_COMBAT_SELF_SPELLS")
ns.petHitsOK    = pcall(frame.RegisterEvent, frame, "CHAT_MSG_COMBAT_PET_HITS")
ns.petSpellsOK  = pcall(frame.RegisterEvent, frame, "CHAT_MSG_COMBAT_PET_SPELLS")
ns.plateGoneOK  = pcall(frame.RegisterEvent, frame, "NAME_PLATE_UNIT_REMOVED")
ns.targetOK     = pcall(frame.RegisterEvent, frame, "PLAYER_TARGET_CHANGED")
pcall(frame.RegisterEvent, frame, "UPDATE_MOUSEOVER_UNIT")
pcall(frame.RegisterEvent, frame, "ADDON_ACTION_BLOCKED")
pcall(frame.RegisterEvent, frame, "ADDON_ACTION_FORBIDDEN")
-- 脱离战斗后补读一次死亡回顾，兜底战场 recap 填充过晚（Record 有 15 秒去重，不会重复记）
pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED")
-- 战场是独立副本，事件流转和野外不同；先把战场系统消息也留档，看里面有没有击杀通报
pcall(frame.RegisterEvent, frame, "CHAT_MSG_BG_SYSTEM_NEUTRAL")
pcall(frame.RegisterEvent, frame, "CHAT_MSG_BG_SYSTEM_ALLIANCE")
pcall(frame.RegisterEvent, frame, "CHAT_MSG_BG_SYSTEM_HORDE")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON then
            InitDB()
            local n = PurgeGarbage()
            if n > 0 then
                print(format("|cff8ab4ff[记仇]|r 清理了 %d 条老版本的无效记录（名字被存成了 GUID）", n))
            end
            ns.Notify("init")
        end

    elseif event == "PLAYER_LOGIN" then
        -- 登录流程早期可能还取不到角色名，这里再定一次，确保 PLAYERS 指向当前角色
        pcall(InitDB)
        ns.Notify("login")

    elseif event == "PARTY_KILL" then
        ns.NoteRaw("PARTY_KILL", ...)
        pcall(HandlePartyKill, ...)

    elseif event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_COMBAT_SELF_SPELLS"
        or event == "CHAT_MSG_COMBAT_PET_HITS" or event == "CHAT_MSG_COMBAT_PET_SPELLS" then
        local msg = ...
        pcall(HandleHit, msg)

    elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
        pcall(CacheCurrentUnits)

    elseif event == "PLAYER_PVP_KILLS_CHANGED" then
        ns.NoteRaw("PVP_KILLS", ...)
        -- 这个计数器不可靠：队友的战果、以及灰名/宠物的判定都可能让它动；触发时 target 已被清空，
        -- 根本拿不到是谁。所以它只当「发生过一次 PVP 击杀」的痕迹，绝不拿它写名单。
        -- 2.1.22 实机踩过：只打了几枪并没打死的人，被这条路径拿「最近命中」猜成了我的击杀。
        -- 真正写名单只认带名字或带 Player GUID 的信号：PARTY_KILL / 荣誉消息 / 「你 杀死了 XXX」。
        local guess = ns.lastHit and ns.lastHit.name
        ns.Log(format("收到 PVP 击杀数变化事件（目标=%s）· 最近命中=%s · 未确认是谁，不写名单（可用 /kl add 名字 补记）",
            tostring(BestName("target")), tostring(guess or "无")), "info")

    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        ns.NoteRaw("HONOR_GAIN", ...)
        local msg = ...
        pcall(HandleHonorGain, msg)

    elseif event == "CHAT_MSG_COMBAT_MISC_INFO" then
        ns.NoteRaw("MISC_INFO", ...)
        local msg = ...
        pcall(function()
            if type(msg) == "string" and (msg:find("杀死") or msg:find("死亡") or msg:find("击杀")
                or msg:find("击败") or msg:find("消灭") or msg:find("荣誉")) then
                ns.Log("[原文·战斗信息] " .. msg, "info")
            end
        end)
        pcall(HandleMiscInfo, msg)

    elseif event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" or event == "CHAT_MSG_BG_SYSTEM_ALLIANCE"
        or event == "CHAT_MSG_BG_SYSTEM_HORDE" then
        ns.NoteRaw("BG_SYS", ...)
        local msg = ...
        pcall(function()
            if type(msg) == "string" and msg ~= "" then
                ns.Log("[原文·战场消息] " .. msg, "info")
            end
        end)

    elseif event == "CHAT_MSG_SYSTEM" then
        ns.NoteRaw("SYSTEM", ...)
        local msg = ...
        pcall(function()
            if type(msg) == "string" and (msg:find("杀死") or msg:find("击杀")
                or msg:find("死亡") or msg:find("击败") or msg:find("消灭")) then
                ns.Log("[原文·系统] " .. msg, "info")
            end
        end)
        pcall(HandleMiscInfo, msg)

    elseif event == "PLAYER_DEAD" then
        -- PLAYER_DEAD 在某些情况下会连着触发两次，用 deadPending 挡住重复
        if ns.deadPending then return end
        ns.deadPending = true
        -- 战场里死亡回顾数据可能晚到，1 秒没读到凶手就隔 1.5 秒再试，最多 3 次
        local attempts = 0
        local function tryRecap()
            attempts = attempts + 1
            local ok, found = pcall(RecordDeathFromRecap)
            if not ok then
                ns.Debug("死亡回顾失败：" .. tostring(found))
            end
            if found or attempts >= 3 then
                ns.deadPending = false
            else
                C_Timer.After(1.5, tryRecap)
            end
        end
        C_Timer.After(1.0, tryRecap)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- 脱离战斗再补读一次死亡回顾，兜底战场 recap 填充过晚
        pcall(RecordDeathFromRecap)

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        pcall(HandlePlateGone, unit)

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        pcall(HandlePlate, unit)

    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- 这两个事件是全局广播：任何插件被拦都会通知到我们。
        -- 不过滤就会把别人的报错当自己的刷屏——Questie 每摆一个按钮碰一次
        -- SetPassThroughButtons，实测能把聊天框刷满一整屏。
        local who, fn = ...
        local whoS = who and tostring(who) or nil
        if not whoS or whoS:find(ADDON, 1, true) then
            print(format("|cffff3333[记仇 拦截]|r 插件 %s 调用了受限函数：%s",
                tostring(who), tostring(fn)))
            ns.Log(format("本插件调用了受限函数：%s", tostring(fn)), "warn")
        elseif KillListDB and KillListDB.settings and KillListDB.settings.debug then
            ns.Log(format("别的插件被拦（已忽略）：%s · %s", whoS, tostring(fn)), "info")
        end
    end
end)