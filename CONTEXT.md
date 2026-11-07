# AI Context & Living Specification — OneFish

> **Living Document**: This file serves as the primary context, architectural specification, and state-handoff document for AI-assisted development across sessions. Update this file on every development cycle ("spin").

---

## 🎯 Overview & Scope

- **Addon Name**: OneFish
- **Current Version**: 1.0.1
- **Suite**: Part of the **OneSuite** family
- **GitHub Repository**:
  - Exists: TRUE
  - URL: https://github.com/Nuros-WoW-Forever-Addons/OneFish
  *(For any new addon, initialize with Exists: FALSE until first commit/push)*
- **Branching Policy**: All new features must be developed on a branch != `main` (e.g. `feature/<name>`)
- **Live Sync Path**: `/Applications/World of Warcraft/_forever_/Interface/AddOns/OneFish/`
- **Rollback Target**: Last working `main` branch commit
- **Release Package**: `.github/workflows/package.yml` generates `OneFish-latest.zip` on push to `main`
- **Target WoW Runtimes**: WoW Forever Beta (v1.60.1 / Interface 16001)
- **Primary Goal**: Deliver a zero-bloat, highly responsive fishing utility featuring double-click casting, automated lure application, dynamic audio boosting, and instant auto-looting without background sync chatter or heavy external libraries.

---

## 🏗️ Architecture & Component Map

### File Structure
- `OneFish.toc`: Addon manifest, load order, SavedVariables declaration (`OneFishDB`), optional dependencies (`OneSwatter`, `OnePanelUtils`).
- `Core.lua`: Double-click detection engine, fishing pole detection (MainHand slot 16 & Profession Tool slot 28), bobber reel-in protection, Click-to-Move suppression, fast auto-looting, and slash command dispatcher (`/of`, `/onefish`).
- `Lures.lua`: Item scan routines, fishing skill check, weapon temporary enchant detection (`GetWeaponEnchantInfo`), and optimal lure application logic.
- `Audio.lua`: Dynamic audio CVar manager (`Sound_MasterVolume`, `Sound_SFXVolume`, `Sound_MusicVolume`). CVar restoration on unequip or combat (`PLAYER_REGEN_DISABLED`).
- `OptionsUI.lua`: Dual-parented settings interface (embedded in Blizzard AddOns category + floating HUD Edit Mode window).

### Global State & Database Schema (`OneFishDB`)
```lua
OneFishDB = {
    enabled = true,                    -- Master addon toggle
    triggerButton = "RightButton",     -- "RightButton", "LeftButton", or "Any"
    doubleClickSpeed = 0.40,           -- Double click threshold in seconds (0.20 - 0.70)
    autoLure = true,                   -- Apply best usable lure when un-enchanted
    audioBoost = true,                 -- Boost SFX/Master volume while pole equipped
    fastAutoLoot = true,               -- Automatically grab loot on LOOT_READY
    preventWaterWalking = true,        -- Suppress Click-to-Move while pole is equipped
}
```

---

## 🔄 AI Development Cycle & Handoff Protocol

When picking up development on this addon:

1. **Orientation**: Read `CONTEXT.md` (this file) to verify current state, known issues, and active backlog items.
2. **Implementation**: Execute changes. For code refactoring or boilerplate, delegate to `qwen2.5-coder:32b` via the local `gx10_ollama` MCP server as mandated by user rules.
3. **Verification**: Verify in-game syntax and test using `/of` slash commands.
4. **Handoff Update**:
   - Move completed tasks from **Upcoming Backlog** to **Recent Completed Work**.
   - If user-facing features or commands changed, update `README.md` and append a new section in `CHANGELOG.md`.
   - Document newly discovered backlog items or edge cases in **Upcoming Backlog**.

---

## ✅ Recent Completed Work (Latest Spins)

### Spin 1.0.1
- Integrated automatic `"OneAddon"` chat tab creation and docking into `GENERAL_CHAT_DOCK`.
- Routed `OneFish:Print`, `OneFish:Debug`, and slash command help outputs to the `"OneAddon"` chat tab.
- Initialized `"OneAddon"` tab on `PLAYER_ENTERING_WORLD` with a 0.4s settling delay.

### Spin 1.0.0
- Complete initial release with double-click casting engine, bobber hover guard, and multi-client audio booster.
- Smart auto-luring with ranked lookup table (Aquadynamic Fish Attractor to Shiny Bauble).
- Integrated Blizzard AddOns options canvas + standalone HUD Edit Mode floating dialog.

---

## 📋 Living Roadmap & Upcoming Backlog (Next Spins)

### Priority 1: High Priority (Immediate Next Spin)
- [ ] **OneSwatter Logging Hooks**: Register with `OneSwatter` (`_G.OneSwatter:RegisterAddon("OneFish")`) and route audio/lure debug logs when debug mode is enabled.
- [ ] **Raft & Water Walking Toy Detection**: Ensure pole equipping does not prematurely cancel water-walking buff items (e.g. Anglers Fishing Raft) while keeping Click-to-Move suppressed.

### Priority 2: Medium Priority (Enhancements)
- [ ] **Fishing Skill Bar in Floating UI**: Show current fishing skill (e.g. `275 / 300 (+100)`) in the floating settings panel header.
- [ ] **Custom Catch Counter**: Optional lightweight session catch counter (fish caught / time elapsed) in chat or small HUD badge.

### Priority 3: Low Priority / Exploration
- [ ] **Fish School Tracking Auto-Enable**: Automatically turn on "Find Fish" minimap tracking when equipping a fishing pole if the player has learned the ability.

---

## 🧪 Testing & Verification Guide

- **Equip Pole**: Equip a fishing pole. Verify chat/audio confirms audio boost activation.
- **Double Click**: Double-click water surface. Confirm cast initiates on second click.
- **Auto-Lure**: Double-click with un-enchanted pole. Confirm lure is applied first, and next double-click casts line.
- **Combat Safety**: Trigger combat. Confirm audio CVars immediately restore to original values.
- **Slash Commands**: Run `/of` or `/onefish` to verify options window toggles cleanly.

---

## ⚠️ Technical Constraints & Engine Gotchas

- **Hardware Action Restrictions**: In Modern WoW (10.0+ / 11.0+), casting fishing requires an authentic hardware click event. Use secure button templates (`InCombatLockdown` checks) and never generate virtual click events.
- **Audio CVar State Recovery**: Audio CVars must always restore on `PLAYER_LOGOUT` or `PLAYER_REGEN_DISABLED` to prevent leaving player system volume permanently at 100%.
