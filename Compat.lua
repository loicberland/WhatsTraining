local addonName, wt = ...
addonName = addonName or "WhatsTraining"
wt = wt or _G[addonName] or {}
_G[addonName] = wt

local _, _, _, build = GetBuildInfo()
build = tonumber(build) or 0

wt.addonName = addonName
wt.isLegacyBC = build > 0 and build < 30000
wt.hasModernProjects = WOW_PROJECT_ID ~= nil
wt.hasNewSpellbook = wt.hasModernProjects and WOW_PROJECT_CATACLYSM_CLASSIC ~= nil and WOW_PROJECT_ID >= WOW_PROJECT_CATACLYSM_CLASSIC

local queuedCallbacks = {}
local nextFrameRunner = CreateFrame("Frame")
local function flushNextFrameQueue(self)
    self:SetScript("OnUpdate", nil)
    local callbacks = queuedCallbacks
    queuedCallbacks = {}
    for _, callback in ipairs(callbacks) do
        callback()
    end
end

function wt.RunNextFrame(callback)
    if RunNextFrame then
        RunNextFrame(callback)
        return
    end

    tinsert(queuedCallbacks, callback)
    nextFrameRunner:SetScript("OnUpdate", flushNextFrameQueue)
end

function wt.After(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, callback)
        return
    end

    local timer = CreateFrame("Frame")
    local remaining = delay
    timer:SetScript("OnUpdate", function(self, elapsed)
        remaining = remaining - elapsed
        if remaining > 0 then
            return
        end

        self:SetScript("OnUpdate", nil)
        callback()
    end)
end

function wt.GetTexture(path)
    if GetFileIDFromPath then
        return GetFileIDFromPath(path)
    end
    return path
end

function wt.GetAddonTitle(name)
    if C_AddOns and C_AddOns.GetAddOnInfo then
        local _, title = C_AddOns.GetAddOnInfo(name)
        return title or name
    end

    local title = GetAddOnMetadata(name, "Title")
    if title and title ~= "" then
        return title
    end

    local legacyName = GetAddOnInfo(name)
    return legacyName or name
end

function wt.IsAddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    return IsAddOnLoaded(name)
end

function wt.PlayClickSound()
    if SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then
        PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    else
        PlaySound("UChatScrollButton")
    end
end

function wt.ColorText(colorCode, text)
    return string.format("%s%s%s", colorCode or "", text or "", FONT_COLOR_CODE_CLOSE)
end

function wt.GetCoinString(amount, fontHeight)
    if GetCoinTextureString then
        return GetCoinTextureString(amount, fontHeight)
    end

    local copper = amount or 0
    local gold = math.floor(copper / 10000)
    copper = math.fmod(copper, 10000)
    local silver = math.floor(copper / 100)
    copper = math.fmod(copper, 100)

    local parts = {}
    if gold > 0 then
        tinsert(parts, tostring(gold) .. "g")
    end
    if silver > 0 or gold > 0 then
        tinsert(parts, tostring(silver) .. "s")
    end
    tinsert(parts, tostring(copper) .. "c")

    return table.concat(parts, " ")
end

if not MenuResponse then
    MenuResponse = { Close = true }
end

if not MenuUtil then
    local compatMenuFrame = CreateFrame("Frame", "WTCompatContextMenu", UIParent, "UIDropDownMenuTemplate")
    MenuUtil = {}

    function MenuUtil.CreateContextMenu(owner, builder)
        local items = {}
        local rootDescription = {}

        function rootDescription:CreateTitle(text)
            tinsert(items, {
                text = text,
                isTitle = true,
            })
        end

        function rootDescription:CreateCheckbox(text, checkedFunc, clickFunc)
            tinsert(items, {
                text = text,
                checked = checkedFunc and checkedFunc() or false,
                func = function()
                    if clickFunc then
                        clickFunc()
                    end
                end
            })
        end

        builder(owner, rootDescription)

        UIDropDownMenu_Initialize(compatMenuFrame, function()
            for _, item in ipairs(items) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.isTitle = item.isTitle
                info.notCheckable = item.checked == nil
                info.checked = item.checked
                info.notClickable = item.isTitle
                info.func = item.func
                UIDropDownMenu_AddButton(info)
            end
        end, "MENU")

        ToggleDropDownMenu(1, nil, compatMenuFrame, owner, 0, 0)
    end
end

function wt.FormatParens(text)
    if not text or text == "" then
        return ""
    end
    if PARENS_TEMPLATE then
        return format(PARENS_TEMPLATE, text)
    end
    return format("(%s)", text)
end

function wt.SetTooltipSpellByID(tooltip, spellId)
    if tooltip.SetSpellByID then
        tooltip:SetSpellByID(spellId)
        return
    end

    tooltip:SetHyperlink("spell:" .. spellId)
end

function wt.CastSpellByID(spellId)
    if _G.CastSpellByID then
        CastSpellByID(spellId)
        return
    end

    local spellName = GetSpellInfo(spellId)
    if spellName then
        CastSpellByName(spellName)
    end
end

local knownSpellCache
local knownPetSpellCache
local BOOKTYPE_SPELL_LOCAL = BOOKTYPE_SPELL or "spell"
local BOOKTYPE_PET_LOCAL = BOOKTYPE_PET or "pet"

local function spellKey(name, rank)
    return format("%s\001%s", name or "", rank or "")
end

local function buildKnownSpellCache(bookType)
    local cache = {}
    local index = 1

    while true do
        local name, rank = GetSpellName(index, bookType)
        if not name then
            break
        end

        cache[spellKey(name, rank)] = true
        cache[spellKey(name, "")] = true
        index = index + 1
    end

    return cache
end

function wt.InvalidateKnownSpellCache()
    knownSpellCache = nil
    knownPetSpellCache = nil
end

function wt.IsSpellKnown(spellId, isPetSpell)
    if not wt.isLegacyBC then
        if isPetSpell then
            return IsSpellKnown and IsSpellKnown(spellId, true)
        end

        if IsSpellKnown and IsSpellKnown(spellId) then
            return true
        end

        return IsPlayerSpell and IsPlayerSpell(spellId) or false
    end

    local name, rank = GetSpellInfo(spellId)
    if not name then
        return false
    end

    if isPetSpell then
        knownPetSpellCache = knownPetSpellCache or buildKnownSpellCache(BOOKTYPE_PET_LOCAL)
        return knownPetSpellCache[spellKey(name, rank)] or knownPetSpellCache[spellKey(name, "")]
    end

    knownSpellCache = knownSpellCache or buildKnownSpellCache(BOOKTYPE_SPELL_LOCAL)
    return knownSpellCache[spellKey(name, rank)] or knownSpellCache[spellKey(name, "")]
end

function wt.GetMerchantItemID(index)
    if GetMerchantItemID then
        return GetMerchantItemID(index)
    end

    local link = GetMerchantItemLink(index)
    if not link then
        return nil
    end

    local itemId = string.match(link, "item:(%d+)")
    return tonumber(itemId)
end

function wt.RefreshSpellBookFrame()
    if SpellBookFrame and SpellBookFrame.Update then
        SpellBookFrame:Update()
        return
    end

    if SpellBookFrame_Update then
        SpellBookFrame_Update()
    end
end
