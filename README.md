# Spin the Streamer

A bright, cartoony Roblox RNG simulator where players spin a wheel to collect streamer characters, equip them in plot slots, rebirth for more slots, and purchase boosts with Robux.

## Tech Stack

- **Roblox** (Luau)
- **Rojo** for filesystem-to-Studio sync
- No external frameworks -- pure Roblox APIs

## Project Structure

```
default.project.json        # Rojo project config
src/
  shared/                   # -> ReplicatedStorage.Shared
    Config/
      DesignConfig.lua      # Colors, fonts, spacing, rarity visuals
      Streamers.lua         # All 24 streamers with rarity
      Rarities.lua          # Rarity tiers, weights, colors
      SlotsConfig.lua       # Slots unlocked per rebirth
      Economy.lua           # Spin cost, rebirth cost, sell prices
  server/                   # -> ServerScriptService
    init.server.lua         # Server entry point
    services/
      PlayerData.lua        # DataStore persistence
      SpinService.lua       # Spin RNG + server luck
      EconomyService.lua    # Cash, selling, passive income
      RebirthService.lua    # Rebirth logic
      StoreService.lua      # Robux purchases (ProcessReceipt)
      WorldBuilder.lua      # Generates hub, stalls, lanes, pads
  client/                   # -> StarterPlayerScripts
    init.client.lua         # Client entry point
    controllers/
      UIHelper.lua          # Shared UI utilities + animations
      TopNavController.lua  # Top nav (SHOPS, PLOT, SPIN)
      LeftSideNavController.lua
      RightSideNavController.lua
      HUDController.lua     # Cash, rebirth, spin credits display
      StoreController.lua   # Store popup modal
      SpinController.lua    # Spin wheel + VFX
      SlotPadController.lua # Plot pad visuals
  gui/                      # -> StarterGui (placeholder)
```

## Setup

### Prerequisites

- [Rojo](https://rojo.space/) v7+ installed
- Roblox Studio with the Rojo plugin

### Steps

1. **Clone the repo**
   ```bash
   git clone <repo-url>
   cd SPINTHESTREAMER
   ```

2. **Start the Rojo dev server**
   ```bash
   rojo serve
   ```

3. **Connect from Roblox Studio**
   - Open a new Baseplate place in Roblox Studio
   - Click the Rojo plugin button -> Connect
   - The project tree will sync automatically

4. **Play-test**
   - Hit Play in Studio
   - The server builds the world (hub, stalls, lanes)
   - The client renders all UI (top nav, side navs, HUD, spin wheel, store)

## Game Loop

1. Player earns cash passively (or from selling duplicate streamers)
2. Player spends cash to **SPIN** the wheel
3. Server rolls a random streamer based on weighted rarity
4. Client plays spin animation + rarity-based VFX (glow, shake, flash)
5. Streamer is added to collection and auto-equipped
6. Player can **Rebirth** (reset cash, keep collection, unlock more slots)
7. Robux products: Server Luck, Spin Packs, 2x Cash, Premium Slot

## Rarity Tiers

| Tier      | Weight | Color   |
|-----------|--------|---------|
| Common    | 60     | Grey    |
| Rare      | 25     | Blue    |
| Epic      | 10     | Purple  |
| Legendary | 4      | Gold    |
| Mythic    | 1      | Red     |

Mythic pulls trigger a **server-wide alert** so all players see the notification.

## Customization

- **Add streamers**: Edit `src/shared/Config/Streamers.lua`
- **Tune economy**: Edit `src/shared/Config/Economy.lua`
- **Change visuals**: Edit `src/shared/Config/DesignConfig.lua`
- **Add Robux product IDs**: Set real IDs in `Economy.Products`

## What's Not Included (Yet)

- Collection / Index UI popup
- Friends, Rewards, Quests, Settings panels
- Trading system
- Sound asset IDs (placeholders only)
- Streamer models (use placeholder rigs in Studio)

## Design Principles

- Bright, saturated, cartoony (no realism)
- Large buttons, clear labels, mobile-friendly
- Fast, satisfying, addictive
- Minimal text, strong color contrast
- Visual feedback on every interaction
