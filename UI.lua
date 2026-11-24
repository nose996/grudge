--[[
    记仇 · 界面层
    名单浏览、搜索、标记、备注、导出
]]

local ADDON, ns = ...

local ROW_H = 26

--------------------------------------------------------------
-- 统一视觉：一套配色 + 一个扁平按钮皮肤
-- 本服可靠可用的只有 SetColorTexture 和字体（外部贴图会渲染成红块），
-- 所以整个界面靠色块 + 1px 细线搭，不用任何 UI-* 素材
--------------------------------------------------------------
local GOLD = { 0.847, 0.706, 0.416 }
local TXT  = { 0.93, 0.90, 0.83 }
local DIM  = { 0.60, 0.58, 0.54 }

--------------------------------------------------------------
-- 自绘控件：本服没有可用的圆角/贴图，按钮、开关、关闭键全靠色块 + 1px 边
--------------------------------------------------------------
-- 四条 1px 边，返回一个改透明度的函数
local function EdgeBox(f)
    local e = {}
    for i = 1, 4 do e[i] = f:CreateTexture(nil, "BORDER") end
    e[1]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    e[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    e[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    e[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    e[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    e[4]:SetWidth(1)
    return function(a)
        for i = 1, 4 do e[i]:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], a) end
    end
end

-- 自绘扁平按钮：UIPanelButtonTemplate 的九宫格木纹在这个客户端上盖不掉，
-- 只能自己用色块 + 1px 边画一个；danger 走暗红字，fontObj 可换字号
local function Flat(parent, w, h, text, onClick, danger, fontObj)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    local edge = EdgeBox(b)
    local fs = b:CreateFontString(nil, "OVERLAY", fontObj or "GameFontNormalSmall")
    fs:SetAllPoints(b)
    fs:SetJustifyH("CENTER")
    fs:SetText(text or "")

    local isOn = false
    local idleC = { 0.91, 0.87, 0.79 }

    local function paintNormal()
        if isOn then
            bg:SetColorTexture(0.260, 0.200, 0.100, 0.95)
            edge(0.80)
            fs:SetTextColor(1, 0.87, 0.60)
        elseif danger then
            bg:SetColorTexture(0.105, 0.078, 0.062, 0.95)
            edge(0.30)
            fs:SetTextColor(0.80, 0.45, 0.38)
        else
            bg:SetColorTexture(0.095, 0.080, 0.064, 0.95)
            edge(0.22)
            fs:SetTextColor(idleC[1], idleC[2], idleC[3])
        end
    end

    local function paintHover()
        if danger then
            bg:SetColorTexture(0.150, 0.100, 0.080, 0.95)
            edge(0.62)
            fs:SetTextColor(0.95, 0.56, 0.47)
        else
            bg:SetColorTexture(0.165, 0.138, 0.104, 0.95)
            edge(0.58)
            fs:SetTextColor(1, 0.93, 0.76)
        end
    end

    paintNormal()
    b:SetScript("OnEnter", paintHover)
    b:SetScript("OnLeave", paintNormal)
    b:SetScript("OnMouseDown", function() bg:SetColorTexture(0.040, 0.034, 0.028, 1) end)
    b:SetScript("OnMouseUp", function()
        if b.GetMouseOver and b:GetMouseOver() then paintHover() else paintNormal() end
    end)
    b:SetScript("OnClick", function() if onClick then onClick() end end)

    -- 页签这类需要「选中」状态的按钮用得到
    b.__setActive = function(v)
        isOn = v and true or false
        paintNormal()
    end
    b.__setIdleColor = function(r, g, bl)
        idleC = { r, g, bl }
        paintNormal()
    end
    b.SetText = function(_, t) fs:SetText(t) end
    b.GetFontString = function() return fs end
    return b
end

-- 自绘关闭按钮：原生 UIPanelCloseButton 是红木纹，和整套暗色不搭
local function SkinClose(parent, onClick, x, y)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x or -7, y or -7)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0.07, 0.06, 0.05, 0.75)
    local edge = EdgeBox(b)
    edge(0.22)

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints(b)
    fs:SetJustifyH("CENTER")
    fs:SetText("×")
    fs:SetTextColor(0.62, 0.60, 0.56)

    b:SetScript("OnClick", function() if onClick then onClick() end end)
    b:SetScript("OnEnter", function()
        edge(0.70)
        fs:SetTextColor(0.95, 0.85, 0.62)
    end)
    b:SetScript("OnLeave", function()
        edge(0.22)
        fs:SetTextColor(0.62, 0.60, 0.56)
    end)
    return b
end

-- 顶部那种「日志 / 设置」小链接，不要底板，只留字
local function LinkButton(parent, w, text, x, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 18)
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x, -16)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetAllPoints(b)
    t:SetJustifyH("CENTER")
    t:SetText(text)
    t:SetTextColor(0.70, 0.68, 0.63)
    b:SetScript("OnEnter", function() t:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end)
    b:SetScript("OnLeave", function() t:SetTextColor(0.70, 0.68, 0.63) end)
    b:SetScript("OnClick", function() if onClick then onClick() end end)
    b.t = t
    return b
end

-- 一根 1px 的分隔线
local function Hairline(parent, y, alpha)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], alpha or 0.28)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y)
    t:SetHeight(1)
    return t
end

local kind       = "death"   -- death = 杀过我的；kill = 我杀过的
local selected   = nil
local filterText = ""

local RefreshList, UpdateDetail, SelectEntry, SetKind, ShowExport, ShowDiag, ShowProbe
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

-- 面板暖色底：原生 DialogFrame 背景偏冷黑，盖一层很淡的暖棕，整体偏暖
local frameTint = frame:CreateTexture(nil, "BACKGROUND")
frameTint:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -7)
frameTint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -7, 7)
frameTint:SetColorTexture(0.22, 0.15, 0.09, 0.42)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -14)
title:SetText("|cffd8b46a记仇|r")

local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subtitle:SetPoint("LEFT", title, "RIGHT", 8, -1)
subtitle:SetText("|cff8a8279PVP 交手记录|r")

local closeBtn = SkinClose(frame, function() frame:Hide() end, -9, -9)

local btnOpenLog = LinkButton(frame, 34, "日志", -40, function()
    if ns.ToggleLog then ns.ToggleLog() end
end)
local btnOpenSet = LinkButton(frame, 34, "设置", -78, function()
    if ns.OpenSettings then ns.OpenSettings() end
end)

Hairline(frame, -38, 0.32)

--------------------------------------------------------------
-- 两个页签
--------------------------------------------------------------
local tabDeath = Flat(frame, 150, 26, "", function() SetKind("death") end, false, "GameFontNormal")
tabDeath:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -46)

local tabKill = Flat(frame, 150, 26, "", function() SetKind("kill") end, false, "GameFontNormal")
tabKill:SetPoint("LEFT", tabDeath, "RIGHT", 6, 0)

--------------------------------------------------------------
-- 搜索
--------------------------------------------------------------
local searchHint
local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
search:SetSize(444, 22)
search:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -80)
search:SetAutoFocus(false)
search:SetTextInsets(8, 8, 0, 0)
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
search:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    filterText = self:GetText() or ""
    if searchHint then searchHint:SetShown((self:GetText() or "") == "") end
    if RefreshList then RefreshList() end
end)
search:SetScript("OnEditFocusGained", function() if searchHint then searchHint:Hide() end end)
search:SetScript("OnEditFocusLost", function(self)
    if searchHint then searchHint:SetShown((self:GetText() or "") == "") end
end)

searchHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
searchHint:SetPoint("LEFT", search, "LEFT", 10, 0)
searchHint:SetText("搜索名字…")

--------------------------------------------------------------
-- 列表
--------------------------------------------------------------
-- 列表区垫一层深色底板，让表头和数据从木纹背景里分出来
local listBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
listBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -104)
listBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 200)
listBg:SetBackdrop({
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
listBg:SetBackdropColor(0.035, 0.030, 0.025, 0.55)
listBg:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.26)

local function HeadText(text, x, w, align)
    local t = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -108)
    t:SetWidth(w)
    t:SetJustifyH(align or "LEFT")
    t:SetText("|cff8a8279" .. text .. "|r")
    return t
end
HeadText("名字", 26, 168)
HeadText("等级 / 公会", 198, 100)
HeadText("交手", 306, 60)

local scroll = CreateFrame("ScrollFrame", "KillListScrollFrame", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -126)
scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -38, 206)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(1, 1)
scroll:SetScrollChild(content)

local rowPool = {}

local function CreateRow(i)
    local r = CreateFrame("Button", nil, content)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * ROW_H)

    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.03)

    r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.sel:SetAllPoints()
    r.sel:SetColorTexture(0.85, 0.64, 0.24, 0.26)
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

    r:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, 0.09) end)
    r:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, self.__base or 0.018) end)
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- 右键该条目：补记一条「我杀过他」
            if self.entry and ns.ManualKill then ns.ManualKill(self.entry) end
        elseif self.entry then
            SelectEntry(self.entry)
        end
    end)

    return r
end

local function UpdateRow(r, entry, index)
    r.entry = entry
    r.__base = (index % 2 == 0) and 0.05 or 0.018
    r.bg:SetColorTexture(1, 1, 1, r.__base)

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
    if entry.star    then prefix = prefix .. "|cffd8b46a★ |r" end

    r.nameFS:SetText(prefix .. entry.name)

    local lvl   = (entry.level and entry.level > 0) and (entry.level .. " 级") or "等级未知"
    local guild = entry.guild and (" · " .. entry.guild) or ""
    r.metaFS:SetText(lvl .. guild)

    local n = (kind == "kill") and (entry.kills or 0) or (entry.deaths or 0)
    r.countFS:SetText(((kind == "kill") and "击杀 " or "死亡 ") .. n .. " 次")

    r.whenFS:SetText(ns.TimeAgo(entry.lastSeen))
end

RefreshList = function()
    local players = ns.Players()
    local list = players and ns.GetList(kind, filterText, true) or {}

    content:SetWidth(math.max(100, scroll:GetWidth() - 2))

    -- 先把行池全部收起并解绑，避免上一页 / 上一场的旧条目残留在屏幕上
    for i = 1, #rowPool do
        rowPool[i]:Hide()
        rowPool[i].entry = nil
    end

    local dIdx = 0
    for i = 1, #list do
        local entry = list[i]
        -- 二次校验：条目必须还在当前名单表里，丢弃跨表残留的孤立对象（key/name 两个键都查）
        local inTable = not players
            or players[entry.key] == entry
            or players[entry.name] == entry
        if inTable then
            dIdx = dIdx + 1
            local r = rowPool[dIdx]
            if not r then
                r = CreateRow(dIdx)
                rowPool[dIdx] = r
            end
            r:Show()
            UpdateRow(r, entry, dIdx)
        end
    end

    content:SetHeight(math.max(1, dIdx * ROW_H))

    local cDeath = #ns.GetList("death", nil, false)
    local cKill  = #ns.GetList("kill",  nil, false)
    tabDeath:SetText(format("杀过我的 (%d)", cDeath))
    tabKill:SetText(format("我杀过的 (%d)", cKill))

    local k, d, n = ns.GetStats()
    statFS:SetText(format("|cff8a8279累计|r  击杀 %d   ·   死亡 %d   ·   名单 %d 人", k, d, n))

    if periodFS and ns.GetPeriodStats then
        local kt, dt, kw, dw = ns.GetPeriodStats()
        periodFS:SetText(format("|cff8a8279今天|r  %d 杀 %d 死      |cff8a8279本周|r  %d 杀 %d 死", kt, dt, kw, dw))
    end

    if dIdx == 0 then
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
detail:SetBackdropColor(0.035, 0.030, 0.025, 0.58)
detail:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.26)

local dName = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dName:SetPoint("TOPLEFT", detail, "TOPLEFT", 6, -8)

local dMeta = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dMeta:SetPoint("TOPLEFT", detail, "TOPLEFT", 6, -34)
dMeta:SetWidth(450)
dMeta:SetJustifyH("LEFT")
dMeta:SetWordWrap(false)

local dNote = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
dNote:SetSize(240, 20)
dNote:SetPoint("TOPLEFT", detail, "TOPLEFT", 6, -58)
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

local function MakeDetailButton(text, x, danger)
    local b = Flat(detail, 88, 22, text, nil, danger)
    b:SetPoint("TOPLEFT", detail, "TOPLEFT", x, -88)
    return b
end

local btnStar   = MakeDetailButton("标星", 6)
local btnIgnore = MakeDetailButton("忽略", 102)
local btnDelete = MakeDetailButton("删除", 198, true)
local btnKill   = MakeDetailButton("补记击杀", 294)

btnKill:SetScript("OnClick", function()
    if selected and ns.ManualKill then ns.ManualKill(selected) end
end)

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
    -- 刷新包一层容错：即便列表刷新抛错，页签高亮也要照常切换，避免按钮卡在旧状态
    pcall(RefreshList)
    pcall(UpdateDetail)

    local function tone(tab, on)
        if tab.__setIdleColor then tab.__setIdleColor(0.72, 0.70, 0.66) end
        if tab.__setActive then tab.__setActive(on) end
    end
    tone(tabDeath, k == "death")
    tone(tabKill,  k == "kill")
end

--------------------------------------------------------------
-- 底部：导出与统计
--------------------------------------------------------------
statFS = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
statFS:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 22)
statFS:SetText("")

-- 今天 / 本周的即时战绩
periodFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
periodFS:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 44)
periodFS:SetText("")

Hairline(frame, -538, 0.18)

local btnExport = Flat(frame, 110, 24, "导出名单", function() ShowExport() end)
btnExport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 16)

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
exportTitle:SetText("|cffd8b46a导出名单|r")

local exportClose = SkinClose(exportFrame, function() exportFrame:Hide() end, -7, -7)

-- 导出窗也盖一层暖色底，和主窗、设置面板统一
local exportTint = exportFrame:CreateTexture(nil, "BACKGROUND")
exportTint:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 7, -7)
exportTint:SetPoint("BOTTOMRIGHT", exportFrame, "BOTTOMRIGHT", -7, 7)
exportTint:SetColorTexture(0.22, 0.15, 0.09, 0.42)

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
    exportTitle:SetText("|cffd8b46a导出名单|r")
    exportHint:SetText("点进输入框按 Ctrl+A 全选、Ctrl+C 复制，可直接贴到群里或攻略站。")
    exportBox:SetText(ns.BuildExport(kind))
    exportFrame:Show()
    exportBox:SetFocus()
    exportBox:HighlightText()
end
-- 复制诊断信息：把一小段环境摘要塞进同一个导出窗，Ctrl+A / Ctrl+C 就能发出去
ShowDiag = function()
    exportTitle:SetText("|cffd8b46a诊断信息|r")
    exportHint:SetText("全选复制这段发给作者即可。内容只有版本、接口状态和名单人数，不含账号信息。")
    exportBox:SetText(ns.DiagText and ns.DiagText() or "诊断接口不可用")
    exportFrame:Show()
    exportBox:SetFocus()
    exportBox:HighlightText()
end
-- 探针窗：环境 + PARTY_KILL 留档 + 信号原始参数，一窗复制导出，不用截图
ShowProbe = function()
    local ok, err = pcall(function()
        exportTitle:SetText("|cffd8b46a探针诊断 · v" .. tostring(ns.version) .. "|r")
        exportHint:SetText("Ctrl+A 全选、Ctrl+C 复制。含环境、PARTY_KILL 留档和信号原始参数，不含账号信息。")
        exportBox:SetText(ns.ProbeText and ns.ProbeText() or "探针接口不可用")
        exportFrame:Show()
        exportBox:SetFocus()
        exportBox:HighlightText()
    end)
    if not ok then
        print("|cffff3333[记仇]|r 探针窗打开失败：" .. tostring(err))
    end
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
logFrame:SetBackdropColor(0.062, 0.053, 0.045, 0.95)
logFrame:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.26)
logFrame:Hide()

local logTitle = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
logTitle:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 14, -10)
logTitle:SetText("|cffd8b46a记仇|r |cff8a8279日志|r")
Hairline(logFrame, -32, 0.20)

local logClose = SkinClose(logFrame, function() logFrame:Hide() end, -6, -6)

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

local btnLogClear = Flat(logFrame, 76, 20, "清空", function()
    if ns.ClearLog then ns.ClearLog() end
    RefreshLog()
end)
btnLogClear:SetPoint("BOTTOMLEFT", logFrame, "BOTTOMLEFT", 12, 10)

local btnLogCopy = Flat(logFrame, 76, 20, "导出", function()
    exportTitle:SetText("|cffd8b46a记仇|r |cff8a8279日志|r")
    exportHint:SetText("按 Ctrl+A 全选，Ctrl+C 复制")
    exportBox:SetText(ComposeLogText())
    exportFrame:Show()
    exportBox:SetFocus()
    exportBox:HighlightText()
end)
btnLogCopy:SetPoint("BOTTOMLEFT", logFrame, "BOTTOMLEFT", 96, 10)

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

-- 提示音。走过的弯路记在这里，免得以后又试一遍：
--   · 带第二个参数 "Master" 不是问题（SilverDragon 就这么写，有声音）
--   · 单参数也不是问题（163UI_CombatTimer 就这么写，有声音）
--   · 真正被拒的是 "Sound\\..." 系统素材字符串路径：调用不报错、静默丢弃
-- 可用的三条：PlaySound(编号) / PlaySoundFile(数字 FileDataID) / PlaySoundFile(AddOns 下的 wav)

-- 插件自带的提示音：不依赖客户端素材文件是否被裁，路径必然存在
local SELF_WAV = "Interface\\AddOns\\" .. tostring(ADDON) .. "\\alert.wav"

-- 实测（2026-11-20）：本服插件能出声的有三条路——
--   ① PlaySound(编号) 走客户端内部音效库（856/852/799 已验证有声音）
--   ② PlaySoundFile(数字FileDataID) 走客户端文件表（SilverDragon 就是这么播稀有提示音的）
--   ③ PlaySoundFile("Interface\\AddOns\\<插件>\\x.wav") 插件自带文件
-- 而 "Sound\\..." 这类系统素材**字符串路径**一律被拒（调用不报错但静默）。
local SOUNDS = {
    { name = "自动（亡灵号角优先）",      kind = "auto" },
    { name = "亡灵号角 567386",          kind = "fdid", arg = 567386 },
    { name = "战鼓 567275",              kind = "fdid", arg = 567275 },
    { name = "雷劈 566202",              kind = "fdid", arg = 566202 },
    { name = "巫妖王「我看见你」554236",  kind = "fdid", arg = 554236 },
    { name = "自带 beep.wav（兜底）",     kind = "file", arg = SELF_WAV },
}
ns.SOUNDS = SOUNDS

-- 单参数优先；传了 channel 才走双参数（留给通道排查）
local function FireSound(idx, channel)
    local p = SOUNDS[idx]
    if not p then return "序号无效" end
    local chan = (channel and channel ~= "") and channel or nil

    -- 数字 FileDataID：客户端文件表，SilverDragon 播稀有提示音走的就是这条
    local function PFDID(id)
        if not PlaySoundFile then return false, "PlaySoundFile 不存在" end
        local ok = pcall(PlaySoundFile, id)
        if not ok then ok = pcall(PlaySoundFile, id, chan or "Master") end
        if not ok then return false, "报错" end
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
        local ok, info = PFDID(567386)          -- 亡灵号角
        if ok then return "自动 → 亡灵号角 567386" end
        ok, info = PFile(SELF_WAV)              -- 自带 wav 兜底
        if ok then return "自动 → 自带 beep.wav" end
        ok, info = PFDID(567275)                -- 战鼓
        if ok then return "自动 → 战鼓 567275" end
        return "自动 → 都没发出去（" .. tostring(info) .. "）"

    elseif p.kind == "fdid" then
        local ok, info = PFDID(p.arg)
        if not ok then return p.name .. " → " .. info end
        return p.name .. " → 已发送（ID " .. tostring(p.arg) .. "）"
    end

    local ok, info = PFile(p.arg)
    if not ok then return p.name .. " → " .. info end
    return p.name .. " → 已发送"
end
ns.FireSound = FireSound

local function PlayAlertSound(forceIdx, channel)
    local s = KillListDB and KillListDB.settings
    local idx = tonumber(forceIdx or (s and s.alertSound)) or 1
    if not SOUNDS[idx] then idx = 1 end
    return FireSound(idx, channel)
end

ns.PlayAlertSound = PlayAlertSound

ns.ShowAlert = function(name, deaths, starred)
    local tag = starred and "|cffd8b46a★ 重点目标   |r" or ""
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
-- 敌情条：仇人在视野内就一直挂在屏幕上方，血条消失才收
-- 横幅只闪 3.8 秒，打架时容易错过；这条是持续状态，抬头就在
--------------------------------------------------------------
local enemyBar = CreateFrame("Frame", "KillListEnemyBar", UIParent, "BackdropTemplate")
enemyBar:SetHeight(24)
enemyBar:SetPoint("TOP", UIParent, "TOP", 0, -96)
enemyBar:SetFrameStrata("HIGH")
enemyBar:SetBackdrop({
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
enemyBar:SetBackdropColor(0.22, 0.02, 0.02, 0.88)
enemyBar:SetBackdropBorderColor(0.90, 0.22, 0.18, 0.95)
enemyBar:EnableMouse(false)
enemyBar:Hide()

local enemyBarText = enemyBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
enemyBarText:SetPoint("LEFT", enemyBar, "LEFT", 12, 0)
enemyBarText:SetPoint("RIGHT", enemyBar, "RIGHT", -12, 0)
enemyBarText:SetJustifyH("CENTER")
pcall(function()
    local path = GameFontNormalSmall:GetFont()
    enemyBarText:SetFont(path, 14, "OUTLINE")
end)

local function RefreshEnemyBar()
    local s = KillListDB and KillListDB.settings
    if not s or s.enemyBar == false then enemyBar:Hide(); return end
    local list = ns.GetNearby and ns.GetNearby() or {}
    if #list == 0 then enemyBar:Hide(); return end

    local parts = {}
    for i = 1, math.min(#list, 4) do
        local v = list[i]
        parts[#parts + 1] = (v.star and "|cffd8b46a★|r" or "")
            .. "|cffff9999" .. v.name .. "|r|cff9a9a9a " .. tostring(v.deaths or 0) .. "|r"
    end
    if #list > 4 then parts[#parts + 1] = "|cff9a9a9a另 " .. tostring(#list - 4) .. " 人|r" end

    enemyBarText:SetText("|cffff4444■ 敌情|r   " .. table.concat(parts, "   ·   "))
    local w = enemyBarText:GetStringWidth() + 30
    if w < 180 then w = 180 end
    if w > 760 then w = 760 end
    enemyBar:SetWidth(w)
    enemyBar:Show()
end
ns.RefreshEnemyBar = RefreshEnemyBar

-- 常驻不可见的心跳帧：条自己隐藏后 OnUpdate 会停，没法再自动弹出来
local enemyTick = CreateFrame("Frame")
local enemyAcc = 0
enemyTick:SetScript("OnUpdate", function(_, dt)
    enemyAcc = enemyAcc + dt
    if enemyAcc >= 0.4 then
        enemyAcc = 0
        RefreshEnemyBar()
    end
end)

ns.RegListener(function(what)
    if what == "nearby" then RefreshEnemyBar() end
end)

-- 测试用：没仇人在线时也能确认条的位置、宽度和排版。
-- 只往内存里的表塞两条假数据，10 秒后自己清掉，不写进名单、不进存档
function ns.DemoEnemyBar(seconds)
    if not ns.nearby then return end
    local now = time()
    ns.nearby["Player-Demo0000-01"] = { name = "测试 仇人甲", deaths = 5, star = true,  since = now, t = now }
    ns.nearby["Player-Demo0000-02"] = { name = "测试 灰名乙", deaths = 2, star = false, since = now, t = now }
    RefreshEnemyBar()
    C_Timer.After(seconds or 10, function()
        if ns.nearby then
            ns.nearby["Player-Demo0000-01"] = nil
            ns.nearby["Player-Demo0000-02"] = nil
        end
        RefreshEnemyBar()
    end)
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
setFrame:SetSize(300, 440)
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
setTitle:SetPoint("TOPLEFT", setFrame, "TOPLEFT", 18, -14)
setTitle:SetText("|cffd8b46a记仇|r |cff8a8279设置|r")
Hairline(setFrame, -40, 0.32)

-- 面板暖色底：原生 DialogFrame 背景偏冷黑，盖一层很淡的暖棕，颜色才和主窗一致
local panelTint = setFrame:CreateTexture(nil, "BACKGROUND")
panelTint:SetPoint("TOPLEFT", setFrame, "TOPLEFT", 7, -7)
panelTint:SetPoint("BOTTOMRIGHT", setFrame, "BOTTOMRIGHT", -7, 7)
panelTint:SetColorTexture(0.22, 0.15, 0.09, 0.42)

local setStat, btnWipe
local setRows = {}

--------------------------------------------------------------
-- 设置面板控件：分组标题 / 行式开关 / 工具按钮
-- 本服没有任何圆角或外部贴图可用，开关用「色块 + 1px 细边」做，
-- 开 = 金底深字，关 = 暗底灰字；整行可点，不必瞄着开关按
--------------------------------------------------------------
local setClose = SkinClose(setFrame, function() setFrame:Hide() end, -9, -9)

local function GroupTitle(text, y)
    local fs = setFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", setFrame, "TOPLEFT", 16, y)
    fs:SetText(text)
    fs:SetTextColor(0.60, 0.58, 0.54)

    local ln = setFrame:CreateTexture(nil, "ARTWORK")
    ln:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.22)
    ln:SetPoint("LEFT", fs, "RIGHT", 8, 1)
    ln:SetPoint("RIGHT", setFrame, "RIGHT", -16, 0)
    ln:SetHeight(1)
end

local function MakeRow(key, label, y, dim, onClick)
    local row = CreateFrame("Button", nil, setFrame)
    row:SetSize(268, 26)
    row:SetPoint("TOPLEFT", setFrame, "TOPLEFT", 16, y)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", row, "LEFT", 0, 1)
    name:SetText(label)

    local sw = CreateFrame("Frame", nil, row)
    sw:SetSize(40, 18)
    sw:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    local bg = sw:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sw)
    local edge = EdgeBox(sw)
    local st = sw:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    st:SetAllPoints(sw)
    st:SetJustifyH("CENTER")

    local hr = row:CreateTexture(nil, "ARTWORK")
    hr:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.11)
    hr:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    hr:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    hr:SetHeight(1)

    local function idle()
        if dim then name:SetTextColor(0.60, 0.58, 0.54)
        else name:SetTextColor(TXT[1], TXT[2], TXT[3]) end
    end
    idle()

    row.__set = function(on)
        row.__on = on and true or false
        if row.__on then
            bg:SetColorTexture(0.780, 0.640, 0.380, 1)
            edge(0.90)
            st:SetText("开")
            st:SetTextColor(0.10, 0.07, 0.02)
        else
            bg:SetColorTexture(0.100, 0.088, 0.074, 0.90)
            edge(0.18)
            st:SetText("关")
            st:SetTextColor(0.50, 0.48, 0.44)
        end
    end

    row:SetScript("OnClick", function() if onClick then onClick() end end)
    row:SetScript("OnEnter", function() name:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end)
    row:SetScript("OnLeave", idle)

    setRows[key] = row
    row.__set(false)
    return row
end

local function SyncSettings()
    local s = KillListDB and KillListDB.settings
    if not s then return end

    local function set(key, on)
        local r = setRows[key]
        if r then r.__set(on) end
    end

    set("nameplate", s.nameplate and true or false)
    set("sound",     s.nearbySound ~= false)
    set("screen",    s.nearbyScreen ~= false)
    set("enemy",     s.enemyBar ~= false)
    set("minimap",   MinimapButtonShown())
    set("tooltip",   s.tooltip ~= false)
    set("debug",     s.debug and true or false)

    if setStat and ns.GetStats then
        local k, d, n = ns.GetStats()
        setStat:SetText(format("|cff8a8279名单 %d 人 · %d 杀 %d 死|r", n, k, d))
    end
end

-- 设置面板上的工具按钮：统一走 Flat 自绘，危险动作直接走暗红字
local function MakeBtn(x, y, w, text, onClick, danger)
    local b = Flat(setFrame, w, 24, text, onClick, danger)
    b:SetPoint("TOPLEFT", setFrame, "TOPLEFT", x, y)
    return b
end

--------------------------------------------------------------
-- 提醒
--------------------------------------------------------------
GroupTitle("提醒", -46)

MakeRow("nameplate", "附近仇人提醒", -60, false, function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.nameplate = not s.nameplate
    SyncSettings()
end)

MakeRow("sound", "接近时提示音", -88, false, function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.nearbySound = not (s.nearbySound ~= false)
    SyncSettings()
end)

MakeRow("screen", "接近时屏幕提示", -116, false, function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.nearbyScreen = not (s.nearbyScreen ~= false)
    SyncSettings()
end)

MakeRow("enemy", "顶部敌情条", -144, false, function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.enemyBar = not (s.enemyBar ~= false)
    if ns.RefreshEnemyBar then ns.RefreshEnemyBar() end
    SyncSettings()
end)

--------------------------------------------------------------
-- 显示
--------------------------------------------------------------
GroupTitle("显示", -178)

MakeRow("minimap", "小地图按钮", -192, false, function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.minimapButton = not MinimapButtonShown()
    SyncMinimapButton()
    SyncSettings()
end)

MakeRow("tooltip", "悬停显示交手记录", -220, false, function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.tooltip = not (s.tooltip ~= false)
    SyncSettings()
end)

--------------------------------------------------------------
-- 排查
--------------------------------------------------------------
GroupTitle("排查", -254)

MakeRow("debug", "调试输出", -268, true, function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    s.debug = not s.debug
    SyncSettings()
end)

--------------------------------------------------------------
-- 工具（动作，不改设置）
--------------------------------------------------------------
GroupTitle("工具", -302)

MakeBtn(16, -318, 130, "日志窗", function()
    if ns.ToggleLog then ns.ToggleLog() end
end)

MakeBtn(154, -318, 130, "导出名单", function()
    if ShowExport then ShowExport() end
end)

MakeBtn(16, -346, 130, "探针诊断", function()
    if ShowProbe then ShowProbe() end
end)

MakeBtn(154, -346, 130, "换个提示音", function()
    local s = KillListDB and KillListDB.settings
    if not s then return end
    local n = #SOUNDS
    s.alertSound = ((s.alertSound or 1) % n) + 1
    local how = FireSound(s.alertSound)
    print(format("|cff8ab4ff[记仇]|r 提示音 %d/%d：%s", s.alertSound, n, how))
end)

MakeBtn(16, -374, 130, "清理脏数据", function()
    if ns.Clean then ns.Clean() end
    SyncSettings()
end)

btnWipe = MakeBtn(154, -374, 130, "清空名单", function()
    local armed = btnWipe.__armed
    if not armed then
        btnWipe.__armed = true
        btnWipe:SetText("|cffff6b5e再点一次确认|r")
        C_Timer.After(3, function()
            btnWipe.__armed = false
            if btnWipe then btnWipe:SetText("清空名单") end
        end)
    else
        btnWipe.__armed = false
        btnWipe:SetText("清空名单")
        if ns.Reset then ns.Reset() end
        SyncSettings()
    end
end)

Hairline(setFrame, -406, 0.18)

setStat = setFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
setStat:SetPoint("TOPLEFT", setFrame, "TOPLEFT", 16, -414)

local setVer = setFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
setVer:SetPoint("TOPRIGHT", setFrame, "TOPRIGHT", -16, -414)
local verText = (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or ns.version or "?"
setVer:SetText("|cff8a8279v" .. tostring(verText) .. "|r")

ns.OpenSettings = function()
    if not KillListDB then return end
    setFrame:Show()
    setFrame:Raise()
    -- 刷新失败也不能把面板挡在后面；出错就打到聊天框，方便报bug时定位
    local ok, err = pcall(SyncSettings)
    if not ok then
        ns.lastSyncError = tostring(err)
        print("|cffff6b5e[记仇]|r 设置面板刷新出错：" .. tostring(err))
    else
        ns.lastSyncError = nil
    end
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

    elseif msg == "env" or msg == "pk" or msg == "raw" or msg == "probe" then
        if ShowProbe then ShowProbe() end

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

    elseif msg == "ui" or msg:match("^ui%s") then
        -- 设置面板自检：打不开时先跑这条
        local n = 0
        for _ in pairs(setRows) do n = n + 1 end
        print(format("|cff8ab4ff[记仇]|r 设置面板 shown=%s 尺寸=%sx%s 位置=(%s,%s) 开关行=%d",
            tostring(setFrame:IsShown()), tostring(setFrame:GetWidth()), tostring(setFrame:GetHeight()),
            tostring(setFrame:GetLeft()), tostring(setFrame:GetTop()), n))
        local ok2, err2 = pcall(SyncSettings)
        print("|cff8ab4ff[记仇]|r 刷新一次：" .. (ok2 and "OK" or tostring(err2)) ..
            " · 上次错误=" .. tostring(ns.lastSyncError or "无"))
        if msg == "ui reset" or (msg:match("^ui reset")) then
            setFrame:ClearAllPoints()
            setFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    elseif msg == "diag" then
        if ShowDiag then ShowDiag() end

    elseif msg == "demo" then
        local s = KillListDB and KillListDB.settings
        if s and s.enemyBar == false then
            print("|cff8ab4ff[记仇]|r 顶部敌情条现在是关着的，先在设置里打开")
        elseif ns.DemoEnemyBar then
            ns.DemoEnemyBar(10)
            print("|cff8ab4ff[记仇]|r 敌情条测试：屏幕上方显示 10 秒假数据（不进名单、不进存档）")
        end

    elseif msg == "clean" then
        if ns.Clean then ns.Clean() end

    elseif msg:match("^add ") then
        if ns.AddManual then ns.AddManual(msg:gsub("^add%s+", "")) end

    elseif msg == "add" then
        if ns.AddManual then ns.AddManual() end

    elseif msg == "reset" then
        if ns.Reset then ns.Reset() end
        selected = nil

    elseif msg == "help" then
        print("|cff8ab4ff[记仇]|r 小地图边上的「仇」字按钮：左键开名单、右键开设置、拖动可挪位置。命令也都还在：/kl 开关 · /kl log 日志窗 · /kl export 导出 · /kl stats 统计 · /kl add [名字] 手动补记（选中对方后可省略名字；名单里右键某人或详情区「补记击杀」按钮也行） · /kl beep 试播提示音 · /kl snd 挑提示音 · /kl probe 探针诊断窗（env/pk/raw 同一窗口可复制导出） · /kl name 姓名诊断 · /kl names 姓名板 · /kl diag 复制诊断 · /kl demo 试敌情条 · /kl debug 调试 · /kl reset 清空 · /kl clean 清脏数据")

    else
        if msg == "" then
            if frame:IsShown() then
                frame:Hide()
            else
                frame:Show()
            end
        else
            -- 未知子命令不再静默切主窗（旧版本/打错命令容易被当成“窗口没反应”）
            print("|cff8ab4ff[记仇]|r 不认识的命令：/" .. msg .. "。输入 /kl help 看命令表；若是刚更新过插件，先 /reload 一次。")
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

    local prefix = e.star and "|cffd8b46a★ |r" or ""
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
