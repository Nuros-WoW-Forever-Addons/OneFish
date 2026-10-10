--[[
    OneFish - Lures.lua
    Smart, automated fishing lure application.
    Checks main-hand weapon enchantments, filters lures by player fishing skill,
    and applies the optimal lure from player inventory on double-click.
--]]

local addonName, addonTable = ...
local OneFish = _G.OneFish or addonTable

OneFish.Lures = {}
local Lures = OneFish.Lures

-- Known fishing lures ranked from highest bonus to lowest
Lures.RANKED_LURES = {
    { id = 6533,  name = "Aquadynamic Fish Attractor", bonus = 100, minSkill = 100 },
    { id = 34861, name = "Sharpened Fish Hook",        bonus = 100, minSkill = 100 },
    { id = 46006, name = "Glow Worm",                  bonus = 100, minSkill = 100 },
    { id = 7307,  name = "Flesh Eating Worm",          bonus = 75,  minSkill = 100 },
    { id = 6532,  name = "Bright Baubles",             bonus = 75,  minSkill = 100 },
    { id = 6811,  name = "Aquadynamic Fish Lens",       bonus = 50,  minSkill = 50  },
    { id = 6530,  name = "Nightcrawlers",              bonus = 50,  minSkill = 50  },
    { id = 6529,  name = "Shiny Bauble",               bonus = 25,  minSkill = 1   },
}

-------------------------------------------------------------------------------
-- Helper: Safe Item ID from Link
-------------------------------------------------------------------------------

local function GetItemIDFromLink(link)
    if not link then return nil end
    local _, _, itemID = string.find(link, "item:(%d+)")
    return tonumber(itemID)
end

-------------------------------------------------------------------------------
-- Skill & Enchant Checks
-------------------------------------------------------------------------------

--- Check player's current Fishing skill level across all client versions
-- @return number: Current rank (defaults to 300 if skill pane inaccessible)
function Lures:GetPlayerFishingSkill()
    -- 1. Legacy Skill Lines (Classic / Vanilla / Turtle)
    if GetNumSkillLines and GetSkillLineInfo then
        local ok, numSkills = pcall(GetNumSkillLines)
        if ok and numSkills then
            for i = 1, numSkills do
                local ok2, skillName, _, _, skillRank = pcall(GetSkillLineInfo, i)
                if ok2 and skillName and string.find(string.lower(skillName), "fish") then
                    return skillRank or 0
                end
            end
        end
    end

    -- 2. Modern Professions API (WoW 11.0 / Classic)
    if GetProfessions and GetProfessionInfo then
        local ok, p1, p2, arch, fish = pcall(GetProfessions)
        if ok and fish then
            local ok2, _, _, skillRank = pcall(GetProfessionInfo, fish)
            if ok2 and skillRank then
                return skillRank
            end
        end
    end

    return 300
end

--- Checks if the main-hand fishing pole already has a temporary enchant (lure)
-- @return boolean: true if a lure is active
function Lures:HasActiveLure()
    if not GetWeaponEnchantInfo then return false end
    local hasMainHandEnchant = GetWeaponEnchantInfo()
    if hasMainHandEnchant and hasMainHandEnchant ~= 0 then
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Inventory Lookup & Application
-------------------------------------------------------------------------------

--- Locate a specific item ID in player bags
-- @param targetID number: Item ID
-- @return number|nil, number|nil: bagID, slotID
local function FindItemInBags(targetID)
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink

    if not getNumSlots or not getItemLink then return nil, nil end

    local numBags = NUM_BAG_SLOTS or 4
    for bag = 0, numBags do
        local ok, slots = pcall(getNumSlots, bag)
        if ok and slots and slots > 0 then
            for slot = 1, slots do
                local ok2, link = pcall(getItemLink, bag, slot)
                if ok2 and link then
                    local itemID = GetItemIDFromLink(link)
                    if itemID == targetID then
                        return bag, slot
                    end
                end
            end
        end
    end
    return nil, nil
end

--- Scans bags for the highest quality lure usable by the player
-- @return number|nil, number|nil, string|nil: bag, slot, lureName
function Lures:FindBestLure()
    local playerSkill = self:GetPlayerFishingSkill()

    for _, lure in ipairs(self.RANKED_LURES) do
        if playerSkill >= lure.minSkill then
            local bag, slot = FindItemInBags(lure.id)
            if bag and slot then
                return bag, slot, lure.name
            end
        end
    end

    return nil, nil, nil
end

--- Checks if lure should be applied and applies it if needed
-- @return boolean: true if lure application was initiated, false if casting should proceed
function Lures:CheckAndApplyLure()
    -- 1. Check if pole already has an active lure
    if self:HasActiveLure() then
        return false
    end

    -- 2. Find best available lure in bags
    local bag, slot, lureName = self:FindBestLure()
    if not bag or not slot then
        return false -- No lures available in bags
    end

    -- 3. Apply lure across client versions
    local mainHandSlot = GetInventorySlotInfo and GetInventorySlotInfo("MainHandSlot") or 16

    -- Secure client branch (WotLK 3.3.5+, Modern)
    if InCombatLockdown ~= nil and OneFish.secureButton then
        OneFish.secureButton:SetAttribute("type", "item")
        OneFish.secureButton:SetAttribute("item", bag .. " " .. slot)
        OneFish.secureButton:SetAttribute("target-slot", mainHandSlot)
        if SetOverrideBindingClick then
            SetOverrideBindingClick(OneFish.secureButton, true, "BUTTON2", "OneFishSecureButton")
            OneFish.secureButtonArmedTime = GetTime()
        end
        OneFish:Print("Applying " .. (lureName or "lure") .. "...")
        return true
    end

    -- Direct execution branch (Vanilla 1.12 / Turtle WoW 1.16)
    local useItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
    if useItem then
        useItem(bag, slot)
        if SpellIsTargeting and SpellIsTargeting() then
            if PickupInventoryItem then
                PickupInventoryItem(mainHandSlot)
            end
            if SpellIsTargeting and SpellIsTargeting() and SpellStopTargeting then
                SpellStopTargeting()
            end
            OneFish:Print("Applying " .. (lureName or "lure") .. "...")
            return true
        end
    end

    return false
end
