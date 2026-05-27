local _, wt = ...
wt = wt or _G.WhatsTraining or {}
_G.WhatsTraining = wt

-- Spell Cache
wt.petAbilities = {}
wt.spellInfoCache = {}
wt.allRanksCache = {}
wt.idToRanks = {}

-- done has params cacheHit: bool, spellInfo
function wt:CacheSpell(spell, level, done)
    if (self.spellInfoCache[spell.id] ~= nil) then
        done(true, self.spellInfoCache[spell.id])
        return
    end
    local function storeSpellInfo(name, subText, icon)
        local formattedSubText = wt.FormatParens(subText)
        local formattedFullName = (formattedSubText ~= "") and format("%s %s", name, formattedSubText) or name
        self.spellInfoCache[spell.id] = {
            id = spell.id,
            name = name,
            subText = subText,
            formattedSubText = formattedSubText,
            icon = icon,
            cost = spell.cost,
            tooltipType = "spell",
            tooltipId = spell.id,
            formattedCost = wt.GetCoinString(spell.cost),
            level = level,
            formattedLevel = format(wt.L.LEVEL_FORMAT, level),
            formattedFullName = formattedFullName,
            searchText = strlower(formattedFullName),
            link = string.format("|cff71d5ff|Hspell:%d|h[%s]|h|r", spell.id, name),
        }

        if self.allRanksCache[name] == nil then
            self.allRanksCache[name] = {}
        end
        tinsert(self.allRanksCache[name], spell.id)
        self.idToRanks[spell.id] = self.allRanksCache[name]
        if (self:IsPetAbility(spell.id)) then
            if (formattedSubText ~= "") then
                self.petAbilities[name .. " " .. formattedSubText] =
                    self.spellInfoCache[spell.id]
            else
                self.petAbilities[name] =
                    self.spellInfoCache[spell.id]
            end
        end
        done(false, self.spellInfoCache[spell.id])
    end

    if Spell and Spell.CreateFromSpellID then
        local si = Spell:CreateFromSpellID(spell.id)
        si:ContinueOnSpellLoad(function()
            if (self.spellInfoCache[spell.id] ~= nil) then
                done(true, self.spellInfoCache[spell.id])
                return
            end
            wt.RunNextFrame(function()
                storeSpellInfo(si:GetSpellName(), si:GetSpellSubtext(), select(3, GetSpellInfo(spell.id)))
            end)
        end)
        return
    end

    local name, subText, icon = GetSpellInfo(spell.id)
    if not name then
        return
    end
    storeSpellInfo(name, subText, icon)
end

function wt:SpellInfo(spellId) return self.spellInfoCache[spellId] end

function wt:PetAbility(forName) return self.petAbilities[forName] end

function wt:AllRanks(spellId) return self.idToRanks[spellId] end

-- Item Cache
wt.itemInfoCache = {}
-- for warlock pet tomes, the name includes the rank
-- however, this will cause overlap with the level text and there's no good way to fix it with setting points
-- instead, strip the rank text out of the name and put it as the subText
local parensPattern = " (%(.+%))"
function wt:CacheItem(item, level, done, taughtSpell)
    if (self.itemInfoCache[item.id] ~= nil) then
        done(true)
        return
    end
    local function storeItemInfo(itemName, itemLink, itemIcon)
        local rankText = string.match(itemName, parensPattern)
        local ranklessName = string.gsub(itemName, parensPattern, "")
        local rankCacheKey = ranklessName
        if wt.SayaadTomes[item.itemId] then
           rankCacheKey = item.family .. ranklessName
        end
        self.itemInfoCache[item.id] = {
            id = item.id,
            itemId = item.itemId,
            name = ranklessName,
            formattedSubText = rankText,
            icon = itemIcon,
            cost = item.cost,
            formattedCost = wt.GetCoinString(item.cost),
            level = level,
            formattedLevel = format(wt.L.LEVEL_FORMAT, level),
            tooltipType = "item",
            tooltipId = wt.TomeTaughtSpells[item.itemId],
            searchText = strlower(itemName),
            formattedFullName = itemName,
            localFamily = item.localFamily,
            family = item.family,
            altIcon = item.altIcon,
            link = itemLink,
            taughtSpell = taughtSpell
        }
        if self.allRanksCache[rankCacheKey] == nil then
            self.allRanksCache[rankCacheKey] = {}
        end
        tinsert(self.allRanksCache[rankCacheKey], item.id)
        self.idToRanks[item.id] = self.allRanksCache[rankCacheKey]
        done(false)
    end

    if Item and Item.CreateFromItemID then
        local ii = Item:CreateFromItemID(item.itemId)
        ii:ContinueOnItemLoad(function()
            if (self.itemInfoCache[item.id] ~= nil) then
                done(true)
                return
            end
            storeItemInfo(ii:GetItemName(), ii:GetItemLink(), ii:GetItemIcon())
        end)
        return
    end

    local itemName, itemLink, _, _, _, _, _, _, _, itemIcon = GetItemInfo(item.itemId)
    if not itemName then
        itemName, itemLink, _, _, _, _, _, _, _, itemIcon = GetItemInfo("item:" .. item.itemId)
    end
    if not itemName then
        wt.After(0.2, function()
            wt:CacheItem(item, level, done, taughtSpell)
        end)
        return
    end
    storeItemInfo(itemName, itemLink, itemIcon or GetItemIcon(item.itemId))
end

function wt:ItemInfo(itemId) return self.itemInfoCache[itemId] end
