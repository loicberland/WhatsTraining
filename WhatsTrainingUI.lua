local _, wt = ...
wt = wt or _G.WhatsTraining or {}
_G.WhatsTraining = wt
local ignoreStore = LibStub:GetLibrary("FusionIgnoreStore-1.0")

local hasNewSpellbook = wt.hasNewSpellbook

local BOOKTYPE_SPELL = BOOKTYPE_SPELL

local MAX_ROWS = 22
local ROW_HEIGHT = 14
local SKILL_LINE_TAB = MAX_SKILLLINE_TABS - 1
local ROW_RIGHT_PADDING = 12
local WT_SCROLLBAR_X = -43
local WT_SCROLLBAR_TOP = -75
local WT_SCROLLBAR_BOTTOM = 81
local WT_SCROLLBAR_BUTTON_GAP = 0
local WT_SCROLLBAR_WIDTH = 16
local HIGHLIGHT_TEXTURE_FILEID = wt.GetTexture(
                                     "Interface\\AddOns\\WhatsTraining\\highlight")
local LEFT_BG_TEXTURE_FILEID = wt.GetTexture(
                                   "Interface\\AddOns\\WhatsTraining\\left")
local RIGHT_BG_TEXTURE_FILEID = wt.GetTexture(
                                    "Interface\\AddOns\\WhatsTraining\\right")
local TAB_TEXTURE_FILEID = wt.GetTexture(
                               "Interface\\Icons\\INV_Misc_QuestionMark")

local tooltip = CreateFrame("GameTooltip", "WhatsTrainingTooltip", UIParent,
                            "GameTooltipTemplate")

local function setTooltip(spellInfo)
    if spellInfo.tooltipType == "item" then
        wt.SetTooltipSpellByID(tooltip, spellInfo.tooltipId)
        tooltip:AddLine(spellInfo.formattedFullName, 1, 1, 1)
    elseif spellInfo.tooltipType == "spell" then
        wt.SetTooltipSpellByID(tooltip, spellInfo.tooltipId)
    else
        tooltip:ClearLines()
    end
    if spellInfo.cost > 0 then
        tooltip:AddLine(wt.formatSpellCost(spellInfo))
    end
    if spellInfo.tooltip then tooltip:AddLine(spellInfo.tooltip) end
    tooltip:Show()
end

local menuFrame = CreateFrame("Frame", "WTRightClickFrame", UIParent,
                              "UIDropDownMenuTemplate")
local legacyMenuFrame = CreateFrame("Frame", "WTLegacyContextMenu", UIParent,
                                    "UIDropDownMenuTemplate")

local function openLegacyMenu(row, items)
    UIDropDownMenu_Initialize(legacyMenuFrame, function()
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.isTitle = item.isTitle
            info.notCheckable = item.checked == nil
            info.checked = item.checked
            info.disabled = item.disabled
            info.notClickable = item.isTitle or item.disabled
            info.func = item.func
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, legacyMenuFrame, row, 0, 0)
end
local function setRowSpell(row, spell)
    if spell == nil then
        row.currentSpell = nil
        row:Hide()
        return
    elseif spell.isHeader then
        row.spell:Hide()
        row.header:Show()
        row.header:SetText(spell.formattedName)
        row:SetID(0)
        row.highlight:SetTexture(nil)
    else
        local rowSpell = row.spell
        row.header:Hide()
        row.isHeader = false
        row.highlight:SetTexture(HIGHLIGHT_TEXTURE_FILEID)
        rowSpell:Show()
        rowSpell.label:SetText(spell.name)
        rowSpell.subLabel:SetText(spell.formattedSubText)
        if not spell.hideLevel then
            rowSpell.level:Show()
            rowSpell.level:SetText(spell.formattedLevel)
            local color = spell.levelColor
            rowSpell.level:SetTextColor(color.r, color.g, color.b)
        else
            rowSpell.level:Hide()
        end
        row:SetID(spell.itemId or spell.id)
        rowSpell.icon:SetTexture(spell.useAltIcon and spell.altIcon or spell.icon)
    end
    if spell.click then
        row:SetScript("OnClick", spell.click)
    elseif not spell.isHeader then
        row:SetScript("OnClick", function(_, button)
            if button == "LeftButton" and IsShiftKeyDown() then
                local link = spell.link
                if spell.taughtSpell then
                    link = link..' '..spell.taughtSpell.link
                end
                local window = ChatEdit_GetActiveWindow()
                if window then
                    window:Insert(link)
                else
                    ChatFrame_OpenChat(link)
                end
            end
            if not wt.ClickHook then return end
            if button == "RightButton" then
                wt.ClickHook(spell, function()
                    wt:RebuildData()
                end, row)
            end
        end)
    else
        row:SetScript("OnClick", nil)
    end
    row.currentSpell = spell
    if (tooltip:IsOwned(row)) then setTooltip(spell) end
    row:Show()
end

-- When holding down left mouse on the slider knob, it will keep firing update even though
-- the offset hasn't changed so this will help throttle that
local lastOffset = -1
function wt.Update(frame, forceUpdate)
    local scrollBar = frame.scrollBar
    local maxOffset = math.max(0, #wt.data - MAX_ROWS)
    local offset = math.min(frame.scrollOffset or 0, maxOffset)
    frame.scrollOffset = offset
    if offset == lastOffset and not forceUpdate then return end
    for i, row in ipairs(frame.rows) do
        local spellIndex = i + offset
        local spell = wt.data[spellIndex]
        setRowSpell(row, spell)
    end
    if scrollBar then
        scrollBar:SetMinMaxValues(0, maxOffset)
        if scrollBar:GetValue() ~= offset then
            scrollBar:SetValue(offset)
        end
        if maxOffset > 0 then
            scrollBar:Show()
        else
            scrollBar:Hide()
        end
    end
    lastOffset = offset
end

local hasFrameShown = false
function wt.CreateFrame()
    local mainFrame = CreateFrame("Frame", "WhatsTrainingFrame", SpellBookFrame)
    local lastNativeSkillLine = 1

    local function isWhatsTrainingSkillLine(skillLine)
        return skillLine == SKILL_LINE_TAB
    end

    local function rememberNativeSkillLine(skillLine)
        skillLine = skillLine or SpellBookFrame.selectedSkillLine
        if skillLine and skillLine > 0 and not isWhatsTrainingSkillLine(skillLine) then
            lastNativeSkillLine = skillLine
        end
    end

    mainFrame:SetPoint("TOPLEFT", SpellBookFrame, "TOPLEFT", 0, 0)
    mainFrame:SetPoint("BOTTOMRIGHT", SpellBookFrame, "BOTTOMRIGHT", 0, 0)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame.scrollOffset = 0
    mainFrame.SetVerticalScroll = function(self, value)
        local offset = math.floor((value or 0) + 0.5)
        if self.scrollOffset ~= offset then
            self.scrollOffset = offset
            wt.Update(self)
        end
    end
    mainFrame.GetVerticalScroll = function(self)
        return self.scrollOffset or 0
    end
    local left = mainFrame:CreateTexture(nil, "ARTWORK")
    left:SetTexture(LEFT_BG_TEXTURE_FILEID)
    left:SetWidth(256)
    left:SetHeight(512)
    left:SetPoint("TOPLEFT", mainFrame)
    local right = mainFrame:CreateTexture(nil, "ARTWORK")
    right:SetTexture(RIGHT_BG_TEXTURE_FILEID)
    right:SetWidth(128)
    right:SetHeight(512)
    right:SetPoint("TOPRIGHT", mainFrame)
    if not hasNewSpellbook then
        local searchTemplate = "InputBoxTemplate"
        if SearchBoxTemplate then
            searchTemplate = "SearchBoxTemplate"
        end
        local search = CreateFrame("EditBox", "$parentSearchBox", mainFrame, searchTemplate)
        search:SetWidth(124)
        search:SetHeight(20)
        search:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 81, -38)
        search:SetAutoFocus(false)
        search:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        search:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        search:SetScript("OnTextChanged", function(self)
            if SearchBoxTemplate_OnTextChanged then
                SearchBoxTemplate_OnTextChanged(self)
            end
            local oldFilter = wt.filter
            wt.filter = strlower(self:GetText() or "")
            if wt.filter ~= oldFilter then
                wt:ApplyFilter()
            end
        end)
        if not SearchBoxTemplate then
            local searchLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            searchLabel:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 2, 2)
            searchLabel:SetText(SEARCH or "Search")
        end
    end
    mainFrame:Hide()
    
    if hasNewSpellbook then
    	left:SetWidth(350)
    	left:SetHeight(536)
    	left:SetPoint("TOPLEFT", mainFrame, 72, 8)
    	right:SetHeight(536)
    	right:SetPoint("TOPRIGHT", mainFrame, 0, 8)
    end

    -- TBC 2.4.3 does not need the SoD/Classic SPELLS_CHANGED tab-restoring hack.
    rememberNativeSkillLine(SpellBookFrame.selectedSkillLine)

    SpellBookFrame:HookScript("OnHide", function()
        if isWhatsTrainingSkillLine(SpellBookFrame.selectedSkillLine) then
            SpellBookFrame.selectedSkillLine = lastNativeSkillLine or 1
        end
        local skillLineTab = _G["SpellBookSkillLineTab" .. SKILL_LINE_TAB]
        if skillLineTab then
            skillLineTab:SetChecked(false)
        end
        mainFrame:Hide()
    end)

    SpellBookFrame:HookScript("OnEvent", function(self, event)
        if event == "SPELLS_CHANGED" and SpellBookFrame.bookType == BOOKTYPE_SPELL then
            rememberNativeSkillLine()
        end
    end)
    function wt.Open()
        if SpellBookFrame.bookType == BOOKTYPE_SPELL then
            rememberNativeSkillLine()
        end
        SpellBookFrame.bookType = BOOKTYPE_SPELL
        SpellBookFrame.selectedSkillLine = SKILL_LINE_TAB
        if SpellBookFrame:IsVisible() then
            wt.RefreshSpellBookFrame()
        else
            ToggleSpellBook("spell")
        end
    end

    local function updateSkillLineTabs()
        local skillLineTab = _G["SpellBookSkillLineTab" .. SKILL_LINE_TAB]
        if not skillLineTab then
            return
        end
        skillLineTab:SetNormalTexture(TAB_TEXTURE_FILEID)
        skillLineTab.tooltip = wt.L.TAB_TEXT
        skillLineTab:Show()
        local isAddonTabSelected = SpellBookFrame.bookType == BOOKTYPE_SPELL
            and isWhatsTrainingSkillLine(SpellBookFrame.selectedSkillLine)
        if isAddonTabSelected then
            skillLineTab:SetChecked(true)
            mainFrame:Show()
            if hasNewSpellbook then
                SpellBookPrevPageButton:Disable()
                SpellBookNextPageButton:Disable()
                SpellBookPageText:SetText('')
            elseif ShowAllSpellRanksCheckbox then
                ShowAllSpellRanksCheckbox:Hide()
            end
        else
            skillLineTab:SetChecked(false)
            mainFrame:Hide()
            if SpellBookFrame.bookType == BOOKTYPE_SPELL then
                rememberNativeSkillLine()
            end
            local _, class = UnitClass("player")
            if not hasNewSpellbook and ShowAllSpellRanksCheckbox and class ~= "ROGUE" and class ~= "WARRIOR" then
                ShowAllSpellRanksCheckbox:Show()
            end
        end
    end
    if SpellBookFrame.UpdateSkillLineTabs then
        hooksecurefunc(SpellBookFrame, "UpdateSkillLineTabs", updateSkillLineTabs)
    elseif type(_G.SpellBookFrame_UpdateSkillLineTabs) == "function" then
        hooksecurefunc("SpellBookFrame_UpdateSkillLineTabs", updateSkillLineTabs)
    end

    local function onSpellBookUpdate()
        if SpellBookFrame.bookType == BOOKTYPE_SPELL then
            rememberNativeSkillLine()
        end
        updateSkillLineTabs()
        if SpellBookFrame.bookType ~= BOOKTYPE_SPELL then
            mainFrame:Hide()
        elseif isWhatsTrainingSkillLine(SpellBookFrame.selectedSkillLine) then
            mainFrame:Show()
        else
            mainFrame:Hide()
        end
    end
    if SpellBookFrame.Update then
        hooksecurefunc(SpellBookFrame, "Update", onSpellBookUpdate)
    else
        hooksecurefunc("SpellBookFrame_Update", onSpellBookUpdate)
    end

    local scrollBar = CreateFrame("Slider", "$parentScrollBar", mainFrame,
                                  "UIPanelScrollBarTemplate")
    scrollBar:SetWidth(WT_SCROLLBAR_WIDTH)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)
    scrollBar:SetScript("OnValueChanged", function(self, value)
        local offset = math.floor((value or 0) + 0.5)
        if mainFrame.scrollOffset ~= offset then
            mainFrame.scrollOffset = offset
            wt.Update(mainFrame)
        end
    end)
    local upButton = _G[scrollBar:GetName() .. "ScrollUpButton"]
    local downButton = _G[scrollBar:GetName() .. "ScrollDownButton"]
    if upButton and downButton then
        local upButtonHeight = upButton:GetHeight() or 16
        local downButtonHeight = downButton:GetHeight() or 16
        upButton:ClearAllPoints()
        upButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", WT_SCROLLBAR_X, WT_SCROLLBAR_TOP)
        downButton:ClearAllPoints()
        downButton:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", WT_SCROLLBAR_X,
                            WT_SCROLLBAR_BOTTOM)
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", WT_SCROLLBAR_X,
                           WT_SCROLLBAR_TOP - upButtonHeight - WT_SCROLLBAR_BUTTON_GAP)
        scrollBar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", WT_SCROLLBAR_X,
                           WT_SCROLLBAR_BOTTOM + downButtonHeight + WT_SCROLLBAR_BUTTON_GAP)
    else
        scrollBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", WT_SCROLLBAR_X, WT_SCROLLBAR_TOP)
        scrollBar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", WT_SCROLLBAR_X,
                           WT_SCROLLBAR_BOTTOM)
    end
    if upButton then
        upButton:SetScript("OnClick", function()
            scrollBar:SetValue(math.max(0, (mainFrame.scrollOffset or 0) - 1))
        end)
    end
    if downButton then
        downButton:SetScript("OnClick", function()
            local maxOffset = math.max(0, #wt.data - MAX_ROWS)
            scrollBar:SetValue(math.min(maxOffset, (mainFrame.scrollOffset or 0) + 1))
        end)
    end
    mainFrame:EnableMouseWheel(true)
    mainFrame:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #wt.data - MAX_ROWS)
        local step = delta > 0 and -1 or 1
        scrollBar:SetValue(math.min(maxOffset, math.max(0, (mainFrame.scrollOffset or 0) + step)))
    end)
    scrollBar:SetScript("OnShow", function()
        if not hasFrameShown then
            wt:RebuildData()
            hasFrameShown = true
        end
        wt.Update(mainFrame, true)
    end)
    mainFrame.scrollBar = scrollBar

    local rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", "$parentRow" .. i, mainFrame)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnEnter", function(self)
            tooltip:SetOwner(self, "ANCHOR_RIGHT")
            setTooltip(self.currentSpell)
        end)
        row:SetScript("OnLeave", function() tooltip:Hide() end)

        local highlight = row:CreateTexture("$parentHighlight", "HIGHLIGHT")
        highlight:SetAllPoints()

        local spell = CreateFrame("Frame", "$parentSpell", row)
        spell:SetPoint("LEFT", row, "LEFT")
        spell:SetPoint("TOP", row, "TOP")
        spell:SetPoint("BOTTOM", row, "BOTTOM")

        local spellIcon = spell:CreateTexture(nil, "OVERLAY")
        spellIcon:SetPoint("TOPLEFT", spell)
        spellIcon:SetPoint("BOTTOMLEFT", spell)
        local iconWidth = ROW_HEIGHT
        spellIcon:SetWidth(iconWidth)
        local spellLabel = spell:CreateFontString("$parentLabel", "OVERLAY",
                                                  "GameFontNormal")
        spellLabel:SetPoint("TOPLEFT", spell, "TOPLEFT", iconWidth + 4, 0)
        spellLabel:SetPoint("BOTTOM", spell)
        spellLabel:SetJustifyV("MIDDLE")
        spellLabel:SetJustifyH("LEFT")
        local spellSublabel = spell:CreateFontString("$parentSubLabel",
                                                     "OVERLAY",
                                                     "GameFontNormalSmall")
        spellSublabel:SetJustifyH("LEFT")
        spellSublabel:SetPoint("TOPLEFT", spellLabel, "TOPRIGHT", 2, 0)
        spellSublabel:SetPoint("BOTTOM", spellLabel)
        local spellLevelLabel = spell:CreateFontString("$parentLevelLabel",
                                                       "OVERLAY",
                                                       "GameFontWhite")
        spellLevelLabel:SetPoint("TOPRIGHT", spell, -4, 0)
        spellLevelLabel:SetPoint("BOTTOM", spell)
        spellLevelLabel:SetJustifyH("RIGHT")
        spellLevelLabel:SetJustifyV("MIDDLE")
        spellSublabel:SetPoint("RIGHT", spellLevelLabel, "LEFT")
        spellSublabel:SetJustifyV("MIDDLE")

        local headerLabel = row:CreateFontString("$parentHeaderLabel",
                                                 "OVERLAY", "GameFontWhite")
        headerLabel:SetAllPoints()
        headerLabel:SetJustifyV("MIDDLE")
        headerLabel:SetJustifyH("CENTER")

        spell.label = spellLabel
        spell.subLabel = spellSublabel
        spell.icon = spellIcon
        spell.level = spellLevelLabel
        row.highlight = highlight
        row.header = headerLabel
        row.spell = spell

        if rows[i - 1] == nil then
        	if hasNewSpellbook then
        		row:SetPoint("TOPLEFT", mainFrame, 110, -78)
        	else
            	row:SetPoint("TOPLEFT", mainFrame, 26, -78)
            end
        else
            row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -2)
        end
        row:SetPoint("RIGHT", scrollBar, "LEFT", -ROW_RIGHT_PADDING, 0)

        rawset(rows, i, row)
    end
    mainFrame.rows = rows
    wt.MainFrame = mainFrame
end

local function addIgnoreLines(rootDescription, config)
    rootDescription:CreateTitle(config.title)
    rootDescription:CreateCheckbox(wt.L.IGNORED_TT, function() return config.isIgnored end, function() 
        wt.PlayClickSound()
        ignoreStore:Flip(config.id)
        config.afterClick()
        return MenuResponse.Close
    end)

    local allRanks = wt:AllRanks(config.id)
    if allRanks and #allRanks > 1 then
        local allIgnored = true
        for _, id in ipairs(allRanks) do
            allIgnored = allIgnored and ignoreStore:IsIgnored(id)
        end
        rootDescription:CreateCheckbox(wt.L.IGNORE_ALL_TT, function() return allIgnored end, function ()
            wt.PlayClickSound()
            ignoreStore:UpdateMany(allRanks, not allIgnored)
            config.afterClick()
            return MenuResponse.Close
        end)
    end
end

local function addLegacyIgnoreLines(items, config)
    tinsert(items, {
        text = config.title,
        isTitle = true,
    })
    tinsert(items, {
        text = wt.L.IGNORED_TT,
        checked = config.isIgnored,
        func = function()
            wt.PlayClickSound()
            ignoreStore:Flip(config.id)
            config.afterClick()
        end
    })

    local allRanks = wt:AllRanks(config.id)
    if allRanks and #allRanks > 1 then
        local allIgnored = true
        for _, id in ipairs(allRanks) do
            allIgnored = allIgnored and ignoreStore:IsIgnored(id)
        end
        tinsert(items, {
            text = wt.L.IGNORE_ALL_TT,
            checked = allIgnored,
            func = function()
                wt.PlayClickSound()
                ignoreStore:UpdateMany(allRanks, not allIgnored)
                config.afterClick()
            end
        })
    end
end

wt.ClickHook = function(spell, afterClick, row)
    if not wt.TomeIds or not wt.TomeIds[spell.itemId or spell.id] then
        wt.PlayClickSound()
        local isIgnored = ignoreStore:IsIgnored(spell.id)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(row, function(owner, rootDescription)
                addIgnoreLines(rootDescription, {
                    title = spell.formattedFullName,
                    isIgnored = isIgnored,
                    id = spell.id,
                    afterClick = afterClick
                })
            end)
        else
            local items = {}
            addLegacyIgnoreLines(items, {
                title = spell.formattedFullName,
                isIgnored = isIgnored,
                id = spell.id,
                afterClick = afterClick
            })
            openLegacyMenu(row, items)
        end

        return
    end

    local checked = wt:IsPetAbilityLearned(spell.id)
    wt.PlayClickSound()
    local isIgnored = ignoreStore:IsIgnored(spell.id)
    MenuUtil.CreateContextMenu(row, function(owner, rootDescription)
        if wt.SayaadTomes[spell.itemId] then
            rootDescription:CreateTitle(string.format("%s — %s", wt.L.TOME_HEADER, spell.localFamily))
        else
            rootDescription:CreateTitle(wt.L.TOME_HEADER)
        end
        rootDescription:CreateCheckbox(wt.L.TOME_LEARNED, function() return checked end, function() 
            wt.PlayClickSound()
            wt:SetPetAbilityStatus(spell.id, not checked)
            afterClick()
            return MenuResponse.Close
        end)
        addIgnoreLines(rootDescription, {
            title = spell.formattedFullName,
            isIgnored = isIgnored,
            id = spell.id,
            afterClick = afterClick
        })
    end)
end
