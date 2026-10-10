--[[
    OneFish - Audio.lua
    Dynamic sound manager for fishing.
    Boosts Master/SFX volume and mutes background music while a fishing pole is equipped
    so bobber splashes are crisp and unmistakable. Automatically restores all original
    audio CVars upon unequipping or entering combat.
--]]

local addonName, addonTable = ...
local OneFish = _G.OneFish or addonTable

OneFish.Audio = {}
local Audio = OneFish.Audio

Audio.isBoosted = false
Audio.savedCVars = {}

-- CVar mapping table supporting Vanilla 1.12, Turtle WoW 1.16, WotLK 3.3.5, and Modern WoW
Audio.CVAR_NAMES = {
    -- Key, Legacy 1.12 CVar, Modern CVar
    { key = "master",   cvar112 = "MasterVolume",   cvarModern = "Sound_MasterVolume"   },
    { key = "sfx",      cvar112 = "SoundVolume",    cvarModern = "Sound_SFXVolume"      },
    { key = "music",    cvar112 = "MusicVolume",    cvarModern = "Sound_MusicVolume"    },
    { key = "ambience", cvar112 = "AmbienceVolume", cvarModern = "Sound_AmbienceVolume" },
}

local function SafeGetCVar(cvarName)
    if not GetCVar then return nil end
    local val = GetCVar(cvarName)
    return val and tonumber(val)
end

local function SafeSetCVar(cvarName, val)
    if not SetCVar or not GetCVar then return end
    if GetCVar(cvarName) ~= nil then
        SetCVar(cvarName, tostring(val))
    end
end

--- Boost sound volume for fishing mode
function Audio:Boost()
    if self.isBoosted then return end
    if not OneFishDB or not OneFishDB.enhanceAudio then return end

    self.savedCVars = {}

    -- 1. Snapshot all active audio CVars
    for _, mapping in ipairs(self.CVAR_NAMES) do
        local modernVal = SafeGetCVar(mapping.cvarModern)
        local legVal = SafeGetCVar(mapping.cvar112)

        if modernVal ~= nil then
            self.savedCVars[mapping.cvarModern] = modernVal
        elseif legVal ~= nil then
            self.savedCVars[mapping.cvar112] = legVal
        end
    end

    -- 2. Apply boosted levels
    local masterTarget = OneFishDB.masterVolume or 1.0
    local sfxTarget = OneFishDB.sfxVolume or 1.0
    local musicTarget = OneFishDB.muteMusic and 0.0 or nil
    local ambienceTarget = OneFishDB.muteAmbience and 0.0 or nil

    for _, mapping in ipairs(self.CVAR_NAMES) do
        local targetVal = nil
        if mapping.key == "master" then
            targetVal = masterTarget
        elseif mapping.key == "sfx" then
            targetVal = sfxTarget
        elseif mapping.key == "music" and musicTarget ~= nil then
            targetVal = musicTarget
        elseif mapping.key == "ambience" and ambienceTarget ~= nil then
            targetVal = ambienceTarget
        end

        if targetVal ~= nil then
            SafeSetCVar(mapping.cvarModern, targetVal)
            SafeSetCVar(mapping.cvar112, targetVal)
        end
    end

    self.isBoosted = true
end

--- Restore original sound settings
function Audio:Restore()
    if not self.isBoosted then return end

    -- Reapply every snapshotted CVar
    for cvarName, originalVal in pairs(self.savedCVars) do
        SafeSetCVar(cvarName, originalVal)
    end

    self.savedCVars = {}
    self.isBoosted = false
end
