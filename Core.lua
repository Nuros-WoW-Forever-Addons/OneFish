--[[
    OneFish - Core.lua
    Lightweight, high-performance fishing engine for World of Warcraft.
    Features:
      - Double-click to cast (Right-click, Left-click, or Either button)
      - Instant arming on second click with secure execution across all client versions
      - Universal pole detection supporting MainHand (slot 16) and Profession Tool (slot 28)
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
OneFish.secureButtonArmedTime = nil

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
-- Helper Utilities
-------------------------------------------------------------------------------

local function GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    local _, _, itemID = string.find(itemLink, "item:(%d+)")
    return tonumber(itemID)
end

function OneFish:GetItemNameFromLink(link)
    if not link then return "Fishing Pole" end
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getItemInfo then
        local ok, name = pcall(getItemInfo, link)
        if ok and name and name ~= "" then return name end
    end
    local _, _, bracketName = string.find(link, "%[(.-)%]")
    if bracketName and bracketName ~= "" then
        return bracketName
    end
    return "Fishing Pole"
end

-------------------------------------------------------------------------------
-- Fishing Pole Identification (Universal Multi-Client)
-------------------------------------------------------------------------------

-- Comprehensive list of known fishing poles across all WoW eras
OneFish.POLE_IDS = {
    [6256]   = true, -- Fishing Pole
    [6365]   = true, -- Strong Fishing Pole
    [6366]   = true, -- Darkwood Fishing Pole
    [6367]   = true, -- Big Iron Fishing Pole
    [12225]  = true, -- Blump Family Fishing Pole
    [19022]  = true, -- Nat Pagle's Extreme Angler FC-5000
    [19970]  = true, -- Arcanite Fishing Pole
    [25924]  = true, -- Mastercraft Kalu'ak Fishing Pole
    [25978]  = true, -- Seth's Graphite Fishing Pole
    [44050]  = true, -- Mastercraft Kalu'ak Fishing Pole
    [45858]  = true, -- Nat's Lucky Fishing Pole
    [45991]  = true, -- Bone Fishing Pole
    [45992]  = true, -- Jeweled Fishing Pole
    [46337]  = true, -- Dragon Fishing Pole
    [81001]  = true, -- Bamboo Fishing Pole (Turtle WoW)
    [81002]  = true, -- Reinforced Fishing Pole (Turtle WoW)
    [133755] = true, -- Underlight Angler (Legion)
    [198288] = true, -- Khaz'gorite Fishing Pole (Dragonflight)
    [224522] = true, -- Algari Fishing Pole (The War Within)
    [224523] = true, -- Weaver's Fishing Pole
    [224524] = true, -- Artisan's Fishing Pole
}

--- Tests if a specific itemLink/itemID is a fishing pole across 6 robust detection layers
function OneFish:IsItemAFishingPole(itemLink, slotID, itemID)
    if not itemLink and not itemID then return false end

    itemID = itemID or GetItemIDFromLink(itemLink)

    -- 1. Check known item ID list
    if itemID and self.POLE_IDS[itemID] then
        return true
    end

    -- 2. C_Item.GetItemInfoInstant (subClassID 20 = Fishing Pole, instant synchronous check)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if getInstant then
        local target = itemID or itemLink
        local ok, _, _, _, _, _, classID, subClassID = pcall(getInstant, target)
        if ok and (subClassID == 20 or (Enum and Enum.ItemWeaponSubclass and subClassID == Enum.ItemWeaponSubclass.FishingPole)) then
            return true
        end
    end

    -- 3. GetItemInfo (itemSubType match)
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getItemInfo then
        local target = itemID or itemLink
        local ok, _, _, _, _, _, _, itemSubType = pcall(getItemInfo, target)
        if ok and itemSubType then
            local lower = string.lower(itemSubType)
            if string.find(lower, "fish") or string.find(lower, "angel") or string.find(lower, "pêche") or string.find(lower, "peche") or string.find(lower, "pesca") then
                return true
            end
        end
    end

    -- 4. Modern C_TooltipInfo scan
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem and slotID then
        local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slotID)
        if ok and data and data.lines then
            for _, line in ipairs(data.lines) do
                if line.leftText then
                    local lower = string.lower(line.leftText)
                    if string.find(lower, "fishing pole") or string.find(lower, "requires fishing") or string.find(lower, "angelrute") or string.find(lower, "canne à pêche") then
                        return true
                    end
                end
            end
        end
    end

    -- 5. Legacy Tooltip Scan (Classic / Vanilla 1.12)
    if slotID then
        if not self.scanTooltip then
            self.scanTooltip = CreateFrame("GameTooltip", "OneFishScanTooltip", UIParent, "GameTooltipTemplate")
            self.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        end
        self.scanTooltip:ClearLines()
        local ok = pcall(self.scanTooltip.SetInventoryItem, self.scanTooltip, "player", slotID)
        if ok then
            for i = 1, self.scanTooltip:NumLines() do
                local line = _G["OneFishScanTooltipTextLeft" .. i]
                local text = line and line:GetText()
                if text then
                    local lower = string.lower(text)
                    if string.find(lower, "fishing pole") or string.find(lower, "requires fishing") then
                        return true
                    end
                end
            end
        end
    end

    -- 6. Item Name Fallback
    local itemName = self:GetItemNameFromLink(itemLink)
    if itemName then
        local lowerName = string.lower(itemName)
        if string.find(lowerName, "fishing pole") or string.find(lowerName, "angelrute") or string.find(lowerName, "canne à pêche") then
            -- Exclude non-pole weapon with fishing in name (Nat Pagle's Fish Terminator - 19944)
            if itemID ~= 19944 then
                return true
            end
        end
    end

    return false
end

--- Checks whether the player currently has a fishing pole equipped (Slot 16 or Profession Tool Slot 28)
-- @return boolean, string|nil (link), string|nil (name), number|nil (slot)
function OneFish:IsFishingPoleEquipped()
    -- Check MainHandSlot (Slot 16)
    local slot16 = GetInventorySlotInfo and GetInventorySlotInfo("MainHandSlot") or 16
    local id16 = GetInventoryItemID and GetInventoryItemID("player", slot16)
    local link16 = GetInventoryItemLink("player", slot16)
    if (id16 and self.POLE_IDS[id16]) or (link16 and self:IsItemAFishingPole(link16, slot16, id16)) or (id16 and self:IsItemAFishingPole(nil, slot16, id16)) then
        local name = self:GetItemNameFromLink(link16)
        return true, link16, name, slot16
    end

    -- Check Profession Tool Slot (Slot 28) if present in modern clients
    local slot28 = INVSLOT_FISHING_TOOL or (GetInventorySlotInfo and GetInventorySlotInfo("FishingToolSlot")) or 28
    if slot28 then
        local id28 = GetInventoryItemID and GetInventoryItemID("player", slot28)
        local link28 = GetInventoryItemLink("player", slot28)
        if (id28 and self.POLE_IDS[id28]) or (link28 and self:IsItemAFishingPole(link28, slot28, id28)) or (id28 and self:IsItemAFishingPole(nil, slot28, id28)) then
            local name = self:GetItemNameFromLink(link28)
            return true, link28, name, slot28
        end
    end

    return false, nil, nil, nil
end

-------------------------------------------------------------------------------
-- Fishing Spell Resolver (100% Cross-Client Safe)
-------------------------------------------------------------------------------

local FISHING_SPELL_IDS = { 131474, 7620, 7731, 7732, 18248, 33095, 51294 }

--- Resolves the localized fishing spell name and spellbook index
function OneFish:GetFishingSpellInfo()
    if self.cachedFishingSpellName then
        return self.cachedFishingSpellIndex, self.cachedFishingSpellName
    end

    -- 1. Modern C_Spell API (GetSpellName - WoW 11.0+, 1.60.1+)
    if C_Spell and C_Spell.GetSpellName then
        for _, id in ipairs(FISHING_SPELL_IDS) do
            local ok, name = pcall(C_Spell.GetSpellName, id)
            if ok and name and name ~= "" then
                self.cachedFishingSpellName = name
                self.cachedFishingSpellIndex = id
                return id, name
            end
        end
    end

    -- 2. Modern C_Spell API (GetSpellInfo table - WoW 11.0+, 1.60.1+)
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

    -- 2. Modern Profession API (GetProfessions)
    if GetProfessions and GetProfessionInfo then
        local ok, _, _, _, fishProf = pcall(GetProfessions)
        if ok and fishProf then
            local ok2, name = pcall(GetProfessionInfo, fishProf)
            if ok2 and name and name ~= "" then
                self.cachedFishingSpellName = name
                return nil, name
            end
        end
    end

    -- 3. Legacy GetSpellInfo (WoW 2.0 - 10.x)
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

    -- 4. Modern SpellBook via C_SpellBook (WoW 11.0+, 1.60.1+)
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

    -- 5. Legacy Spellbook Scan via GetSpellName (Vanilla 1.12 / TBC / WotLK)
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

    -- 6. Safe Fallback
    self.cachedFishingSpellName = "Fishing"
    return nil, "Fishing"
end

-------------------------------------------------------------------------------
-- Bobber & Mouseover Protection
-------------------------------------------------------------------------------

--- Determines if the cursor is currently hovering over the fishing bobber
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
    self.secureButtonArmedTime = nil

    -- 1. Restore Click-to-Move
    if self.savedClickToMove and SetCVar then
        SetCVar("autointeract", self.savedClickToMove)
        self.savedClickToMove = nil
    end

    -- 2. Restore Audio
    if self.Audio and self.Audio.Restore then
        self.Audio:Restore()
    end

    if OneFishDB.showChatMessages then
        self:Print("Fishing mode ended.")
    end
end

-------------------------------------------------------------------------------
-- Double-Click Casting Engine
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

--- Arms and triggers casting upon detecting double-click
function OneFish:ArmDoubleCast(button)
    local buttonKey = (button == "LeftButton") and "BUTTON1" or "BUTTON2"

    -- 1. Protected client branch (1.60.1, WotLK, Modern)
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
                if SetOverrideBindingClick then
                    SetOverrideBindingClick(self.secureButton, true, buttonKey, "OneFishSecureButton")
                end
                appliedLure = true
                OneFish:Print("Applying " .. (lureName or "lure") .. "...")
            end
        end

        if not appliedLure then
            local _, spellName = self:GetFishingSpellInfo()
            self.secureButton:SetAttribute("type", "spell")
            self.secureButton:SetAttribute("spell", spellName or "Fishing")

            if SetOverrideBindingSpell then
                SetOverrideBindingSpell(self.secureButton, true, buttonKey, spellName or "Fishing")
            elseif SetOverrideBindingClick then
                SetOverrideBindingClick(self.secureButton, true, buttonKey, "OneFishSecureButton")
            end
        end

        self.secureButtonArmedTime = GetTime()
        return
    end

    -- 2. Non-secure client branch (Vanilla 1.12)
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

--- Unified Mouse Down Click Interceptor
function OneFish:HandleMouseDown(button)
    button = button or "RightButton"

    if not self:IsClickButtonAllowed(button) then return end
    if not OneFishDB or not OneFishDB.enabled or not OneFishDB.doubleClickCast then return end
    if not self.isFishingMode then return end
    if InCombatLockdown and InCombatLockdown() then return end

    -- Ignore if hovering over bobber with Right-Click (reeling in / looting)
    if button == "RightButton" and self:IsMouseOverBobber() then
        if self.secureButton and ClearOverrideBindings then
            ClearOverrideBindings(self.secureButton)
            self.secureButtonArmedTime = nil
        end
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

    -- Ignore duplicate events from the same physical click within 30ms (e.g. GLOBAL_MOUSE_DOWN + WorldFrame)
    if (self.lastClickButton == button) and (timeDiff < 0.03) then
        return
    end

    if (self.lastClickButton == button) and (timeDiff >= 0.03) and (timeDiff <= maxWait) then
        -- DOUBLE-CLICK DETECTED!
        self.lastClickTime = 0
        self.lastClickButton = nil

        if IsMouselooking and IsMouselooking() then
            MouselookStop()
        end

        self:ArmDoubleCast(button)
    else
        -- First click
        self.lastClickTime = now
        self.lastClickButton = button

        -- Clear any previous override binding from past clicks
        if self.secureButton and ClearOverrideBindings then
            ClearOverrideBindings(self.secureButton)
            self.secureButtonArmedTime = nil
        end
    end
end

-------------------------------------------------------------------------------
-- Secure Action Button Setup
-------------------------------------------------------------------------------

function OneFish:SetupSecureButton()
    if InCombatLockdown == nil then return end

    local btn = CreateFrame("Button", "OneFishSecureButton", UIParent, "SecureActionButtonTemplate")
    btn:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    btn:SetSize(1, 1)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    
    btn:SetScript("PostClick", function(self)
        if ClearOverrideBindings then
            ClearOverrideBindings(self)
        end
        OneFish.secureButtonArmedTime = nil
    end)

    -- Auto-clear override binding timeout after 1.2s if click wasn't completed
    btn:SetScript("OnUpdate", function(self, elapsed)
        if OneFish.secureButtonArmedTime then
            if (GetTime() - OneFish.secureButtonArmedTime) > 1.2 then
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
-- Mouse Event Hooking (GLOBAL_MOUSE_DOWN + WorldFrame)
-------------------------------------------------------------------------------

function OneFish:HookMouseEvents(f)
    -- 1. Modern WoW global mouse events
    pcall(function() f:RegisterEvent("GLOBAL_MOUSE_DOWN") end)

    -- 2. Fallback WorldFrame hooks (Classic 1.12 / older clients)
    if WorldFrame then
        if WorldFrame.HookScript then
            WorldFrame:HookScript("OnMouseDown", function(_, button)
                OneFish:HandleMouseDown(button)
            end)
        else
            local origMouseDown = WorldFrame:GetScript("OnMouseDown")
            WorldFrame:SetScript("OnMouseDown", function()
                if origMouseDown then origMouseDown() end
                OneFish:HandleMouseDown(arg1 or "RightButton")
            end)
        end
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
pcall(function() eventFrame:RegisterEvent("BAG_UPDATE_DELAYED") end)
pcall(function() eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED") end)

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local arg1 = ...

    if event == "ADDON_LOADED" and arg1 == addonName then
        OneFish:InitDB()
        OneFish:SetupSecureButton()
        OneFish:HookMouseEvents(self)

        -- Register with OneSwatter if present
        if _G.OneSwatter and _G.OneSwatter.RegisterAddon then
            _G.OneSwatter:RegisterAddon("OneFish")
        end

    elseif event == "GLOBAL_MOUSE_DOWN" then
        OneFish:HandleMouseDown(arg1)

    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        OneFish:InitDB()
        OneFish.isInitialized = true
        OneFish:UpdateFishingMode()

    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then
            OneFish:UpdateFishingMode()
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "ITEM_LOCK_CHANGED" or event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then
        OneFish:UpdateFishingMode()

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Drop fishing mode & clear bindings upon entering combat
        if OneFish.isFishingMode then
            OneFish:ExitFishingMode()
        end
        if OneFish.secureButton and ClearOverrideBindings then
            ClearOverrideBindings(OneFish.secureButton)
        end
        OneFish.secureButtonArmedTime = nil

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

-------------------------------------------------------------------------------
-- Debug Status Inspector (/of status)
-------------------------------------------------------------------------------

function OneFish:PrintStatus()
    local isPole, link, name, slot = self:IsFishingPoleEquipped()
    local _, spellName = self:GetFishingSpellInfo()
    self:Print("--- Diagnostic Status ---")
    print("  Addon Enabled: " .. (OneFishDB.enabled and "|cff00ff00Yes|r" or "|cffff0000No|r"))
    print("  Double-Click Cast: " .. (OneFishDB.doubleClickCast and "|cff00ff00Yes|r" or "|cffff0000No|r"))
    print("  Trigger Button: |cff00ccff" .. (OneFishDB.mouseButton or "RightButton") .. "|r")
    print("  Fishing Mode Active: " .. (self.isFishingMode and "|cff00ff00Yes|r" or "|cffff0000No|r"))
    print("  Equipped Pole: " .. (isPole and ("|cff00ff00" .. tostring(name) .. "|r (Slot " .. tostring(slot) .. ")") or "|cffff0000None detected|r"))
    if not isPole then
        local slot16 = GetInventorySlotInfo and GetInventorySlotInfo("MainHandSlot") or 16
        local id16 = GetInventoryItemID and GetInventoryItemID("player", slot16)
        local link16 = GetInventoryItemLink("player", slot16)
        print("  MainHand (Slot 16): Link=" .. tostring(link16 or "None") .. ", ItemID=" .. tostring(id16 or "None"))
    end
    print("  Detected Spell: |cff00ccff" .. tostring(spellName) .. "|r")
    print("  Double-Click Window: |cff00ccff" .. tostring(OneFishDB.doubleClickSpeed or 0.40) .. "s|r")
end
