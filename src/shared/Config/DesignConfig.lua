--[[
	DesignConfig.lua
	Central design system for Spin the Streamer.
	Bright minty-green map with a single wide dark-purple conveyor
	and 8 bases on each side — matching the reference RNG game layout.
]]

local DesignConfig = {}

-------------------------------------------------
-- COLOR PALETTE
-------------------------------------------------
DesignConfig.Colors = {
	-- Primary UI
	Background       = Color3.fromRGB(30, 30, 45),
	BackgroundLight  = Color3.fromRGB(45, 45, 65),
	Accent           = Color3.fromRGB(0, 200, 100),
	AccentAlt        = Color3.fromRGB(80, 120, 255),
	Danger           = Color3.fromRGB(230, 50, 50),
	White            = Color3.fromRGB(255, 255, 255),
	TextPrimary      = Color3.fromRGB(255, 255, 255),
	TextSecondary    = Color3.fromRGB(180, 180, 200),
	TextMuted        = Color3.fromRGB(120, 120, 140),

	-- Stall colors
	StallBlue        = Color3.fromRGB(60, 130, 255),
	StallRed         = Color3.fromRGB(230, 60, 60),
	StallPurple      = Color3.fromRGB(150, 60, 230),
	StallGreen       = Color3.fromRGB(50, 200, 80),
	StallYellow      = Color3.fromRGB(255, 210, 50),

	-- World
	Baseplate        = Color3.fromRGB(120, 220, 155),   -- bright mint green
	Water            = Color3.fromRGB(80, 180, 255),
	PathColor        = Color3.fromRGB(105, 205, 145),

	-- Conveyor — single wide dark blue-purple strip
	ConveyorBase     = Color3.fromRGB(30, 30, 80),      -- dark blue-purple
	ConveyorStripe   = Color3.fromRGB(50, 40, 110),     -- side accent
	ConveyorArrow    = Color3.fromRGB(40, 220, 100),    -- bright green chevrons
	ConveyorGlow     = Color3.fromRGB(120, 60, 255),    -- purple glow
	ConveyorBorder   = Color3.fromRGB(40, 35, 90),      -- side rail

	-- Base / Plot — dark gray like reference
	BaseFloor        = Color3.fromRGB(65, 65, 75),      -- dark gray base
	BaseBorder       = Color3.fromRGB(255, 220, 50),    -- yellow border
	PadUnlocked      = Color3.fromRGB(90, 90, 105),     -- lighter gray pad
	PadLocked        = Color3.fromRGB(55, 55, 65),      -- darker locked
	PadGlow          = Color3.fromRGB(150, 255, 200),
	PadStarter       = Color3.fromRGB(255, 220, 80),
	PadPremium       = Color3.fromRGB(255, 100, 100),
	PadMarker        = Color3.fromRGB(50, 200, 80),

	-- Button states
	ButtonIdle       = Color3.fromRGB(60, 60, 90),
	ButtonHover      = Color3.fromRGB(80, 80, 120),
	ButtonActive     = Color3.fromRGB(0, 200, 100),

	-- Nav
	NavBackground    = Color3.fromRGB(35, 35, 55),
	NavActive        = Color3.fromRGB(0, 200, 100),
	NavInactive      = Color3.fromRGB(60, 60, 90),
	NotificationBadge = Color3.fromRGB(230, 50, 50),

	-- Inventory bar
	InventoryBg      = Color3.fromRGB(25, 25, 40),
	InventorySlot    = Color3.fromRGB(50, 50, 70),
	InventorySelected = Color3.fromRGB(255, 220, 50),
}

-------------------------------------------------
-- RARITY VISUALS
-------------------------------------------------
DesignConfig.RarityColors = {
	Common    = Color3.fromRGB(170, 170, 170),
	Rare      = Color3.fromRGB(60, 130, 255),
	Epic      = Color3.fromRGB(170, 60, 255),
	Legendary = Color3.fromRGB(255, 200, 40),
	Mythic    = Color3.fromRGB(255, 50, 50),
}
DesignConfig.RarityGlow = { Common = 0, Rare = 0.3, Epic = 0.6, Legendary = 0.8, Mythic = 1.0 }
DesignConfig.RarityShake = { Common = 0, Rare = 0, Epic = 3, Legendary = 6, Mythic = 12 }

-------------------------------------------------
-- TYPOGRAPHY
-------------------------------------------------
DesignConfig.Fonts = {
	Primary   = Enum.Font.GothamBold,
	Secondary = Enum.Font.Gotham,
	Accent    = Enum.Font.FredokaOne,
}
DesignConfig.FontSizes = { Title = 36, Header = 28, Body = 22, Caption = 18, Small = 14 }

-------------------------------------------------
-- SPACING & LAYOUT
-------------------------------------------------
DesignConfig.Layout = {
	ButtonCorner    = UDim.new(0, 12),
	PanelCorner     = UDim.new(0, 16),
	ModalCorner     = UDim.new(0, 20),
	Padding         = UDim.new(0, 8),
	PaddingLarge    = UDim.new(0, 16),
	StrokeThickness = 2,
}

-------------------------------------------------
-- UI SIZES
-------------------------------------------------
DesignConfig.Sizes = {
	TopNavButtonWidth  = UDim2.new(0.12, 0, 0.05, 0),
	TopNavHeight       = UDim2.new(1, 0, 0.06, 0),
	SideButtonSize     = UDim2.new(0, 60, 0, 60),
	SideButtonSpacing  = UDim.new(0, 8),
	ModalSize          = UDim2.new(0.7, 0, 0.75, 0),
	SpinWheelSize      = UDim2.new(0.5, 0, 0.5, 0),
	InventorySlotSize  = UDim2.new(0, 56, 0, 56),
	InventoryBarHeight = UDim2.new(0, 70, 0, 70),
}

-------------------------------------------------
-- WORLD — RECTANGULAR MAP
-------------------------------------------------
DesignConfig.MapWidth  = 400
DesignConfig.MapLength = 1000

-------------------------------------------------
-- STALLS (open-air market stalls near spawn)
-- Layout: striped canopy, wooden cart, NPC behind counter
-------------------------------------------------
DesignConfig.HubCenter = Vector3.new(0, 0.5, -100)

DesignConfig.Stalls = {
	{
		name      = "Spin",
		color     = Color3.fromRGB(60, 160, 230),   -- blue canopy
		roofColor = Color3.fromRGB(60, 160, 230),
		npc = {
			skinColor   = Color3.fromRGB(255, 220, 185),
			outfitColor = Color3.fromRGB(60, 130, 220),
			pantsColor  = Color3.fromRGB(35, 35, 55),
		},
	},
	{
		name      = "Sell",
		color     = Color3.fromRGB(220, 60, 60),    -- red canopy
		roofColor = Color3.fromRGB(220, 60, 60),
		npc = {
			skinColor   = Color3.fromRGB(245, 210, 175),
			outfitColor = Color3.fromRGB(200, 50, 50),
			pantsColor  = Color3.fromRGB(40, 40, 50),
		},
	},
	{
		name      = "Potions",
		color     = Color3.fromRGB(170, 60, 210),   -- purple canopy
		roofColor = Color3.fromRGB(170, 60, 210),
		npc = {
			skinColor   = Color3.fromRGB(255, 225, 195),
			outfitColor = Color3.fromRGB(150, 50, 190),
			pantsColor  = Color3.fromRGB(40, 30, 50),
		},
	},
	{
		name      = "Upgrades",
		color     = Color3.fromRGB(50, 180, 80),    -- green canopy
		roofColor = Color3.fromRGB(50, 180, 80),
		npc = {
			skinColor   = Color3.fromRGB(250, 215, 180),
			outfitColor = Color3.fromRGB(40, 160, 70),
			pantsColor  = Color3.fromRGB(30, 45, 35),
		},
	},
	{
		name      = "Gems",
		color     = Color3.fromRGB(230, 180, 40),   -- gold canopy
		roofColor = Color3.fromRGB(230, 180, 40),
		npc = {
			skinColor   = Color3.fromRGB(248, 218, 185),
			outfitColor = Color3.fromRGB(210, 170, 30),
			pantsColor  = Color3.fromRGB(50, 45, 30),
		},
	},
}

-------------------------------------------------
-- SPEED PAD (online asset) — TWO STRIPS SIDE BY SIDE
-- One going forward (+Z), one going backward (-Z)
-------------------------------------------------
DesignConfig.SpeedPad = {
	AssetId      = 288415410,
	Speed        = 55,
	StripGap     = 12,          -- X offset from center for each strip
	CenterZ      = 200,         -- center Z of the speed pad area
	Length        = 400,         -- how long the speed pad area is
}

-------------------------------------------------
-- PER-PLAYER BASE (online asset) — 8 BASES TOTAL
-- 4 on each side of the speed pads, entrances facing inward
-------------------------------------------------
DesignConfig.BaseAsset = {
	AssetId      = 112269866373242,
}

DesignConfig.Base = {
	PadRows     = 4,
	PadCols     = 5,
	PadSize     = Vector3.new(6, 0.8, 6),
	PadSpacing  = 9,
	FloorPadding = 10,

	BorderHeight   = 1.5,
	BorderThickness = 1.2,

	BasesPerSide = 4,           -- 4 on left, 4 on right = 8 max
	MaxPlayers   = 8,

	SpawnOffset = Vector3.new(0, 3, -10),
}

-- Pre-calculate 8 base positions:
-- Left side:  4 bases stacked along Z
-- Right side: 4 bases stacked along Z
-- All entrances face the speed pad (center)
DesignConfig.BasePositions = {
	-- Left side (rotation 90 = entrance faces right toward speed pad)
	{ position = Vector3.new(-70, 0.5, 80),   rotation = 90  },  -- Left 1
	{ position = Vector3.new(-70, 0.5, 160),  rotation = 90  },  -- Left 2
	{ position = Vector3.new(-70, 0.5, 240),  rotation = 90  },  -- Left 3
	{ position = Vector3.new(-70, 0.5, 320),  rotation = 90  },  -- Left 4
	-- Right side (rotation -90 = entrance faces left toward speed pad)
	{ position = Vector3.new(70,  0.5, 80),   rotation = -90 },  -- Right 1
	{ position = Vector3.new(70,  0.5, 160),  rotation = -90 },  -- Right 2
	{ position = Vector3.new(70,  0.5, 240),  rotation = -90 },  -- Right 3
	{ position = Vector3.new(70,  0.5, 320),  rotation = -90 },  -- Right 4
}

-- Calculate base floor size (still needed for pad grid)
do
	local b = DesignConfig.Base
	local gridWidth = (b.PadCols - 1) * b.PadSpacing + b.PadSize.X
	local gridDepth = (b.PadRows - 1) * b.PadSpacing + b.PadSize.Z
	b.FloorWidth = gridWidth + b.FloorPadding * 2
	b.FloorDepth = gridDepth + b.FloorPadding * 2
	b.FloorSize = Vector3.new(b.FloorWidth, 1, b.FloorDepth)
end

return DesignConfig
