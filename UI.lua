--[[
    记仇 · 界面层
    名单浏览、搜索、标记、备注、导出
]]

local ADDON, ns = ...

local ROW_H = 26

local kind       = "death"   -- death = 杀过我的；kill = 我杀过的
local selected   = nil
local filterText = ""

local RefreshList, UpdateDetail, SelectEntry, SetKind, ShowExport
local emptyText, statFS, periodFS

--------------------------------------------------------------
-- 主窗口
--------------------------------------------------------------
local frame = CreateFrame("Frame", "KillListMainFrame", UIParent, "BackdropTemplate")
frame:SetSize(500, 600)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetFrameStrata("DIALOG")
frame:SetToplevel(true)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
frame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 20,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
})
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", frame, "TOP", 0, -13)
title:SetText("|cffffd700记仇|r  ·  仇人名单")

local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
closeBtn:SetScript("OnClick", function() frame:Hide() end)

local btnOpenLog = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btnOpenLog:SetSize(46, 20)
btnOpenLog:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -12)
btnOpenLog:SetText("日志")
btnOpenLog:SetScript("OnClick", function() if ns.ToggleLog then ns.ToggleLog() end end)

local btnOpenSet = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btnOpenSet:SetSize(46, 20)
btnOpenSet:SetPoint("RIGHT", btnOpenLog, "LEFT", -4, 0)
btnOpenSet:SetText("设置")
btnOpenSet:SetScript("OnClick", function() if ns.OpenSettings then ns.OpenSettings() end end)

--------------------------------------------------------------
-- 两个页签
--------------------------------------------------------------
local tabDeath = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
tabDeath:SetSize(150, 24)
tabDeath:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -38)
tabDeath:SetScript("OnClick", function() SetKind("death") end)

local tabKill = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
tabKill:SetSize(150, 24)
tabKill:SetPoint("LEFT", tabDeath, "RIGHT", 8, 0)
tabKill:SetScript("OnClick", function() SetKind("kill") end)

local mark = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
mark:SetText("|cffffd700▲|r")

--------------------------------------------------------------
-- 搜索
--------------------------------------------------------------
local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
searchLabel:SetText("搜索")

local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
search:SetSize(300, 22)
search:SetPoint("TOPLEFT", frame, "TOPLEFT", 44, -72)
search:SetAutoFocus(false)
search:SetTextInsets(4, 4, 0, 0)
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
search:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    filterText = self:GetText() or ""
    if RefreshList then RefreshList() end
end)

searchLabel:SetPoint("RIGHT", search, "LEFT", -8, 0)

--------------------------------------------------------------
-- 列表
--------------------------------------------------------------
local scroll = CreateFrame("ScrollFrame", "KillListScrollFrame", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -102)
scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -38, 208)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(1, 1)
scroll:SetScrollChild(content)

local rowPool = {}

local function CreateRow(i)
    local r = CreateFrame("Button", nil, content)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * ROW_H)

    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.03)

    r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.sel:SetAllPoints()
    r.sel:SetColorTexture(0.2, 0.55, 1, 0.28)
    r.sel:Hide()

    r.nameFS = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.nameFS:SetPoint("LEFT", r, "LEFT", 8, 0)
    r.nameFS:SetWidth(168)
    r.nameFS:SetJustifyH("LEFT")
    r.nameFS:SetWordWrap(false)

    r.metaFS = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.metaFS:SetPoint("LEFT", r, "LEFT", 180, 0)
    r.metaFS:SetWidth(102)
    r.metaFS:SetJustifyH("LEFT")
    r.metaFS:SetWordWrap(false)

    r.countFS = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.countFS:SetPoint("LEFT", r, "LEFT", 288, 0)
    r.countFS:SetWidth(82)
    r.countFS:SetJustifyH("LEFT")

    r.whenFS = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.whenFS:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.whenFS:SetJustifyH("RIGHT")

    r:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, 0.12) end)
    r:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0.03) end)
    r:SetScript("OnClick", function(self)
        if self.entry then SelectEntry(self.entry) end
    end)

    return r
end

local function UpdateRow(r, entry, index)
    r.entry = entry
    r.bg:SetColorTexture(1, 1, 1, (index % 2 == 0) and 0.05 or 0.02)

    if selected == entry then
        r.sel:Show()
    else
        r.sel:Hide()
    end

    local color = entry.class and RAID_CLASS_COLORS[entry.class]
    if color then
        r.nameFS:SetTextColor(color.r, color.g, color.b)
    else
        r.nameFS:SetTextColor(1, 0.82, 0)
    end

    local prefix = ""
    if entry.ignored then prefix = prefix .. "|cff777777[忽略] |r" end
    if entry.star    then prefix = prefix .. "|cffffd700★ |r" end

    r.nameFS:SetText(prefix .. entry.name)

    local lvl   = (entry.level and entry.level > 0) and (entry.level .. " 级") or "等级未知"
    local guild = entry.guild and (" · " .. entry.guild) or ""
    r.metaFS:SetText(lvl .. guild)

    local n = (kind == "kill") and (entry.kills or 0) or (entry.deaths or 0)
    r.countFS:SetText(((kind == "kill") and "击杀 " or "死亡 ") .. n .. " 次")

    r.whenFS:SetText(ns.TimeAgo(entry.lastSeen))
end

RefreshList = function()
    if not ns.Players() then return end

    local list = ns.GetList(kind, filterText, true)

    content:SetWidth(math.max(100, scroll:GetWidth() - 2))

    for i = 1, #list do
        local r = rowPool[i]
        if not r then
            r = CreateRow(i)
            rowPool[i] = r
        end
        r:Show()
        UpdateRow(r, list[i], i)
    end

    for i = #list + 1, #rowPool do
        rowPool[i]:Hide()
        rowPool[i].entry = nil
    end

    content:SetHeight(math.max(1, #list * ROW_H))

    local cDeath = #ns.GetList("death", nil, false)
    local cKill  = #ns.GetList("kill",  nil, false)
    tabDeath:SetText(format("杀过我的 (%d)", cDeath))
    tabKill:SetText(format("我杀过的 (%d)", cKill))

    local k, d, n = ns.GetStats()
    local me = UnitName("player") or "未知角色"
    statFS:SetText(format("|cffd8b46a%s|r  ·  总击杀 %d  ·  总死亡 %d  ·  名单 %d 人", me, k, d, n))

    if periodFS and ns.GetPeriodStats then
        local kt, dt, kw, dw = ns.GetPeriodStats()
        periodFS:SetText(format("今天 %d 杀 %d 死   ·   本周 %d 杀 %d 死", kt, dt, kw, dw))
    end

    if #list == 0 then
        if not emptyText then
            emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            emptyText:SetPoint("TOP", content, "TOP", 0, -40)
        end
        emptyText:SetText((kind == "death") and "还没有人杀过你。" or "你还没杀过人。")
        emptyText:Show()
    elseif emptyText then
        emptyText:Hide()
    end
end

--------------------------------------------------------------
-- 详情区
--------------------------------------------------------------
local detail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
detail:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -400)
detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 70)
detail:SetBackdrop({
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
detail:SetBackdropColor(0, 0, 0, 0.35)
detail:SetBackdropBorderColor(1, 1, 1, 0.15)

local dName = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dName:SetPoint("TOPLEFT", detail, "TOPLEFT", 2, 0)

local dMeta = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dMeta:SetPoint("TOPLEFT", detail, "TOPLEFT", 2, -26)
dMeta:SetWidth(450)
dMeta:SetJustifyH("LEFT")
dMeta:SetWordWrap(false)

local dNote = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
dNote:SetSize(240, 20)
dNote:SetPoint("TOPLEFT", detail, "TOPLEFT", 4, -48)
dNote:SetAutoFocus(false)
dNote:SetTextInsets(4, 4, 0, 0)
dNote:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
dNote:SetScript("OnEnterPressed", function(self)
    if selected then
        selected.note = self:GetText() or ""
        self:ClearFocus()
        ns.Notify("update")
    end
end)

local dNoteHint = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dNoteHint:SetPoint("LEFT", dNote, "RIGHT", 8, 0)
dNoteHint:SetText("备注，回车保存")

local function MakeDetailButton(text, x)
    local b = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    b:SetSize(84, 22)
    b:SetPoint("TOPLEFT", detail, "TOPLEFT", x, -78)
    b:SetText(text)
    return b
end

local btnStar   = MakeDetailButton("标星", 0)
local btnIgnore = MakeDetailButton("忽略", 90)
local btnDelete = MakeDetailButton("删除", 180)

btnStar:SetScript("OnClick", function()
    if not selected then return end
    selected.star = (not selected.star) or nil
    ns.Notify("update")
    UpdateDetail()
end)

btnIgnore:SetScript("OnClick", function()
    if not selected then return end
    selected.ignored = (not selected.ignored) or nil
    ns.Notify("update")
    UpdateDetail()
end)

btnDelete:SetScript("OnClick", function()
    if not selected then return end
    ns.RemovePlayer(selected)
    selected = nil
    UpdateDetail()
end)

SelectEntry = function(entry)
    selected = entry
    RefreshList()
    UpdateDetail()
end

UpdateDetail = function()
    if not selected then
        dName:SetTextColor(1, 1, 1)
        dName:SetText("|cff777777未选中玩家|r")
        dMeta:SetText("|cff777777点击上方名单中的一行，可标记、写备注、导出|r")
        dNote:Hide()
        dNoteHint:Hide()
        btnStar:Hide()
        btnIgnore:Hide()
        btnDelete:Hide()
        return
    end

    local color = selected.class and RAID_CLASS_COLORS[selected.class]
    if color then
        dName:SetTextColor(color.r, color.g, color.b)
    else
        dName:SetTextColor(1, 0.82, 0)
    end
    dName:SetText(selected.name)

    local parts = {}
    parts[#parts + 1] = (selected.level and selected.level > 0)
        and (selected.level .. " 级") or "等级未知"
    if selected.guild then parts[#parts + 1] = "公会 " .. selected.guild end
    parts[#parts + 1] = format("你杀他 %d 次", selected.kills or 0)
    parts[#parts + 1] = format("他杀你 %d 次", selected.deaths or 0)
    if selected.lastZone then parts[#parts + 1] = "最近：" .. selected.lastZone end

    local SRC_TEXT = {
        honor      = "荣誉消息",
        party_kill = "击杀事件",
        recap      = "死亡回顾",
        victim     = "战斗信息",
        hit        = "战斗日志",
        pvp_kills  = "击杀数",
    }
    if selected.lastSrc and SRC_TEXT[selected.lastSrc] then
        parts[#parts + 1] = "来源：" .. SRC_TEXT[selected.lastSrc]
    end

    dMeta:SetText(table.concat(parts, "   ·   "))

    dNote:Show()
    dNoteHint:Show()
    dNote:SetText(selected.note or "")

    btnStar:Show()
    btnStar:SetText(selected.star and "取消标星" or "标星")

    btnIgnore:Show()
    btnIgnore:SetText(selected.ignored and "取消忽略" or "忽略")

    btnDelete:Show()
    btnDelete:SetText("删除")
end

SetKind = function(k)
    kind     = k
    selected = nil
    RefreshList()
    UpdateDetail()

    mark:ClearAllPoints()
    mark:SetPoint("BOTTOM", (k == "death") and tabDeath or tabKill, "TOP", 0, -2)
end

--------------------------------------------------------------
-- 底部：导出与统计
--------------------------------------------------------------
statFS = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
statFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 28)
statFS:SetText("")

-- 今天 / 本周的即时战绩，放在导出按钮上方一行
periodFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
periodFS:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 52)
periodFS:SetText("")

local btnExport = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btnExport:SetSize(110, 24)
btnExport:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 20)
btnExport:SetText("导出名单")
btnExport:SetScript("OnClick", function() ShowExport() end)

--------------------------------------------------------------
-- 导出窗口
--------------------------------------------------------------
local exportFrame = CreateFrame("Frame", "KillListExportFrame", UIParent, "BackdropTemplate")
exportFrame:SetSize(560, 470)
exportFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
exportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
exportFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 20,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
})
exportFrame:Hide()

local exportTitle = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
exportTitle:SetPoint("TOP", exportFrame, "TOP", 0, -13)
exportTitle:SetText("|cffffd700导出名单|r")

local exportClose = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
exportClose:SetPoint("TOPRIGHT", exportFrame, "TOPRIGHT", -3, -3)
exportClose:SetScript("OnClick", function() exportFrame:Hide() end)

local exportHint = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
exportHint:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 16, -42)
exportHint:SetText("点进输入框按 Ctrl+A 全选、Ctrl+C 复制，可直接贴到群里或攻略站。")

local exportBox = CreateFrame("EditBox", nil, exportFrame, "InputBoxTemplate")
exportBox:SetMultiLine(true)
exportBox:SetAutoFocus(false)
exportBox:SetFontObject(ChatFontNormal)
exportBox:SetSize(528, 380)
exportBox:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 16, -64)
exportBox:SetTextInsets(8, 8, 8, 8)
exportBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    exportFrame:Hide()
end)

ShowExport = function()
    if not KillListDB then return end
    -- 日志窗的「导出」按钮会临时改标题，这里每次都复原本窗口的文案
    exportTitle:SetText("|cffffd700导出名单|r")
    exportHint:SetText("点进输入框按 Ctrl+A 全选、Ctrl+C 复制，可直接贴到群里或攻略站。")
    exportBox:SetText(ns.BuildExport(kind))
    exportFrame:Show()
    exportBox:SetFocus()
    exportBox:HighlightText()
end

--------------------------------------------------------------
-- 日志窗：只显示本插件自己的记录，不跟聊天框混
--------------------------------------------------------------
local LOG_SHOW_MAX = 120
local logFrame, logScroll, logContent, logText, logCountFS

local function ComposeLogText()
    local list = ns.logs or {}
    local start = math.max(1, #list - LOG_SHOW_MAX + 1)
    local out = {}
    for i = start, #list do
        local l = list[i]
        local r = math.floor((l.r or 0.6) * 255)
        local g = math.floor((l.g or 0.6) * 255)
        local b = math.floor((l.b or 0.6) * 255)
        out[#out + 1] = format("|cff777777%s|r  |cff%02x%02x%02x%s|r",
            date("%H:%M", l.t or time()), r, g, b, l.text or "")
    end
    if #out == 0 then
        return "|cff777777还没有记录。进游戏打一场，这里就会开始走流水。|r"
    end
    return table.concat(out, "\n")
end

local function RefreshLog()
    if not logFrame or not logText then return end

    logText:SetText(ComposeLogText())

    local h = logText:GetStringHeight()
    if not h or h <= 0 then h = 20 end
    logContent:SetHeight(h + 12)
    logScroll:SetVerticalScroll(math.max(0, logContent:GetHeight() - logScroll:GetHeight()))

    local list = ns.logs or {}
    if logCountFS then
        logCountFS:SetText(format("共 %d 条，显示最近 %d 条", #list, math.min(#list, LOG_SHOW_MAX)))
    end
end

logFrame = CreateFrame("Frame", "KillListLogFrame", UIParent, "BackdropTemplate")
logFrame:SetSize(430, 340)
logFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 360, -110)
logFrame:SetFrameStrata("DIALOG")
logFrame:SetMovable(true)
logFrame:EnableMouse(true)
logFrame:RegisterForDrag("LeftButton")
logFrame:SetScript("OnDragStart", logFrame.StartMoving)
logFrame:SetScript("OnDragStop", logFrame.StopMovingOrSizing)
logFrame:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
logFrame:SetBackdropColor(0.05, 0.05, 0.06, 0.93)
logFrame:SetBackdropBorderColor(1, 1, 1, 0.18)
logFrame:Hide()

local logTitle = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
logTitle:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 12, -10)
logTitle:SetText("记仇 日志")

local logClose = CreateFrame("Button", nil, logFrame, "UIPanelCloseButton")
logClose:SetPoint("TOPRIGHT", logFrame, "TOPRIGHT", -3, -3)
logClose:SetScript("OnClick", function() logFrame:Hide() end)

logScroll = CreateFrame("ScrollFrame", "KillListLogScroll", logFrame, "UIPanelScrollFrameTemplate")
logScroll:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 10, -32)
logScroll:SetPoint("BOTTOMRIGHT", logFrame, "BOTTOMRIGHT", -32, 44)

logContent = CreateFrame("Frame", nil, logScroll)
logContent:SetSize(360, 20)
logScroll:SetScrollChild(logContent)

logText = logContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
logText:SetPoint("TOPLEFT", logContent, "TOPLEFT", 2, 0)
logText:SetWidth(360)
logText:SetJustifyH("LEFT")
logText:SetWordWrap(true)

logScroll:SetScript("OnSizeChanged", function(self, w)
    if not logText then return end
    local width = math.max(120, (w or 360) - 16)
    logText:SetWidth(width)
    logContent:SetWidth(width)
    RefreshLog()
end)

logCountFS = logFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
logCountFS:SetPoint("BOTTOMRIGHT", logFrame, "BOTTOMRIGHT", -16, 16)

local btnLogClear = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
btnLogClear:SetSize(76, 20)
btnLogClear:SetPoint("BOTTOMLEFT", logFrame, "BOTTOMLEFT", 12, 10)
btnLogClear:SetText("清空")
btnLogClear:SetScript("OnClick", function()
    if ns.ClearLog then ns.ClearLog() end
    RefreshLog()
end)

local btnLogCopy = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
btnLogCopy:SetSize(76, 20)
btnLogCopy:SetPoint("BOTTOMLEFT", logFrame, "BOTTOMLEFT", 96, 10)
btnLogCopy:SetText("导出")
btnLogCopy:SetScript("OnClick", function()
    exportTitle:SetText("记仇 日志")
    exportHint:SetText("按 Ctrl+A 全选，Ctrl+C 复制")
    exportBox:SetText(ComposeLogText())
    exportFrame:Show()
    exportBox:SetFocus()
    exportBox:HighlightText()
end)

-- 有新记录时，窗口开着就实时往下滚
ns.onLog = function()
    if logFrame and logFrame:IsShown() then RefreshLog() end
end

ns.ToggleLog = function()
    if logFrame:IsShown() then
        logFrame:Hide()
    else
        logFrame:Show()
        RefreshLog()
    end
end

--------------------------------------------------------------
-- 仇人接近提示：屏幕中央一行字 + 提示音
-- 打架时聊天框根本看不见，所以这条路才是真正管用的提示
--------------------------------------------------------------
local alertFrame = CreateFrame("Frame", "KillListAlertFrame", UIParent, "BackdropTemplate")
alertFrame:SetSize(560, 46)
alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
alertFrame:SetFrameStrata("FULLSCREEN_DIALOG")
alertFrame:SetBackdrop({
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
alertFrame:SetBackdropColor(0.32, 0.02, 0.02, 0.92)
alertFrame:SetBackdropBorderColor(1.00, 0.25, 0.20, 0.95)
alertFrame:EnableMouse(false)
alertFrame:Hide()

local alertText = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
alertText:SetPoint("CENTER", alertFrame, "CENTER", 0, 0)
alertText:SetJustifyH("CENTER")
alertText:SetWidth(540)
-- 描边大字号：激战中快速扫一眼就能看清
pcall(function()
    local path = GameFontNormalLarge:GetFont()
    alertText:SetFont(path, 24, "OUTLINE")
end)
alertText:SetTextColor(1, 0.93, 0.93)

-- 屏幕四边红晕：声音这条路在这客户端走不通（PlaySound 调用成功但静默），
-- 所以用视觉硬提示补回来。纯色 SetColorTexture 是唯一验证过能渲染的着色方式
local edgeTex = {}
do
    local r, g, b = 0.86, 0.05, 0.03
    local function mk()
        local t = UIParent:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(r, g, b, 0)
        return t
    end
    edgeTex[1] = mk()  -- 上
    edgeTex[1]:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    edgeTex[1]:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    edgeTex[1]:SetHeight(96)
    edgeTex[2] = mk()  -- 下
    edgeTex[2]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    edgeTex[2]:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    edgeTex[2]:SetHeight(96)
    edgeTex[3] = mk()  -- 左
    edgeTex[3]:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    edgeTex[3]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    edgeTex[3]:SetWidth(96)
    edgeTex[4] = mk()  -- 右
    edgeTex[4]:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    edgeTex[4]:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    edgeTex[4]:SetWidth(96)
end

local ALERT_IN, ALERT_HOLD, ALERT_OUT = 0.15, 2.8, 0.85
local VIG_PEAK = 0.42
local alertT = 0

local function SetEdgeAlpha(a)
    for i = 1, 4 do
        if edgeTex[i] then edgeTex[i]:SetAlpha(a) end
    end
end

alertFrame:SetScript("OnUpdate", function(self, dt)
    alertT = alertT + dt

    -- 横幅：淡入 → 停 → 淡出，开头带一次回弹（1.12 → 1）
    if alertT < ALERT_IN then
        self:SetAlpha(alertT / ALERT_IN)
    elseif alertT < ALERT_IN + ALERT_HOLD then
        self:SetAlpha(1)
    elseif alertT < ALERT_IN + ALERT_HOLD + ALERT_OUT then
        self:SetAlpha(1 - (alertT - ALERT_IN - ALERT_HOLD) / ALERT_OUT)
    else
        self:SetAlpha(0)
        self:Hide()
    end
    local sc = 1.12 - 0.12 * math.min(1, alertT / 0.2)
    self:SetScale(sc)

    -- 红晕：0.12 秒冲上来，停 0.4 秒，1.4 秒退干净
    local va
    if alertT < 0.12 then
        va = VIG_PEAK * (alertT / 0.12)
    elseif alertT < 0.5 then
        va = VIG_PEAK
    elseif alertT < 1.9 then
        va = VIG_PEAK * (1 - (alertT - 0.5) / 1.4)
    else
        va = 0
    end
    SetEdgeAlpha(va)
end)

-- 提示音。教训：以前所有调用都带了第二个参数 "Master"，
-- 而本服客户端（和 163UI / AceGUI 一致）只认单参数调用，
-- 多塞一个通道名就静默吞掉——所以这里一律单参数，通道只在 /kl snd 显式测试时才传。
local function KitId(key, fallback)
    local t = _G.SOUNDKIT
    if type(t) == "table" and t[key] then return t[key] end
    return fallback
end

local SOUNDS = {
    { name = "自动（复选框优先）",      kind = "auto" },
    { name = "复选框 叮 856",           kind = "kit",  arg = 856,  kit = "IG_MAINMENU_OPTION_CHECKBOX_ON" },
    { name = "主菜单 852",              kind = "kit",  arg = 852,  kit = "IG_MAINMENU_OPTION" },
    { name = "退出 799",                kind = "kit",  arg = 799,  kit = "GS_TITLE_OPTION_EXIT" },
    { name = "猫叫哨（系统 ogg）",       kind = "file", arg = "Sound\\Character\\EmoteCatCallWhistle02.ogg" },
    { name = "闹钟警告 wav",             kind = "file", arg = "Sound\\Interface\\AlarmClockWarning3.wav" },
    { name = "复选框 wav",               kind = "file", arg = "Sound\\Interface\\igMainMenuOptionCheckBoxOn.wav" },
    { name = "地图标记 wav",             kind = "file", arg = "Sound\\Interface\\MapPing.wav" },
}
ns.SOUNDS = SOUNDS

-- 单参数优先；传了 channel 才走双参数（留给通道排查）
local function FireSound(idx, channel)
    local p = SOUNDS[idx]
    if not p then return "序号无效" end
    local chan = (channel and channel ~= "") and channel or nil

    local function PKit(id)
        if not PlaySound then return false, "PlaySound 不存在" end
        local ok, res
        if chan then ok, res = pcall(PlaySound, id, chan)
        else ok, res = pcall(PlaySound, id) end
        if not ok then return false, "报错：" .. tostring(res) end
        return true, tostring(id)
    end

    local function PFile(path)
        if not PlaySoundFile then return false, "PlaySoundFile 不存在" end
        local ok, res
        if chan then ok, res = pcall(PlaySoundFile, path, chan)
        else ok, res = pcall(PlaySoundFile, path) end
        if not ok then return false, "报错：" .. tostring(res) end
        if res == false then return false, "客户端拒绝（文件不存在）" end
        return true, path
    end

    if p.kind == "auto" then
        local ok, info = PKit(KitId("IG_MAINMENU_OPTION_CHECKBOX_ON", 856))
        if ok then return "自动 → 637/856 复选框（" .. info .. "）" end
        ok, info = PKit(799)
        if ok then return "自动 → 799 退出音" end
        ok, info = PFile("Sound\\Character\\EmoteCatCallWhistle02.ogg")
        if ok then return "自动 → 猫叫哨 ogg" end
        return "自动 → 三条路都没发出去（" .. tostring(info) .. "）"

    elseif p.kind == "kit" then
        local id = p.arg
        local t = _G.SOUNDKIT
        if type(t) == "table" and p.kit and t[p.kit] then id = t[p.kit] end
        local ok, info = PKit(id)
        if not ok then return p.name .. " → " .. info end
        return p.name .. " → 已发送（编号 " .. tostring(id) .. "）"
    end

    local ok, info = PFile(p.arg)
    if not ok then return p.name .. " → " .. info end
    return p.name .. " → 已发送"
end
ns.FireSound = FireSound

local function PlayAlertSound(forceIdx, channel)
    local s = KillListDB and KillListDB.settings
    local idx = forceIdx or (s and s.alertSound) or 1
    return FireSound(idx, channel)
end

ns.PlayAlertSound = PlayAlertSound

ns.ShowAlert = function(name, deaths, starred)
    local tag = starred and "|cffffd700★ 重点目标   |r" or ""
    alertText:SetText(format("%s|cffff5555仇人接近|r   %s|cffeeeeee（杀过你 %d 次）|r",
        tag, name, deaths))
    alertT = 0
    alertFrame:SetAlpha(0)
    alertFrame:Show()
end

ns.NearbyAlert = function(name, deaths, starred)
    local s = KillListDB and KillListDB.settings
    if not s then return end

    if s.nearbyScreen ~= false then
        ns.ShowAlert(name, deaths, starred)
    end

    if s.nearbySound ~= false then
        PlayAlertSound()
    end
end

--------------------------------------------------------------
-- 小地图按钮：骑着圆环、可拖动、不敲命令也能开窗口
--------------------------------------------------------------
local MINIMAP = Minimap or UIParent

local mmBtn = CreateFrame("Button", "KillListMinimapButton", MINIMAP)
mmBtn:SetSize(31, 31)
mmBtn:SetFrameStrata("MEDIUM")
mmBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mmBtn:RegisterForDrag("LeftButton")
mmBtn:SetMovable(true)
mmBtn:SetAlpha(0.9)

-- 外观：金色浮雕（唯一保留的样式）
local mmSkin = {
    edge = { 1.00, 0.82, 0.35 },
    body = { 0.20, 0.14, 0.05 },
    text = "|cffffe0a0仇|r",
}

local mmEdge = mmBtn:CreateTexture(nil, "BACKGROUND", nil, 1)
mmEdge:SetAllPoints()

local mmBody = mmBtn:CreateTexture(nil, "BACKGROUND", nil, 2)
mmBody:SetSize(27, 27)
mmBody:SetPoint("CENTER", 0, 0)

local mmTop = mmBtn:CreateTexture(nil, "BACKGROUND", nil, 3)
mmTop:SetPoint("TOPLEFT", mmBody, "TOPLEFT", 0, 0)
mmTop:SetPoint("TOPRIGHT", mmBody, "TOPRIGHT", 0, 0)
mmTop:SetHeight(7)

local mmBottom = mmBtn:CreateTexture(nil, "BACKGROUND", nil, 3)
mmBottom:SetPoint("BOTTOMLEFT", mmBody, "BOTTOMLEFT", 0, 0)
mmBottom:SetPoint("BOTTOMRIGHT", mmBody, "BOTTOMRIGHT", 0, 0)
mmBottom:SetHeight(6)

local mmText = mmBtn:CreateFontString(nil, "OVERLAY")
mmText:SetPoint("CENTER", 0, 0)
mmText:SetJustifyH("CENTER")
mmText:SetJustifyV("MIDDLE")
local mmFontPath = (GameFontNormal and GameFontNormal:GetFont()) or "Fonts\\ARKai_T.ttf"
mmText:SetFont(mmFontPath, 14, "OUTLINE")

local function ApplyMinimapSkin(hover)
    mmText:SetText(mmSkin.text)
    if hover then
        mmEdge:SetColorTexture(1, 0.97, 0.72, 1)
    else
        mmEdge:SetColorTexture(mmSkin.edge[1], mmSkin.edge[2], mmSkin.edge[3], 0.95)
    end
    mmBody:SetColorTexture(mmSkin.body[1], mmSkin.body[2], mmSkin.body[3], 0.95)
    mmTop:SetColorTexture(1, 1, 1, 0.13)
    mmBottom:SetColorTexture(0, 0, 0, 0.38)
end

ApplyMinimapSkin(false)

-- 自己算反正切，避免不同 Lua 版本 math.atan2 缺失
local PI = 3.14159265358979
local function Atan2(y, x)
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + PI
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - PI
    elseif x == 0 and y > 0 then
        return PI / 2
    elseif x == 0 and y < 0 then
        return -PI / 2
    end
    return 0
end

local mmPos = 20

local function UpdateMinimapPos()
    local s = KillListDB and KillListDB.settings
    if s and s.minimapPos then mmPos = s.minimapPos end
    mmBtn:ClearAllPoints()
    if MINIMAP ~= Minimap then
        mmBtn:SetPoint("BOTTOMRIGHT", MINIMAP, "BOTTOMRIGHT", 3, 3)
        return
    end
    local w = MINIMAP:GetWidth()
    if not w or w <= 1 then w = 140 end
    local r = w / 2 + 1
    local rad = math.rad(mmPos)
    mmBtn:SetPoint("CENTER", MINIMAP, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

UpdateMinimapPos()

local mmDragEnd = 0

mmBtn:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    ApplyMinimapSkin(true)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("记仇 · PVP 交手记录")
    GameTooltip:AddLine("左键：打开 / 关闭名单", 1, 0.82, 0)
    GameTooltip:AddLine("右键：打开设置", 0.75, 0.75, 0.75)
    GameTooltip:AddLine("按住左键拖动：挪到小地图别的位置", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
mmBtn:SetScript("OnLeave", function(self)
    self:SetAlpha(0.9)
    ApplyMinimapSkin(false)
    GameTooltip:Hide()
end)
mmBtn:SetScript("OnDragStart", function(self)
    self:SetAlpha(1)
    self:SetScript("OnUpdate", function(self)
        local mx, my = GetCursorPosition()
        local scale = self:GetEffectiveScale() or 1
        if not scale or scale == 0 then scale = 1 end
        mx, my = mx / scale, my / scale
        local cx, cy = MINIMAP:GetCenter()
        if not cx or not cy then return end
        local ang = math.deg(Atan2(my - cy, mx - cx))
        if ang < 0 then ang = ang + 360 end
        mmPos = ang
        local s = KillListDB and KillListDB.settings
        if s then s.minimapPos = ang end
        UpdateMinimapPos()
    end)
end)
mmBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    mmDragEnd = GetTime()
    self:SetAlpha(0.9)
end)
mmBtn:SetScript("OnClick", function(self, button)
    if GetTime() - mmDragEnd < 0.3 then return end
    if button == "RightButton" then
        if ns.OpenSettings then ns.OpenSettings() end
    elseif frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end)

local function MinimapButtonShown()
    local s = KillListDB and KillListDB.settings
    if not s then return true end
    return s.minimapButton == nil or s.minimapButton
end

local function SyncMinimapButton()
    if MinimapButtonShown() then mmBtn:Show() else mmBtn:Hide() end
end

-- 进游戏时小地图尺寸才定下来，再校一次位置
local mmWatch = CreateFrame("Frame")
mmWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
mmWatch:SetScript("OnEvent", function() UpdateMinimapPos() end)
--------------------------------------------------------------
-- 设置面板：把常用命令做成按钮
--------------------------------------------------------------
local setFrame = CreateFrame("Frame", "KillListSettingsFrame", UIParent, "BackdropTemplate")
setFrame:SetSize(300, 430)
setFrame:SetPoint("CENTER", UIParent, "CENTER", 250, 30)
setFrame:SetFrameStrata("DIALOG")
setFrame:SetToplevel(true)
setFrame:SetMovable(true)
setFrame:SetClampedToScreen(true)
setFrame:EnableMouse(true)
setFrame:RegisterForDrag("LeftButton")
setFrame:SetScript("OnDragStart", setFrame.StartMoving)
setFrame:SetScript("OnDragStop", setFrame.StopMovingOrSizing)
setFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 20,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
})
setFrame:Hide()

local setTitle = setFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
setTitle:SetPoint("TOP", setFrame, "TOP", 0, -13)
setTitle:SetText("|cffffd700记仇|r  设置")

local setClose = CreateFrame("Button", nil, setFrame, "UIPanelCloseButton")
setClose:SetPoint("TOPRIGHT", setFrame, "TOPRIGHT", -3, -3)
setClose:SetScript("OnClick", function() setFrame:Hide() end)

local btnNearby, btnDebug, btnMinimap, btnTooltip, btnSound, btnScreen, btnWipe, setStat

local function SyncSettings()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    if btnNearby then
        btnNearby:SetText("附近仇人提醒：" .. (s.nameplate and "|cff40ff40开|r" or "|cff888888关|r"))
    end
    if btnSound then
        btnSound:SetText("接近时提示音：" .. ((s.nearbySound ~= false) and "|cff40ff40开|r" or "|cff888888关|r"))
    end
    if btnScreen then
        btnScreen:SetText("接近时屏幕提示：" .. ((s.nearbyScreen ~= false) and "|cff40ff40开|r" or "|cff888888关|r"))
    end
    if btnDebug then
        btnDebug:SetText("调试输出：" .. (s.debug and "|cff40ff40开|r" or "|cff888888关|r"))
    end
    if btnMinimap then
        btnMinimap:SetText("小地图按钮：" .. (MinimapButtonShown() and "|cff40ff40开|r" or "|cff888888关|r"))
    end
    if btnTooltip then
        btnTooltip:SetText("悬停显示交手记录：" .. ((s.tooltip ~= false) and "|cff40ff40开|r" or "|cff888888关|r"))
    end

    if setStat and ns.GetStats then
        local k, d, n = ns.GetStats()
        setStat:SetText(format("|cff888888%s · 总击杀 %d  ·  总死亡 %d  ·  名单 %d 人|r", tostring(UnitName("player")), k, d, n))
    end
end

local function MakeBtn(x, y, w, text, onClick)
    local b = CreateFrame("Button", nil, setFrame, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetPoint("TOPLEFT", setFrame, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

btnNearby = MakeBtn(16, -46, 268, "", function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.nameplate = not s.nameplate
    SyncSettings()
end)

btnDebug = MakeBtn(16, -76, 268, "", function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.debug = not s.debug
    SyncSettings()
end)

btnMinimap = MakeBtn(16, -106, 268, "", function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.minimapButton = not MinimapButtonShown()
    SyncMinimapButton()
    SyncSettings()
end)


btnTooltip = MakeBtn(16, -136, 268, "", function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.tooltip = not (s.tooltip ~= false)
    SyncSettings()
end)

btnSound = MakeBtn(16, -166, 268, "", function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.nearbySound = not (s.nearbySound ~= false)
    SyncSettings()
end)

btnScreen = MakeBtn(16, -196, 268, "", function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.nearbyScreen = not (s.nearbyScreen ~= false)
    SyncSettings()
end)

MakeBtn(16, -226, 130, "打开日志窗", function()
    if ns.ToggleLog then ns.ToggleLog() end
end)

MakeBtn(154, -226, 130, "导出名单", function()
    if ShowExport then ShowExport() end
end)

MakeBtn(16, -256, 130, "环境诊断", function()
    if ns.PrintEnv then ns.PrintEnv() end
end)

MakeBtn(154, -256, 130, "清理脏数据", function()
    if ns.Clean then ns.Clean() end
    SyncSettings()
end)

MakeBtn(16, -286, 130, "换个提示音", function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    local n = #SOUNDS
    s.alertSound = ((s.alertSound or 1) % n) + 1
    local how = FireSound(s.alertSound)
    print(format("|cff8ab4ff[记仇]|r 提示音 %d/%d：%s", s.alertSound, n, how))
end)

local wipeArmed = false
btnWipe = MakeBtn(154, -286, 130, "清空全部名单", function()
    if not wipeArmed then
        wipeArmed = true
        btnWipe:SetText("|cffff3333再点一次，确认清空|r")
        C_Timer.After(3, function()
            wipeArmed = false
            if btnWipe then btnWipe:SetText("清空全部名单") end
        end)
    else
        wipeArmed = false
        btnWipe:SetText("清空全部名单")
        if ns.Reset then ns.Reset() end
        SyncSettings()
    end
end)

setStat = setFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
setStat:SetPoint("TOPLEFT", setFrame, "TOPLEFT", 18, -318)

local setHint = setFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
setHint:SetPoint("TOPLEFT", setFrame, "TOPLEFT", 18, -340)
setHint:SetWidth(266)
setHint:SetJustifyH("LEFT")
setHint:SetText("小地图边上那个「仇」字按钮就是入口：左键开名单，右键开设置，按住左键拖动能挪位置。\n姓名板建议一直开着，关掉后只能靠选中目标认人。\n提示音如果没声音，点一下「试播提示音」看聊天框里的诊断。")

ns.OpenSettings = function()
    if not KillListDB then return end
    setFrame:Show()
    SyncSettings()
    setFrame:Raise()
end

tinsert(UISpecialFrames, "KillListMainFrame")
tinsert(UISpecialFrames, "KillListSettingsFrame")
tinsert(UISpecialFrames, "KillListLogFrame")

--------------------------------------------------------------
-- 事件与命令
--------------------------------------------------------------

ns.RegListener(function(what)
    if what == "init" or (frame and frame:IsShown()) then
        if ns.Players() then
            RefreshList()
            UpdateDetail()
        end
    end
end)

frame:SetScript("OnShow", function()
    if ns.Players() then
        RefreshList()
        UpdateDetail()
    end
end)

SLASH_KILLLIST1 = "/kl"
SLASH_KILLLIST2 = "/killlist"
SlashCmdList["KILLLIST"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()

    if msg == "debug" then
        if KillListDB and KillListDB.settings then
            KillListDB.settings.debug = not KillListDB.settings.debug
            print("|cff8ab4ff[记仇]|r 调试输出已" ..
                (KillListDB.settings.debug and "开启" or "关闭"))
            if setFrame:IsShown() then SyncSettings() end
        end

    elseif msg == "beep" then
        -- 试播：屏幕横幅 + 当前音源，一并验证
        local how = PlayAlertSound()
        print("|cff8ab4ff[记仇]|r 提示音试播：" .. tostring(how))
        ns.ShowAlert("测试目标 假人", 3, true)

    elseif msg == "snd" or msg:find("^snd ") then
        local arg, chanArg = msg:match("^snd%s+([%d]+)%s*(%a*)")
        if arg then
            local n = tonumber(arg)
            if not SOUNDS[n] then
                print(format("|cff8ab4ff[记仇]|r 序号只能是 1~%d", #SOUNDS))
                return
            end
            KillListDB.settings.alertSound = n
            local how = FireSound(n, chanArg ~= "" and chanArg or nil)
            print(format("|cff8ab4ff[记仇]|r 提示音已设为 %d/%d：%s",
                n, #SOUNDS, how))
        else
            print("|cff8ab4ff[记仇]|r 逐个试播，听到哪声就用 /kl snd <序号> 定下来")
            for i = 1, #SOUNDS do
                C_Timer.After((i - 1) * 0.9, function()
                    local how = FireSound(i)
                    print(format("|cff8ab4ff[记仇]|r 第 %d 个 / %d：%s", i, #SOUNDS, how))
                end)
            end
        end

    elseif msg == "stats" then
        local k, d, n = ns.GetStats()
        print(format("|cff8ab4ff[记仇]|r 总击杀 %d 次，总死亡 %d 次，名单 %d 人", k, d, n))

    elseif msg == "export" then
        ShowExport()

    elseif msg == "env" then
        ns.PrintEnv()

    elseif msg == "name" then
        if ns.DumpName then ns.DumpName() end

    elseif msg == "log" then
        if ns.ToggleLog then ns.ToggleLog() end

    elseif msg == "names" or msg:match("^names ") then
        local s = KillListDB and KillListDB.settings
        if s then
            if msg == "names on" then
                s.nameplate = true
            elseif msg == "names off" then
                s.nameplate = false
            else
                s.nameplate = not s.nameplate
            end
            print("|cff8ab4ff[记仇]|r 姓名板扫描已" .. (s.nameplate and "开启" or "关闭"))
            if setFrame:IsShown() then SyncSettings() end
        end

    elseif msg == "clean" then
        if ns.Clean then ns.Clean() end

    elseif msg:match("^add ") then
        if ns.AddManual then ns.AddManual(msg:gsub("^add%s+", "")) end

    elseif msg == "add" then
        print("|cff8ab4ff[记仇]|r 用法：/kl add 名字（自动漏记时手动补一条击杀）")

    elseif msg == "reset" then
        if ns.Reset then ns.Reset() end
        selected = nil

    elseif msg == "help" then
        print("|cff8ab4ff[记仇]|r 小地图边上的「仇」字按钮：左键开名单、右键开设置、拖动可挪位置。命令也都还在：/kl 开关 · /kl log 日志窗 · /kl export 导出 · /kl stats 统计 · /kl add 名字 手动补记 · /kl beep 试播提示音 · /kl snd 挑提示音 · /kl env 环境 · /kl name 姓名诊断 · /kl names 姓名板 · /kl debug 调试 · /kl reset 清空 · /kl clean 清脏数据")

    else
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
    end
end

--------------------------------------------------------------
-- 鼠标提示：悬停或选中玩家时显示交手记录
--------------------------------------------------------------
local function TipGetUnit(tip)
    if tip.GetUnit then
        local ok, _, unit = pcall(tip.GetUnit, tip)
        if ok and unit then return unit end
    end
    return tip.unit
end

local function TooltipAddLine(tip)
    local s = KillListDB and KillListDB.settings
    if not s or not s.tooltip then return end

    local unit = TipGetUnit(tip)
    if not unit then return end
    if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end

    local name = (ns.BestName and ns.BestName(unit)) or UnitName(unit)
    if not name or name == "" then return end

    local e = ns.FindPlayer and ns.FindPlayer(UnitGUID(unit), name)
    if not e then return end

    local kills, deaths = e.kills or 0, e.deaths or 0
    if kills == 0 and deaths == 0 then return end

    local parts = {}
    if kills > 0 then parts[#parts + 1] = "你杀过他 " .. kills .. " 次" end
    if deaths > 0 then parts[#parts + 1] = "他杀过你 " .. deaths .. " 次" end

    local line = table.concat(parts, " · ")
    if e.lastSeen then line = line .. "  ·  上次 " .. ns.TimeAgo(e.lastSeen) end
    if e.lastZone and e.lastZone ~= "" then line = line .. "  " .. e.lastZone end

    local prefix = e.star and "|cffffd700★ |r" or ""
    tip:AddLine(prefix .. "|cffeee0a0" .. line .. "|r", 1, 1, 1, true)

    if e.note and e.note ~= "" then
        tip:AddLine("|cff9a9a9a「" .. e.note .. "」|r", 1, 1, 1, true)
    end
    if tip:IsShown() then tip:Show() end
end

local function HookTooltips()
    if ns.tooltipHooked then return end
    ns.tooltipHooked = true
    local function hookOne(tip)
        if not tip or not tip.HookScript then return end
        tip:HookScript("OnTooltipSetUnit", function(self) pcall(TooltipAddLine, self) end)
    end
    hookOne(GameTooltip)
    hookOne(ItemRefTooltip)
end
HookTooltips()

-- 初始化界面状态（此时 SavedVariables 可能还没加载，Refresh 自带保护）
SetKind(kind)

-- 存档加载后同步小地图按钮的显示状态
ns.RegListener(function(what)
    if what == "init" then UpdateMinimapPos(); SyncMinimapButton(); ApplyMinimapSkin(false) end
end)
