--[[
    OneFish - OptionsUI.lua
    Full-featured configuration interface for OneFish matching the MovableFrames architecture.
    Features:
      - Integrated Blizzard AddOns Category (Game Menu -> Options -> AddOns -> OneFish)
      - "Pop Out Independent Window" button to switch from Blizzard menu to floating dialog
      - Standalone movable HUD Edit Mode style dialog window (/onefish or /of)
      - Dual parenting via GetOrCreateUIContent() to eliminate code duplication
      - Interactive checkboxes, steppers, and collapsible section banners
      - Choice of Right-Click, Left-Click, or Either button for casting
      - Reset Defaults, Close, and ESC key support
--]]

local addonName, addonTable = ...
local OneFish = _G.OneFish or addonTable

OneFish.OptionsUI = {}
local OptionsUI = OneFish.OptionsUI

local frame = nil
local standaloneFrame = nil
local blizzardCategoryPanel = nil

-- Safe BackdropTemplate across all WoW client versions (1.12, Turtle, WotLK, Modern)
local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

local function ApplyBackdrop(target, backdropInfo)
    if BackdropTemplateMixin and not target.SetBackdrop then
        Mixin(target, BackdropTemplateMixin)
    end
    if target.SetBackdrop then
        target:SetBackdrop(backdropInfo)
    end
end

-------------------------------------------------------------------------------
-- Widget Creators
-------------------------------------------------------------------------------

local function CreateButton(parent, labelText, width, height, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 120, height or 24)
    btn:SetText(labelText)
    if onClick then
        btn:SetScript("OnClick", onClick)
    end
    return btn
end

local function CreateCheckbox(parent, labelText, getValue, setValue, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    if not cb.text then
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    end
    cb.text:SetText(labelText)

    cb:SetScript("OnShow", function(self)
        self:SetChecked(getValue())
    end)
    cb:SetScript("OnClick", function(self)
        setValue(self:GetChecked())
        if onChange then onChange(self:GetChecked()) end
    end)
    return cb
end

local function CreateSubLabel(parent, text, isSmall)
    local fs = parent:CreateFontString(nil, "OVERLAY", isSmall and "GameFontDisableSmall" or "GameFontHighlightSmall")
    fs:SetText(text)
    return fs
end

local function CreateStepper(parent, minVal, maxVal, step, getter, setter, formatStr, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(160, 22)

    local btnMinus = CreateButton(container, "-", 22, 20, nil)
    btnMinus:SetPoint("LEFT", container, "LEFT", 0, 0)

    local valText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("CENTER", container, "CENTER", 0, 0)

    local btnPlus = CreateButton(container, "+", 22, 20, nil)
    btnPlus:SetPoint("RIGHT", container, "RIGHT", 0, 0)

    local function UpdateVal(newVal)
        newVal = math.max(minVal, math.min(maxVal, newVal))
        newVal = math.floor((newVal / step) + 0.5) * step
        setter(newVal)
        valText:SetText("|cff00ccff" .. string.format(formatStr, newVal) .. "|r")
        if onChange then onChange(newVal) end
    end

    btnMinus:SetScript("OnClick", function()
        UpdateVal(getter() - step)
    end)

    btnPlus:SetScript("OnClick", function()
        UpdateVal(getter() + step)
    end)

    container.valText = valText
    container.UpdateDisplay = function()
        valText:SetText("|cff00ccff" .. string.format(formatStr, getter()) .. "|r")
    end

    return container
end

local function SetSectionHeaderArrow(btn, isCollapsed)
    if not btn or not btn.arrow then return end

    local atlasName = isCollapsed and "editmode-down-arrow" or "editmode-up-arrow"
    local setAtlasSuccess = false

    if btn.arrow.SetAtlas then
        setAtlasSuccess = pcall(function()
            return btn.arrow:SetAtlas(atlasName, true)
        end)
        if not setAtlasSuccess then
            local fallbackAtlas = isCollapsed and "common-dropdown-icon-down" or "common-dropdown-icon-up"
            setAtlasSuccess = pcall(function()
                return btn.arrow:SetAtlas(fallbackAtlas, true)
            end)
        end
    end

    if not setAtlasSuccess then
        if isCollapsed then
            btn.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
        else
            btn.arrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
        end
        btn.arrow:SetTexCoord(0, 1, 0, 1)
        btn.arrow:SetVertexColor(0, 0.8, 1)
    end
    btn.arrow:SetSize(12, 12)
end

-------------------------------------------------------------------------------
-- Master UI Content Builder
-------------------------------------------------------------------------------

local function GetOrCreateUIContent()
    if frame then return frame.content end

    frame = {}

    local content = CreateFrame("Frame", "OneFishOptionsContent", UIParent)
    content:SetSize(480, 560)
    frame.content = content

    frame.secHeaders = {}

    local function MakeSectionHeader(secKey, titleText)
        local rule = content:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        if rule.SetColorTexture then
            rule:SetColorTexture(0.2, 0.45, 0.65, 0.6)
        else
            rule:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
        end

        local btn = CreateFrame("Button", nil, content)
        btn:SetSize(16, 16)
        btn.arrow = btn:CreateTexture(nil, "ARTWORK")
        btn.arrow:SetPoint("CENTER")
        btn.arrow:SetSize(12, 12)

        local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
        title:SetText("|cff00ccff" .. titleText .. "|r")

        btn:SetScript("OnClick", function()
            OneFishDB.collapsedSections = OneFishDB.collapsedSections or {}
            OneFishDB.collapsedSections[secKey] = not OneFishDB.collapsedSections[secKey]
            OneFish:RefreshUI()
        end)

        frame.secHeaders[secKey] = { rule = rule, btn = btn, title = title }
    end

    -- 1. Master Enable Banner
    frame.cbEnable = CreateCheckbox(content, "|cffffd100Enable OneFish|r",
        function() return OneFishDB.enabled ~= false end,
        function(val) OneFishDB.enabled = val; OneFish:UpdateFishingMode(); OneFish:RefreshUI() end
    )

    -- Live fishing mode status line
    frame.lblStatus = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.lblStatus:SetJustifyH("LEFT")

    -- 2. Section: Core Mechanics
    MakeSectionHeader("mechanics", "Core Casting Engine")

    frame.cbDoubleClick = CreateCheckbox(content, "Enable Double-Click to Cast",
        function() return OneFishDB.doubleClickCast ~= false end,
        function(val) OneFishDB.doubleClickCast = val end
    )

    frame.lblMouseButton = CreateSubLabel(content, "Trigger Mouse Button:")
    frame.btnMouseButton = CreateButton(content, "Right Mouse Button", 170, 22, function()
        local current = OneFishDB.mouseButton or "RightButton"
        if current == "RightButton" then
            OneFishDB.mouseButton = "LeftButton"
        elseif current == "LeftButton" then
            OneFishDB.mouseButton = "Both"
        else
            OneFishDB.mouseButton = "RightButton"
        end
        OneFish:RefreshUI()
    end)

    frame.lblDoubleClickSpeed = CreateSubLabel(content, "Double-Click Timing Window:")
    frame.stepperDoubleClickSpeed = CreateStepper(content, 0.20, 0.70, 0.05,
        function() return OneFishDB.doubleClickSpeed or 0.40 end,
        function(val) OneFishDB.doubleClickSpeed = val end,
        "%.2fs"
    )

    frame.cbClickToMove = CreateCheckbox(content, "Prevent Click-to-Move Water Walking",
        function() return OneFishDB.disableClickToMove ~= false end,
        function(val) OneFishDB.disableClickToMove = val end
    )
    frame.lblClickToMoveDesc = CreateSubLabel(content, "Temporarily disables Click-to-Move when pole is equipped so you don't run into water.", true)

    -- 3. Section: Smart Auto-Lure
    MakeSectionHeader("lures", "Smart Auto-Lure")

    frame.cbAutoLure = CreateCheckbox(content, "Enable Smart Auto-Lure",
        function() return OneFishDB.autoLure ~= false end,
        function(val) OneFishDB.autoLure = val end
    )
    frame.lblAutoLureDesc = CreateSubLabel(content, "When your pole lacks a lure, double-clicking applies the best usable lure in your bags;\nsubsequent double-clicks cast your line.", true)

    -- 4. Section: Audio Enhancement
    MakeSectionHeader("audio", "Fishing Audio Enhancement")

    frame.cbEnhanceAudio = CreateCheckbox(content, "Enable Fishing Audio Boost",
        function() return OneFishDB.enhanceAudio ~= false end,
        function(val)
            OneFishDB.enhanceAudio = val
            if val and OneFish.isFishingMode then
                OneFish.Audio:Boost()
            elseif not val and OneFish.Audio.isBoosted then
                OneFish.Audio:Restore()
            end
        end
    )

    frame.lblMasterVolume = CreateSubLabel(content, "Boosted Master & SFX Volume:")
    frame.stepperMasterVolume = CreateStepper(content, 0.20, 1.0, 0.10,
        function() return OneFishDB.masterVolume or 1.0 end,
        function(val)
            OneFishDB.masterVolume = val
            OneFishDB.sfxVolume = val
            if OneFish.Audio.isBoosted then
                OneFish.Audio:Restore()
                OneFish.Audio:Boost()
            end
        end,
        "%.0f%%"
    )

    frame.cbMuteMusic = CreateCheckbox(content, "Mute Background Music While Fishing",
        function() return OneFishDB.muteMusic ~= false end,
        function(val)
            OneFishDB.muteMusic = val
            if OneFish.Audio.isBoosted then
                OneFish.Audio:Restore()
                OneFish.Audio:Boost()
            end
        end
    )

    frame.cbMuteAmbience = CreateCheckbox(content, "Mute Ambient Sounds While Fishing",
        function() return OneFishDB.muteAmbience or false end,
        function(val)
            OneFishDB.muteAmbience = val
            if OneFish.Audio.isBoosted then
                OneFish.Audio:Restore()
                OneFish.Audio:Boost()
            end
        end
    )
    frame.lblAudioDesc = CreateSubLabel(content, "All audio CVars are restored to your exact pre-fishing settings upon unequip or combat.", true)

    -- 5. Section: Fast Auto-Loot
    MakeSectionHeader("loot", "Fast Auto-Looting")

    frame.cbAutoLoot = CreateCheckbox(content, "Instant Fishing Auto-Loot",
        function() return OneFishDB.autoLoot ~= false end,
        function(val) OneFishDB.autoLoot = val end
    )
    frame.lblAutoLootDesc = CreateSubLabel(content, "Automatically loots catches the instant the fishing window opens without holding Shift.", true)

    -- 6. Section: General & Chat Notifications
    MakeSectionHeader("general", "General & Notifications")

    frame.cbChat = CreateCheckbox(content, "Show Chat Notifications",
        function() return OneFishDB.showChatMessages == true end,
        function(val) OneFishDB.showChatMessages = val end
    )
    frame.lblChatDesc = CreateSubLabel(content, "Prints chat notifications when equipping a pole, unequipping, or applying lures.", true)

    return content
end

-------------------------------------------------------------------------------
-- Dynamic Layout & Refresh
-------------------------------------------------------------------------------

function OneFish:RefreshUI()
    if not frame or not frame.content then return end

    local yOfs = -10
    OneFishDB.collapsedSections = OneFishDB.collapsedSections or {}

    -- Master Enable Checkbox
    frame.cbEnable:ClearAllPoints()
    frame.cbEnable:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 15, yOfs)
    frame.cbEnable:SetChecked(OneFishDB.enabled ~= false)
    yOfs = yOfs - 30

    if frame.lblStatus then
        frame.lblStatus:ClearAllPoints()
        frame.lblStatus:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 42, yOfs)
        frame.lblStatus:SetText(OneFish.GetStatusSummary and OneFish:GetStatusSummary() or "")
        yOfs = yOfs - 24
    end

    local function LayoutSection(secKey, titleText, isFirst)
        local isCollapsed = OneFishDB.collapsedSections[secKey] or false
        local sec = frame.secHeaders[secKey]
        if not sec then return false end

        if not isFirst then
            sec.rule:ClearAllPoints()
            sec.rule:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 10, yOfs)
            sec.rule:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", -10, yOfs)
            sec.rule:Show()
            yOfs = yOfs - 8
        else
            sec.rule:Hide()
        end

        sec.btn:ClearAllPoints()
        sec.btn:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 10, yOfs)
        sec.btn:Show()
        SetSectionHeaderArrow(sec.btn, isCollapsed)

        sec.title:ClearAllPoints()
        sec.title:SetPoint("LEFT", sec.btn, "RIGHT", 6, 0)
        sec.title:Show()

        yOfs = yOfs - 26
        return not isCollapsed
    end

    -- Section 1: Core Mechanics
    local expMech = LayoutSection("mechanics", "Core Casting Engine", true)
    frame.cbDoubleClick:SetShown(expMech)
    frame.lblMouseButton:SetShown(expMech)
    frame.btnMouseButton:SetShown(expMech)
    frame.lblDoubleClickSpeed:SetShown(expMech)
    frame.stepperDoubleClickSpeed:SetShown(expMech)
    frame.cbClickToMove:SetShown(expMech)
    frame.lblClickToMoveDesc:SetShown(expMech)

    if expMech then
        frame.cbDoubleClick:ClearAllPoints()
        frame.cbDoubleClick:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 20, yOfs)
        frame.cbDoubleClick:SetChecked(OneFishDB.doubleClickCast ~= false)
        yOfs = yOfs - 28

        local pref = OneFishDB.mouseButton or "RightButton"
        local buttonLabel = "Right Mouse Button"
        if pref == "LeftButton" then
            buttonLabel = "Left Mouse Button"
        elseif pref == "Both" then
            buttonLabel = "Either Button (Left/Right)"
        end
        frame.lblMouseButton:ClearAllPoints()
        frame.lblMouseButton:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 42, yOfs + 2)
        frame.btnMouseButton:ClearAllPoints()
        frame.btnMouseButton:SetPoint("LEFT", frame.lblMouseButton, "RIGHT", 15, 0)
        frame.btnMouseButton:SetText(buttonLabel)
        yOfs = yOfs - 28

        frame.lblDoubleClickSpeed:ClearAllPoints()
        frame.lblDoubleClickSpeed:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 42, yOfs + 2)
        frame.stepperDoubleClickSpeed:ClearAllPoints()
        frame.stepperDoubleClickSpeed:SetPoint("LEFT", frame.lblDoubleClickSpeed, "RIGHT", 15, 0)
        frame.stepperDoubleClickSpeed.UpdateDisplay()
        yOfs = yOfs - 28

        frame.cbClickToMove:ClearAllPoints()
        frame.cbClickToMove:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 20, yOfs)
        frame.cbClickToMove:SetChecked(OneFishDB.disableClickToMove ~= false)
        yOfs = yOfs - 22

        frame.lblClickToMoveDesc:ClearAllPoints()
        frame.lblClickToMoveDesc:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 42, yOfs)
        yOfs = yOfs - 24
    end

    -- Section 2: Smart Auto-Lure
    local expLure = LayoutSection("lures", "Smart Auto-Lure", false)
    frame.cbAutoLure:SetShown(expLure)
    frame.lblAutoLureDesc:SetShown(expLure)

    if expLure then
        frame.cbAutoLure:ClearAllPoints()
        frame.cbAutoLure:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 20, yOfs)
        frame.cbAutoLure:SetChecked(OneFishDB.autoLure ~= false)
        yOfs = yOfs - 22

        frame.lblAutoLureDesc:ClearAllPoints()
        frame.lblAutoLureDesc:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 42, yOfs)
        yOfs = yOfs - 34
    end

    -- Section 3: Audio Enhancement
    local expAudio = LayoutSection("audio", "Fishing Audio Enhancement", false)
    frame.cbEnhanceAudio:SetShown(expAudio)
    frame.lblMasterVolume:SetShown(expAudio)
    frame.stepperMasterVolume:SetShown(expAudio)
    frame.cbMuteMusic:SetShown(expAudio)
    frame.cbMuteAmbience:SetShown(expAudio)
    frame.lblAudioDesc:SetShown(expAudio)

    if expAudio then
        frame.cbEnhanceAudio:ClearAllPoints()
        frame.cbEnhanceAudio:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 20, yOfs)
        frame.cbEnhanceAudio:SetChecked(OneFishDB.enhanceAudio ~= false)
        yOfs = yOfs - 28

        frame.lblMasterVolume:ClearAllPoints()
        frame.lblMasterVolume:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 42, yOfs + 2)
        frame.stepperMasterVolume:ClearAllPoints()
        frame.stepperMasterVolume:SetPoint("LEFT", frame.lblMasterVolume, "RIGHT", 15, 0)
        frame.stepperMasterVolume.UpdateDisplay()
        yOfs = yOfs - 28

        frame.cbMuteMusic:ClearAllPoints()
        frame.cbMuteMusic:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 42, yOfs)
        frame.cbMuteMusic:SetChecked(OneFishDB.muteMusic ~= false)
        yOfs = yOfs - 26

        frame.cbMuteAmbience:ClearAllPoints()
        frame.cbMuteAmbience:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 42, yOfs)
        frame.cbMuteAmbience:SetChecked(OneFishDB.muteAmbience or false)
        yOfs = yOfs - 22

        frame.lblAudioDesc:ClearAllPoints()
        frame.lblAudioDesc:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 42, yOfs)
        yOfs = yOfs - 24
    end

    -- Section 4: Fast Auto-Loot
    local expLoot = LayoutSection("loot", "Fast Auto-Looting", false)
    frame.cbAutoLoot:SetShown(expLoot)
    frame.lblAutoLootDesc:SetShown(expLoot)

    if expLoot then
        frame.cbAutoLoot:ClearAllPoints()
        frame.cbAutoLoot:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 20, yOfs)
        frame.cbAutoLoot:SetChecked(OneFishDB.autoLoot ~= false)
        yOfs = yOfs - 22

        frame.lblAutoLootDesc:ClearAllPoints()
        frame.lblAutoLootDesc:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 42, yOfs)
        yOfs = yOfs - 24
    end

    -- Section 5: General & Notifications
    local expGen = LayoutSection("general", "General & Notifications", false)
    frame.cbChat:SetShown(expGen)
    frame.lblChatDesc:SetShown(expGen)

    if expGen then
        frame.cbChat:ClearAllPoints()
        frame.cbChat:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 20, yOfs)
        frame.cbChat:SetChecked(OneFishDB.showChatMessages ~= false)
        yOfs = yOfs - 22

        frame.lblChatDesc:ClearAllPoints()
        frame.lblChatDesc:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 42, yOfs)
        yOfs = yOfs - 24
    end

    frame.content:SetHeight(math.abs(yOfs) + 30)
end

-------------------------------------------------------------------------------
-- Standalone Floating Control Panel Window (HUD Edit Mode Style)
-------------------------------------------------------------------------------

local function BuildStandaloneWindow()
    if standaloneFrame then return standaloneFrame end

    standaloneFrame = CreateFrame("Frame", "OneFishOptionsFrame", UIParent, backdropTemplate)
    standaloneFrame:SetSize(520, 560)
    standaloneFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    standaloneFrame:SetMovable(true)
    standaloneFrame:EnableMouse(true)
    standaloneFrame:RegisterForDrag("LeftButton")
    standaloneFrame:SetScript("OnDragStart", standaloneFrame.StartMoving)
    standaloneFrame:SetScript("OnDragStop", standaloneFrame.StopMovingOrSizing)
    standaloneFrame:SetFrameStrata("DIALOG")

    -- Check if Native Blizzard Edit Mode Dialog Border Template exists
    if _G["DialogBorderTranslucentTemplate"] then
        standaloneFrame.Border = CreateFrame("Frame", nil, standaloneFrame, "DialogBorderTranslucentTemplate")
        standaloneFrame.Border:SetAllPoints(standaloneFrame)
    else
        ApplyBackdrop(standaloneFrame, {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogFrame-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 5, right = 5, top = 5, bottom = 5 }
        })
        if standaloneFrame.SetBackdropColor then
            standaloneFrame:SetBackdropColor(0.04, 0.05, 0.09, 0.94)
            standaloneFrame:SetBackdropBorderColor(0.3, 0.85, 1.0, 0.90) -- Bright Cyan Edit Mode Outline
        end
    end

    -- Deep Slate Dark Background Texture
    local bgTex = standaloneFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bgTex:SetAllPoints(standaloneFrame)
    if bgTex.SetColorTexture then
        bgTex:SetColorTexture(0.03, 0.04, 0.08, 0.95)
    end

    -- Header Panel Bar
    local headerBar = standaloneFrame:CreateTexture(nil, "ARTWORK")
    headerBar:SetPoint("TOPLEFT", standaloneFrame, "TOPLEFT", 6, -6)
    headerBar:SetPoint("TOPRIGHT", standaloneFrame, "TOPRIGHT", -6, -6)
    headerBar:SetHeight(32)
    if headerBar.SetColorTexture then
        headerBar:SetColorTexture(0.08, 0.14, 0.22, 0.95)
    end

    -- Title Header Text
    local title = standaloneFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    title:SetPoint("LEFT", headerBar, "LEFT", 12, 0)
    title:SetText("|cff00ccffOneFish|r  |cffffd100Fishing Settings Panel|r  |cff888888(v1.0.0)|r")

    -- Close Button (X)
    local closeBtn = CreateFrame("Button", nil, standaloneFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", headerBar, "RIGHT", -2, 0)
    closeBtn:SetScript("OnClick", function()
        standaloneFrame:Hide()
    end)

    -- Inner Container Inset Box
    local insetBox = CreateFrame("Frame", nil, standaloneFrame, backdropTemplate)
    insetBox:SetPoint("TOPLEFT", standaloneFrame, "TOPLEFT", 10, -42)
    insetBox:SetPoint("BOTTOMRIGHT", standaloneFrame, "BOTTOMRIGHT", -10, 44)
    ApplyBackdrop(insetBox, {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    if insetBox.SetBackdropColor then
        insetBox:SetBackdropColor(0.02, 0.03, 0.06, 0.70)
        insetBox:SetBackdropBorderColor(0.2, 0.4, 0.6, 0.6)
    end

    -- ESC Key Support
    if UISpecialFrames then
        table.insert(UISpecialFrames, "OneFishOptionsFrame")
    end

    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", "OneFishOptionsScrollFrame", insetBox, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", insetBox, "TOPLEFT", 6, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", insetBox, "BOTTOMRIGHT", -26, 6)
    standaloneFrame.scrollFrame = scrollFrame

    standaloneFrame:SetScript("OnShow", function()
        -- Close Blizzard options if currently visible to prevent overlap
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            HideUIPanel(InterfaceOptionsFrame)
        end
        if SettingsPanel and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end

        local content = GetOrCreateUIContent()
        content:SetParent(scrollFrame)
        scrollFrame:SetScrollChild(content)
        content:Show()
        OneFish:RefreshUI()
    end)

    -- Reset Defaults Button (Bottom-Left)
    local btnReset = CreateButton(standaloneFrame, "Reset Defaults", 120, 24, function()
        OneFishDB = {}
        OneFish:InitDB()
        OneFish:RefreshUI()
        OneFish:Print("Settings reset to defaults.")
    end)
    btnReset:SetPoint("BOTTOMLEFT", standaloneFrame, "BOTTOMLEFT", 15, 12)

    -- Close Button (Bottom-Right)
    local btnClose = CreateButton(standaloneFrame, "Close", 100, 24, function()
        standaloneFrame:Hide()
    end)
    btnClose:SetPoint("BOTTOMRIGHT", standaloneFrame, "BOTTOMRIGHT", -15, 12)

    standaloneFrame:Hide()
    return standaloneFrame
end

function OneFish:ShowStandaloneUI()
    local win = BuildStandaloneWindow()
    if not win:IsShown() then
        win:Show()
    end
end

function OneFish:ToggleOptionsUI()
    local win = BuildStandaloneWindow()
    if win:IsShown() then
        win:Hide()
    else
        win:Show()
    end
end

-------------------------------------------------------------------------------
-- Blizzard Options -> AddOns Category Registration
-------------------------------------------------------------------------------

local function RegisterBlizzardCategory()
    if blizzardCategoryPanel then return blizzardCategoryPanel end

    blizzardCategoryPanel = CreateFrame("Frame", "OneFishBlizzardCategory", UIParent)
    blizzardCategoryPanel.name = "OneFish"

    local title = blizzardCategoryPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    title:SetPoint("TOPLEFT", 15, -15)
    title:SetText("|cff00ccffOneFish|r  |cffffd100Fishing Options|r  |cff888888(v1.0.0)|r")

    local btnPopOut = CreateButton(blizzardCategoryPanel, "Pop Out Independent Window", 220, 24, function()
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            HideUIPanel(InterfaceOptionsFrame)
        end
        if SettingsPanel and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end
        OneFish:ShowStandaloneUI()
    end)
    btnPopOut:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)

    local hintText = blizzardCategoryPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintText:SetPoint("LEFT", btnPopOut, "RIGHT", 10, 0)
    hintText:SetText("(Click to open floating window & close Game Menu options)")

    local scrollFrame = CreateFrame("ScrollFrame", "OneFishBlizzardScrollFrame", blizzardCategoryPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", blizzardCategoryPanel, "TOPLEFT", 10, -80)
    scrollFrame:SetPoint("BOTTOMRIGHT", blizzardCategoryPanel, "BOTTOMRIGHT", -26, 10)
    blizzardCategoryPanel.scrollFrame = scrollFrame

    local content = GetOrCreateUIContent()
    content:SetParent(scrollFrame)
    scrollFrame:SetScrollChild(content)
    content:Show()
    OneFish:RefreshUI()

    blizzardCategoryPanel:SetScript("OnShow", function()
        if standaloneFrame and standaloneFrame:IsShown() then
            standaloneFrame:Hide()
        end

        local content = GetOrCreateUIContent()
        content:SetParent(scrollFrame)
        scrollFrame:SetScrollChild(content)
        content:Show()
        OneFish:RefreshUI()
    end)

    -- Register category across Classic, WotLK, and Modern Retail
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(blizzardCategoryPanel, "OneFish")
        Settings.RegisterAddOnCategory(category)
        blizzardCategoryPanel.categoryID = category:GetID()
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(blizzardCategoryPanel)
    end

    return blizzardCategoryPanel
end

local categoryLoader = CreateFrame("Frame")
categoryLoader:RegisterEvent("PLAYER_LOGIN")
categoryLoader:SetScript("OnEvent", RegisterBlizzardCategory)

-------------------------------------------------------------------------------
-- Slash Commands (/onefish, /of)
-------------------------------------------------------------------------------

SLASH_ONEFISH1 = "/onefish"
SLASH_ONEFISH2 = "/of"

SlashCmdList["ONEFISH"] = function(msg)
    local cmd = string.lower(string.trim and string.trim(msg) or string.gsub(msg, "^%s*(.-)%s*$", "%1"))

    if cmd == "" or cmd == "config" or cmd == "options" or cmd == "gui" then
        OneFish:ToggleOptionsUI()

    elseif cmd == "toggle" then
        OneFishDB.enabled = not OneFishDB.enabled
        OneFish:UpdateFishingMode()
        OneFish:Print("Addon " .. (OneFishDB.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"), true)
        OneFish:RefreshUI()

    elseif cmd == "button" or cmd == "click" then
        local current = OneFishDB.mouseButton or "RightButton"
        if current == "RightButton" then
            OneFishDB.mouseButton = "LeftButton"
        elseif current == "LeftButton" then
            OneFishDB.mouseButton = "Both"
        else
            OneFishDB.mouseButton = "RightButton"
        end
        OneFish:Print("Double-Click Button: |cff00ccff" .. OneFishDB.mouseButton .. "|r", true)
        OneFish:RefreshUI()

    elseif cmd == "lure" then
        OneFishDB.autoLure = not OneFishDB.autoLure
        OneFish:Print("Auto-Lure " .. (OneFishDB.autoLure and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"), true)
        OneFish:RefreshUI()

    elseif cmd == "sound" or cmd == "audio" then
        OneFishDB.enhanceAudio = not OneFishDB.enhanceAudio
        OneFish:Print("Audio Enhancement " .. (OneFishDB.enhanceAudio and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"), true)
        OneFish:RefreshUI()

    elseif cmd == "loot" then
        OneFishDB.autoLoot = not OneFishDB.autoLoot
        OneFish:Print("Fast Auto-Loot " .. (OneFishDB.autoLoot and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"), true)
        OneFish:RefreshUI()

    elseif cmd == "status" then
        OneFish:PrintStatus()

    elseif cmd == "debug" then
        OneFish.debugMode = not OneFish.debugMode
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[OneFish]|r Debug trace " .. (OneFish.debugMode and "|cff00ff00ON|r - double-click in the water and watch chat." or "|cffff0000OFF|r"))
        end

    elseif cmd == "help" then
        OneFish:Print("Command List:", true)
        print("  |cff00ccff/of|r or |cff00ccff/onefish|r - Open / toggle settings window")
        print("  |cff00ccff/of status|r - Print diagnostic status (pole, spell, fishing mode)")
        print("  |cff00ccff/of debug|r - Toggle click/cast debug trace in chat")
        print("  |cff00ccff/of toggle|r - Toggle OneFish on/off")
        print("  |cff00ccff/of button|r - Cycle click button (Right, Left, Either)")
        print("  |cff00ccff/of lure|r - Toggle smart auto-lure")
        print("  |cff00ccff/of sound|r - Toggle fishing audio boost")
        print("  |cff00ccff/of loot|r - Toggle fast auto-loot")
    else
        OneFish:ToggleOptionsUI()
    end
end
