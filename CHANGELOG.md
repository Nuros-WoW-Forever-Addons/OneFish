# Changelog — OneFish

All notable changes to **OneFish** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.1] - 2026-11-06
### Added
- **OneAddon Chat Tab Integration**:
  - Automatically routes all addon prints, fishing mode notifications, lure announcements, debug traces, and slash command feedback to the dedicated `"OneAddon"` chat tab instead of General chat.
  - Automatically creates and docks the `"OneAddon"` chat tab if missing, keeping public chat channels isolated.
  - Settles chat tab detection during `PLAYER_ENTERING_WORLD` with a 0.4s timer delay.

## [1.0.0] - 2026-10-10
### Added
- **Double-Click Casting Engine**: Double-click detection with customizable trigger mouse button (Right, Left, Either) and adjustable double-click timing window (0.20s – 0.70s).
- **Bobber & Unit Hover Protection**: Prevents accidental casting when mouse cursor hovers over the active fishing bobber, friendly players, or NPCs.
- **Smart Auto-Lure**: Automatically detects pole enchantment status and applies the highest-tier usable lure in bags on double-click.
- **Fishing Audio Booster**: Automatically raises Master & SFX volume to 100% and silences background music while a fishing pole is equipped; restores pre-fishing audio CVars upon unequip or combat.
- **Fast Auto-Looting**: Instantly loots catches when the loot window opens without requiring Shift key modifier.
- **Click-to-Move Suppression**: Temporarily disables Click-to-Move (`autointeract`) while fishing to prevent unwanted character movement into water.
- **Dual Options Architecture**: Integrated settings into native **Options → AddOns → OneFish** plus standalone HUD Edit Mode floating dialog panel (`/of` or `/onefish`).
- **Multi-Client Engine Support**: Compatibility layer supporting Vanilla 1.12, Turtle WoW 1.16, WotLK 3.3.5, and Modern WoW (1.60.1 / 11.0+).
