--[[
    OneFish - Core.lua
    Lightweight, high-performance fishing engine for World of Warcraft.
    Features:
      - Double-click to cast (Right-click, Left-click, or Either button)
      - Instant arming on second click with secure execution across all client versions
      - Auto-detection of equipped fishing poles
      - Bobber protection (reels in without re-casting)
      - Click-to-Move suppression while fishing
      - Fast Auto-Looting for fishing catches
      - Universal compatibility across Vanilla 1.12, Turtle WoW 1.16, WotLK 3.3.5, and Modern WoW 1.60.1 / 11.0+
--]]

local addonName, addonTable = ...

-- Global Namespace Export
_G.OneFish = _G.OneFish or addonTable
local OneFish = _G.OneFish

OneFish.name = addonName
OneFish.version = "1.0.0"
OneFish.isFishingMode = false
OneFish.isInitialized = false

-- Runtime state tracking
OneFish.lastClickTime = 0
OneFish.lastClickButton = nil
OneFish.cachedFishingSpellIndex = nil
OneFish.cachedFishingSpellName = nil
OneFish.savedClickToMove = nil

-- Default Configuration
OneFish.defaults = {
    enabled = true,
    doubleClickCast = true,
    mouseButton = "RightButton", -- "RightButton", "LeftButton", "Both"
    doubleClickSpeed = 0.40,     -- Double-click threshold in seconds (0.20 - 0.70)
    autoLure = true,             -- Automatically apply best lure if missing
    enhanceAudio = true,         -- Boost SFX volume and mute music while pole is equipped
    masterVolume = 1.0,          -- Boosted Master volume (0.0 - 1.0)
    sfxVolume = 1.0,             -- Boosted SFX volume (0.0 - 1.0)
    muteMusic = true,            -- Mute background music while fishing
    muteAmbience = false,        -- Mute ambient environment sounds while fishing
    autoLoot = true,             -- Automatically loot fishing catches
    disableClickToMove = true,   -- Suppress Click-To-Move while fishing to prevent unwanted walking
    showChatMessages = true,     -- Show status messages in chat
    collapsedSections = {
        mechanics = false,
        lures = false,
        audio = false,
        loot = false,
        general = false,
    },
}

function OneFish:RefreshUI()
    -- Defined in OptionsUI.lua
end

-------------------------------------------------------------------------------
-- Database & Initialization
-------------------------------------------------------------------------------

function OneFish:InitDB()
    if not OneFishDB then
        OneFishDB = {}
    end
    for k, v in pairs(self.defaults) do
        if OneFishDB[k] == nil then
            if type(v) == "table" then
                OneFishDB[k] = {}
                for subK, subV in pairs(v) do
                    OneFishDB[k][subK] = subV
                end
            else
                OneFishDB[k] = v
            end
        end
    end
end

function OneFish:Print(msg)
    if OneFishDB and not OneFishDB.showChatMessages then return end
    local prefix = "|cff00ccff[OneFish]|r "
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(msg))
    else
        print(prefix .. tostring(msg))
    end
end

-------------------------------------------------------------------------------
-- Helper: Safe Item ID from Link
-------------------------------------------------------------------------------

local function GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    local _, _, itemID = string.find(itemLink, "item:(%d+)")
    return tonumber(itemID)
end

-------------------------------------------------------------------------------
-- Fishing Pole Identification
-------------------------------------------------------------------------------

-- Comprehensive list of known fishing poles (Vanilla, Turtle WoW, TBC, WotLK)
OneFish.POLE_IDS = {
    [6256]  = true, -- Fishing Pole
    [6365]  = true, -- Strong Fishing Pole
    [6366]  = true, -- Darkwood Fishing Pole
    [6367]  = true, -- Big Iron Fishing Pole
    [12225] = true, -- Blump Family Fishing Pole
    [19022] = true, -- Nat Pagle's Extreme Angler FC-5000
    [19970] = true, -- Arcanite Fishing Pole
    [25924] = true, -- Mastercraft Kalu'ak Fishing Pole (TBC/WotLK)
    [44050] = true, -- Mastercraft Kalu'ak Fishing Pole
    [45858] = true, -- Nat's Lucky Fishing Pole
    [45991] = true, -- Bone Fishing Pole
    [45992] = true, -- Jeweled Fishing Pole
    [46337] = true, -- Dragon Fishing Pole
    [81001] = true, -- Bamboo Fishing Pole (Turtle WoW)
    [81002] = true, -- Reinforced Fishing Pole (Turtle WoW)
}

--- Checks whether the player currently has a fishing pole equipped in the main hand (Slot 16)
-- @return boolean, string|nil (link), string|nil (name)
function OneFish:IsFishingPoleEquipped()
    local slotID = GetInventorySlotInfo and GetInventorySlotInfo("MainHandSlot") or 16
    local itemLink = GetInventoryItemLink("player", slotID)
    
    if not itemLink then
        return false, nil, nil
    end

    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

    -- 1. Check Item ID against known poles
    local itemID = GetItemIDFromLink(itemLink)
    if itemID and self.POLE_IDS[itemID] then
        local itemName = getItemInfo and getItemInfo(itemLink) or "Fishing Pole"
        return true, itemLink, itemName
    end

    -- 2. Inspect item subtype via GetItemInfo
    if getItemInfo then
        local itemName, _, _, _, _, itemType, itemSubType = getItemInfo(itemLink)
        if itemSubType and (
            itemSubType == "Fishing Poles" or 
            itemSubType == "Fishing Pole" or 
            string.find(string.lower(itemSubType), "fish")
        ) then
            return true, itemLink, itemName
        end
    end

    -- 3. Texture check (match standard Blizzard fishing pole icon)
    local texture = GetInventoryItemTexture("player", slotID)
    if texture then
        local lowerTex = string.lower(texture)
        if string.find(lowerTex, "inv_fishingpole") or string.find(lowerTex, "trade_fishing") then
            -- Exclude known non-pole weapon with fishing texture (Nat Pagle's Fish Terminator - 19944)
            if itemID ~= 19944 then
                local itemName = getItemInfo and getItemInfo(itemLink) or "Fishing Pole"
                return true, itemLink, itemName
            end
        end
    end

    -- 4. Tooltip fallback check
    if not self.scanTooltip then
        self.scanTooltip = CreateFrame("GameTooltip", "OneFishScanTooltip", UIParent, "GameTooltipTemplate")
        self.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    self.scanTooltip:ClearLines()
    self.scanTooltip:SetInventoryItem("player", slotID)
    
    for i = 1, self.scanTooltip:NumLines() do
        local line = _G["OneFishScanTooltipTextLeft" .. i]
        local text = line and line:GetText()
        if text then
            local lower = string.lower(text)
            if string.find(lower, "fishing pole") or string.find(lower, "requires fishing") then
                local itemName = getItemInfo and getItemInfo(itemLink) or "Fishing Pole"
                return true, itemLink, itemName
            end
        end
    end

    return false, nil, nil
end

-------------------------------------------------------------------------------
-- Fishing Spell Resolver (100% Cross-Client Safe)
-------------------------------------------------------------------------------

local FISHING_SPELL_IDS = { 131474, 7620, 7731, 7732, 18248, 33095, 51294 }

--- Resolves the localized fishing spell name and spellbook index
-- Supports C_Spell (11.0 / 1.60+), GetSpellInfo, C_SpellBook, and legacy SpellBook scanning
function OneFish:GetFishingSpellInfo()
    if self.cachedFishingSpellName then
        return self.cachedFishingSpellIndex, self.cachedFishingSpellName
    end

    -- 1. Modern C_Spell API (WoW 11.0+, 1.60.1+)
    if C_Spell and C_Spell.GetSpellInfo then
        for _, id in ipairs(FISHING_SPELL_IDS) do
            local ok, info = pcall(C_Spell.GetSpellInfo, id)
            if ok and info and info.name and info.name ~= "" then
                self.cachedFishingSpellName = info.name
                self.cachedFishingSpellIndex = id
                return id, info.name
            end
        end
    end

    -- 2. Legacy GetSpellInfo (WoW 2.0 - 10.x)
    if GetSpellInfo then
        for _, id in ipairs(FISHING_SPELL_IDS) do
            local ok, name = pcall(GetSpellInfo, id)
            if ok and name and name ~= "" then
                self.cachedFishingSpellName = name
                self.cachedFishingSpellIndex = id
                return id, name
            end
        end
    end

    -- 3. Modern SpellBook via C_SpellBook (WoW 11.0+, 1.60.1+)
    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
        for i = 1, 100 do
            local ok, name = pcall(C_SpellBook.GetSpellBookItemName, i, bank)
            if ok and name and name ~= "" then
                local lower = string.lower(name)
                if string.find(lower, "fish") or string.find(lower, "angel") or string.find(lower, "pêche") or string.find(lower, "peche") or string.find(lower, "pesca") or string.find(lower, "рыб") then
                    self.cachedFishingSpellIndex = i
                    self.cachedFishingSpellName = name
                    return i, name
                end
            end
        end
    end

    -- 4. Legacy Spellbook Scan via GetSpellName (Vanilla 1.12 / TBC / WotLK)
    if GetSpellName then
        local bookType = BOOKTYPE_SPELL or "spell"
        local numSpells = 100
        if GetNumSpellTabs then
            local numTabs = GetNumSpellTabs()
            if numTabs and numTabs > 0 then
                local _, _, offset, numTabSpells = GetSpellTabInfo(numTabs)
                if offset and numTabSpells then
                    numSpells = offset + numTabSpells
                end
            end
        end

        for i = 1, numSpells do
            local name = GetSpellName(i, bookType)
            if name and name ~= "" then
                local lower = string.lower(name)
                if string.find(lower, "fish") or string.find(lower, "angel") or string.find(lower, "pêche") or string.find(lower, "peche") or string.find(lower, "pesca") or string.find(lower, "рыб") then
                    self.cachedFishingSpellIndex = i
                    self.cachedFishingSpellName = name
                    return i, name
                end
            end
        end
    end

    -- 5. Safe Fallback
    self.cachedFishingSpellName = "Fishing"
    return nil, "Fishing"
end

-------------------------------------------------------------------------------
-- Bobber & Mouseover Protection
-------------------------------------------------------------------------------

--- Determines if the cursor is currently hovering over the fishing bobber
-- When hovering over the bobber, right-clicks should reel in / interact, not cast
function OneFish:IsMouseOverBobber()
    if GameTooltip and GameTooltip:IsVisible() then
        local text = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
        if not text and _G["GameTooltipTextLeft1"] then
            text = _G["GameTooltipTextLeft1"]:GetText()
        end
        if text then
            local lower = string.lower(text)
            if string.find(lower, "fishing bobber") or 
               string.find(lower, "bobber") or 
               string.find(lower, "schwimmer") or 
               string.find(lower, "flotteur") or 
               string.find(lower, "поплавок") or
               string.find(lower, "浮动") then
                return true
            end
        end
    end
    return false
end

--- Determines if the cursor is currently over an interactive game unit (NPC, player, target)
function OneFish:IsMouseOverUnit()
    if UnitExists and UnitExists("mouseover") then
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Fishing Mode Coordinator
-------------------------------------------------------------------------------

function OneFish:UpdateFishingMode()
    if not OneFishDB or not OneFishDB.enabled then
        if self.isFishingMode then
            self:ExitFishingMode()
        end
        return
    end

    -- Do not alter fishing mode while in combat
    if InCombatLockdown and InCombatLockdown() then
        if self.isFishingMode then
            self:ExitFishingMode()
        end
        return
    end

    local isPole, _, poleName = self:IsFishingPoleEquipped()

    if isPole and not self.isFishingMode then
        self:EnterFishingMode(poleName)
    elseif not isPole and self.isFishingMode then
        self:ExitFishingMode()
    end
end

function OneFish:EnterFishingMode(poleName)
    self.isFishingMode = true

    -- 1. Click-to-Move Suppression
    if OneFishDB.disableClickToMove and GetCVar and SetCVar then
        local ctm = GetCVar("autointeract")
        if ctm == "1" then
            self.savedClickToMove = "1"
            SetCVar("autointeract", "0")
        end
    end

    -- 2. Audio Enhancement
    if OneFishDB.enhanceAudio and self.Audio and self.Audio.Boost then
        self.Audio:Boost()
    end

    if OneFishDB.showChatMessages and poleName then
        self:Print("Fishing mode active (" .. poleName .. ")")
    end
end

function OneFish:ExitFishingMode()
    self.isFishingMode = false

    -- Clear any pending secure bindings
    if self.secureButton and ClearOverrideBindings then
        ClearOverrideBindings(self.secureButton)
    end

    -- 1. Restore Click-to-Move
    if self.savedClickToMove and SetCVar then
        SetCVar("autointeract", self.savedClickToMove)
        self.savedClickToMove = nil
    end

    -- 2. Restore Audio
    if self.Audio and self.Audio.Restore then
        self.Audio:Restore()
    end
end

-------------------------------------------------------------------------------
-- Double-Click Arming & Execution Engine
-------------------------------------------------------------------------------

--- Check whether the clicked button matches user preferences
function OneFish:IsClickButtonAllowed(button)
    local pref = OneFishDB and OneFishDB.mouseButton or "RightButton"
    if pref == "Both" then
        return button == "RightButton" or button == "LeftButton"
    elseif pref == "LeftButton" then
        return button == "LeftButton"
    else
        return button == "RightButton"
    end
end

--- Arms and triggers casting upon detecting the second click on MouseDown
-- Arming on MouseDown guarantees that the subsequent MouseUp hardware event securely triggers the cast!
function OneFish:PrepareAndExecuteCast(button)
    if InCombatLockdown and InCombatLockdown() then return end
    if not self.isFishingMode then return end

    -- Stop camera mouselook if active
    if IsMouselooking and IsMouselooking() then
        MouselookStop()
    end

    local buttonKey = (button == "LeftButton") and "BUTTON1" or "BUTTON2"

    -- 1. Check if client uses SecureActionButton (Protected clients: 1.60.1, WotLK, Modern)
    if InCombatLockdown ~= nil and self.secureButton then
        local appliedLure = false

        -- Check Auto-Lure
        if OneFishDB.autoLure and self.Lures and not self.Lures:HasActiveLure() then
            local bag, slot, lureName = self.Lures:FindBestLure()
            if bag and slot then
                local mainHandSlot = GetInventorySlotInfo and GetInventorySlotInfo("MainHandSlot") or 16
                self.secureButton:SetAttribute("type", "item")
                self.secureButton:SetAttribute("item", bag .. " " .. slot)
                self.secureButton:SetAttribute("target-slot", mainHandSlot)
                appliedLure = true
                OneFish:Print("Applying " .. (lureName or "lure") .. "...")
            end
        end

        if not appliedLure then
            local _, spellName = self:GetFishingSpellInfo()
            self.secureButton:SetAttribute("type", "spell")
            self.secureButton:SetAttribute("spell", spellName or "Fishing")
        end

        if SetOverrideBindingClick then
            SetOverrideBindingClick(self.secureButton, true, buttonKey, "OneFishSecureButton")
            self.secureButtonArmedTime = GetTime()
        end
        return
    end

    -- 2. Direct execution branch (Vanilla 1.12 / non-secure client)
    if OneFishDB.autoLure and self.Lures and self.Lures.CheckAndApplyLure then
        local applied = self.Lures:CheckAndApplyLure()
        if applied then return end
    end

    local spellIndex, spellName = self:GetFishingSpellInfo()
    if spellIndex and CastSpell and BOOKTYPE_SPELL then
        CastSpell(spellIndex, BOOKTYPE_SPELL)
    elseif CastSpellByName then
        CastSpellByName(spellName or "Fishing")
    end
end

-------------------------------------------------------------------------------
-- World Mouse Event Interception
-------------------------------------------------------------------------------

function OneFish:OnWorldMouseDown(button)
    button = button or arg1 or "RightButton"

    if not self:IsClickButtonAllowed(button) then return end
    if not OneFishDB or not OneFishDB.enabled or not OneFishDB.doubleClickCast then return end
    if not self.isFishingMode then return end
    if InCombatLockdown and InCombatLockdown() then return end

    -- Ignore if hovering over the bobber on Right Click (player is reeling in / looting)
    if button == "RightButton" and self:IsMouseOverBobber() then
        self.lastClickTime = 0
        self.lastClickButton = nil
        return
    end

    -- Ignore if hovering over an NPC, vendor, or player
    if self:IsMouseOverUnit() then
        self.lastClickTime = 0
        self.lastClickButton = nil
        return
    end

    local now = GetTime()
    local timeDiff = now - (self.lastClickTime or 0)
    local maxWait = OneFishDB.doubleClickSpeed or 0.40

    if (self.lastClickButton == button) and (timeDiff > 0.05) and (timeDiff <= maxWait) then
        -- DOUBLE-CLICK DETECTED!
        self.lastClickTime = 0
        self.lastClickButton = nil
        self:PrepareAndExecuteCast(button)
    else
        -- First click
        self.lastClickTime = now
        self.lastClickButton = button
    end
end

function OneFish:OnWorldMouseUp(button)
    -- MouseUp is handled natively by the secure action button binding armed on MouseDown
end

-------------------------------------------------------------------------------
-- Secure Action Button Setup
-------------------------------------------------------------------------------

function OneFish:SetupSecureButton()
    if InCombatLockdown == nil then return end

    local btn = CreateFrame("Button", "OneFishSecureButton", UIParent, "SecureActionButtonTemplate")
    btn:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    btn:SetSize(1, 1)
    btn:RegisterForClicks("RightButtonUp", "LeftButtonUp")
    
    btn:SetScript("PostClick", function(self)
        if ClearOverrideBindings then
            ClearOverrideBindings(self)
        end
    end)

    -- Auto-clear override binding timeout (if player didn't complete click)
    btn:SetScript("OnUpdate", function(self, elapsed)
        if OneFish.secureButtonArmedTime then
            if (GetTime() - OneFish.secureButtonArmedTime) > 0.8 then
                if ClearOverrideBindings then
                    ClearOverrideBindings(self)
                end
                OneFish.secureButtonArmedTime = nil
            end
        end
    end)

    self.secureButton = btn
end

-------------------------------------------------------------------------------
-- WorldFrame Interception Hook
-------------------------------------------------------------------------------

function OneFish:HookWorldFrame()
    if not WorldFrame then return end

    if WorldFrame.HookScript then
        WorldFrame:HookScript("OnMouseDown", function(_, button)
            OneFish:OnWorldMouseDown(button)
        end)
    else
        local origMouseDown = WorldFrame:GetScript("OnMouseDown")
        WorldFrame:SetScript("OnMouseDown", function()
            if origMouseDown then origMouseDown() end
            OneFish:OnWorldMouseDown(arg1 or "RightButton")
        end)
    end
end

-------------------------------------------------------------------------------
-- Event Dispatcher & Lifecycle
-------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "OneFishEventFrame", UIParent)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("ITEM_LOCK_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("SPELLS_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local arg1 = ...

    if event == "ADDON_LOADED" and arg1 == addonName then
        OneFish:InitDB()
        OneFish:SetupSecureButton()
        OneFish:HookWorldFrame()

        -- Register with OneSwatter if present
        if _G.OneSwatter and _G.OneSwatter.RegisterAddon then
            _G.OneSwatter:RegisterAddon("OneFish")
        end

    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        OneFish:InitDB()
        OneFish.isInitialized = true
        OneFish:UpdateFishingMode()

    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then
            OneFish:UpdateFishingMode()
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "ITEM_LOCK_CHANGED" then
        OneFish:UpdateFishingMode()

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Drop fishing mode & clear bindings upon entering combat
        if OneFish.isFishingMode then
            OneFish:ExitFishingMode()
        end
        if OneFish.secureButton and ClearOverrideBindings then
            ClearOverrideBindings(OneFish.secureButton)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        OneFish:UpdateFishingMode()

    elseif event == "SPELLS_CHANGED" then
        OneFish.cachedFishingSpellIndex = nil
        OneFish.cachedFishingSpellName = nil

    elseif event == "LOOT_OPENED" then
        -- Fast Fishing Auto-Loot
        if OneFishDB and OneFishDB.autoLoot and OneFish.isFishingMode then
            local isFishLoot = IsFishingLoot and IsFishingLoot()
            if isFishLoot == nil then
                isFishLoot = true
            end
            if isFishLoot then
                local numLoot = GetNumLootItems and GetNumLootItems() or 0
                for slot = 1, numLoot do
                    if LootSlot then
                        LootSlot(slot)
                    end
                end
            end
        end
    end
end)
