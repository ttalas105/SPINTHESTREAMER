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
-- STALLS (hub near spawn)
-------------------------------------------------
DesignConfig.Stalls = {
	{ name = "SPIN",     color = DesignConfig.Colors.StallPurple, icon = "rbxassetid://0" },
	{ name = "SELL",     color = DesignConfig.Colors.StallRed,    icon = "rbxassetid://0" },
	{ name = "REBIRTH",  color = DesignConfig.Colors.StallYellow, icon = "rbxassetid://0" },
	{ name = "UPGRADES", color = DesignConfig.Colors.StallGreen,  icon = "rbxassetid://0" },
}
DesignConfig.StallSpacing = 22
DesignConfig.HubCenter = Vector3.new(0, 0.5, -80)

-------------------------------------------------
-- CONVEYOR — SINGLE WIDE STRIP
-------------------------------------------------
DesignConfig.Conveyor = {
	Width        = 34,          -- single wide strip
	Speed        = 55,
	StartZ       = 20,
	EndZ         = 880,
	ArrowSpacing = 22,          -- green chevrons every N studs
	RailHeight   = 1.2,
	RailWidth    = 1.5,
}

-------------------------------------------------
-- PER-PLAYER BASE — 1 column per side, 8 per side
-------------------------------------------------
DesignConfig.Base = {
	PadRows     = 4,
	PadCols     = 5,
	PadSize     = Vector3.new(6, 0.8, 6),
	PadSpacing  = 9,
	FloorPadding = 10,

	BorderHeight   = 1.5,
	BorderThickness = 1.2,

	-- 2 columns: left side and right side of conveyor
	-- X positions calculated from conveyor width + gap
	ColumnGap   = 12,           -- gap between conveyor edge and base edge
	RowStartZ   = 40,
	RowSpacing  = 105,          -- Z spacing between base centers
	BasesPerSide = 8,           -- 8 on left, 8 on right = 16 max

	SpawnOffset = Vector3.new(0, 3, -10),
}

-- Calculate base floor size and column X positions
do
	local b = DesignConfig.Base
	local gridWidth = (b.PadCols - 1) * b.PadSpacing + b.PadSize.X
	local gridDepth = (b.PadRows - 1) * b.PadSpacing + b.PadSize.Z
	b.FloorWidth = gridWidth + b.FloorPadding * 2
	b.FloorDepth = gridDepth + b.FloorPadding * 2
	b.FloorSize = Vector3.new(b.FloorWidth, 1, b.FloorDepth)

	-- Column X positions: left and right of conveyor
	local convHalf = DesignConfig.Conveyor.Width / 2
	local baseHalf = b.FloorWidth / 2
	b.LeftColumnX  = -(convHalf + b.ColumnGap + baseHalf)
	b.RightColumnX =  (convHalf + b.ColumnGap + baseHalf)
	b.Columns = { b.LeftColumnX, b.RightColumnX }
end

return DesignConfig
