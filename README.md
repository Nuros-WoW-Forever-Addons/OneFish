# OneFish

**OneFish** is a lightweight, zero-bloat fishing addon for World of Warcraft featuring double-click casting, smart auto-luring, audio enhancement, and fast auto-looting without heavy databases or background sync chatter.

Part of the **OneSuite** family of addons.

---

## 🚀 Features

- 🎣 **Double-Click to Cast**: Double-click anywhere in open water with your fishing pole equipped to instantly cast your line.
  - Supports **Right Mouse Button**, **Left Mouse Button**, or **Either Button**.
  - Configurable timing window (0.20s – 0.70s).
- 🐟 **Bobber & Unit Protection**: When hovering over your fishing bobber with right-click, double-click casting is suppressed so you cleanly reel in and loot your catch. Hovering over NPCs or players also prevents accidental casting.
- 🪱 **Smart Auto-Lure**: Automatically detects when your pole lacks a temporary enchant and applies the highest-grade usable lure in your bags (Aquadynamic Fish Attractor $\to$ Nightcrawlers $\to$ Shiny Bauble). Subsequent double-clicks cast your line.
- 🔊 **Fishing Audio Boost**: Automatically raises Master & SFX volume to 100% and silences background music while your fishing pole is equipped so bobber splashes are crisp and unmistakable. Automatically restores all audio CVars to your exact pre-fishing settings upon unequipping or entering combat.
- ⚡ **Fast Auto-Loot**: Automatically loots catches the instant the fishing window opens without needing to hold Shift.
- 🚫 **Water Walking Prevention**: Temporarily suppresses Click-to-Move (`autointeract`) while fishing so you don't accidentally walk into the water when double-clicking.
- ⚙️ **Dual Options Interface**: 
  - Integrated into the game's **Options $\to$ AddOns $\to$ OneFish** menu.
  - "Pop Out Independent Window" button to switch to the floating dialog.
  - Standalone movable HUD Edit Mode panel opened anytime via `/of` or `/onefish`.
- 🌐 **Multi-Client Architecture**: 100% compatible across Vanilla 1.12, Turtle WoW 1.16, WotLK 3.3.5, and Modern WoW (1.60.1 / 11.0+).

---

## 🛠️ Installation

Copy the `OneFish` directory into your World of Warcraft `Interface/AddOns/` directory:

```text
World of Warcraft/Interface/AddOns/OneFish/
├── OneFish.toc
├── Core.lua
├── Lures.lua
├── Audio.lua
├── OptionsUI.lua
└── README.md
```

Then start or reload World of Warcraft (`/reload`).

---

## 💻 Slash Commands

| Command | Description |
|---|---|
| `/of` or `/onefish` | Open / toggle settings panel |
| `/of toggle` | Toggle OneFish on or off |
| `/of button` | Cycle trigger mouse button (Right, Left, Either) |
| `/of lure` | Toggle smart auto-lure on or off |
| `/of sound` | Toggle fishing audio enhancement on or off |
| `/of loot` | Toggle fast auto-looting on or off |
| `/of help` | Show command list |
