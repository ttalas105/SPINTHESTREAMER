--[[
	DesignConfig.lua
	Central design system for Spin the Streamer.
	All UI colors, fonts, spacing, and rarity visuals live here.
]]

local DesignConfig = {}

-------------------------------------------------
-- COLOR PALETTE
-------------------------------------------------
DesignConfig.Colors = {
	-- Primary UI
	Background       = Color3.fromRGB(30, 30, 45),      -- dark panel bg
	BackgroundLight  = Color3.fromRGB(45, 45, 65),      -- lighter panel
	Accent           = Color3.fromRGB(0, 200, 100),     -- neon green (buy/spin)
	AccentAlt        = Color3.fromRGB(80, 120, 255),    -- blue accent
	Danger           = Color3.fromRGB(230, 50, 50),     -- red (close, warning)
	White            = Color3.fromRGB(255, 255, 255),
	TextPrimary      = Color3.fromRGB(255, 255, 255),
	TextSecondary    = Color3.fromRGB(180, 180, 200),
	TextMuted        = Color3.fromRGB(120, 120, 140),

	-- Stall awning colors
	StallBlue        = Color3.fromRGB(60, 130, 255),
	StallRed         = Color3.fromRGB(230, 60, 60),
	StallPurple      = Color3.fromRGB(150, 60, 230),
	StallGreen       = Color3.fromRGB(50, 200, 80),
	StallYellow      = Color3.fromRGB(255, 210, 50),

	-- World
	Baseplate        = Color3.fromRGB(90, 200, 90),     -- bright green grass
	Water            = Color3.fromRGB(60, 160, 255),
	PadUnlocked      = Color3.fromRGB(100, 255, 150),
	PadLocked        = Color3.fromRGB(100, 100, 100),
	PadGlow          = Color3.fromRGB(150, 255, 200),

	-- Button states
	ButtonIdle       = Color3.fromRGB(60, 60, 90),
	ButtonHover      = Color3.fromRGB(80, 80, 120),
	ButtonActive     = Color3.fromRGB(0, 200, 100),

	-- Nav
	NavBackground    = Color3.fromRGB(35, 35, 55),
	NavActive        = Color3.fromRGB(0, 200, 100),
	NavInactive      = Color3.fromRGB(60, 60, 90),
	NotificationBadge = Color3.fromRGB(230, 50, 50),
}

-------------------------------------------------
-- RARITY VISUALS
-------------------------------------------------
DesignConfig.RarityColors = {
	Common    = Color3.fromRGB(170, 170, 170),  -- grey
	Rare      = Color3.fromRGB(60, 130, 255),   -- blue
	Epic      = Color3.fromRGB(170, 60, 255),   -- purple
	Legendary = Color3.fromRGB(255, 200, 40),   -- gold
	Mythic    = Color3.fromRGB(255, 50, 50),    -- red / rainbow
}

DesignConfig.RarityGlow = {
	Common    = 0,
	Rare      = 0.3,
	Epic      = 0.6,
	Legendary = 0.8,
	Mythic    = 1.0,
}

-- Screen shake intensity per rarity (0 = none)
DesignConfig.RarityShake = {
	Common    = 0,
	Rare      = 0,
	Epic      = 3,
	Legendary = 6,
	Mythic    = 12,
}

-------------------------------------------------
-- TYPOGRAPHY
-------------------------------------------------
DesignConfig.Fonts = {
	Primary   = Enum.Font.GothamBold,
	Secondary = Enum.Font.Gotham,
	Accent    = Enum.Font.FredokaOne,
}

DesignConfig.FontSizes = {
	Title    = 36,
	Header   = 28,
	Body     = 22,
	Caption  = 18,
	Small    = 14,
}

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
-- UI SIZES (Scale-based for mobile)
-------------------------------------------------
DesignConfig.Sizes = {
	TopNavButtonWidth  = UDim2.new(0.12, 0, 0.05, 0),
	TopNavHeight       = UDim2.new(1, 0, 0.06, 0),
	SideButtonSize     = UDim2.new(0, 60, 0, 60),
	SideButtonSpacing  = UDim.new(0, 8),
	ModalSize          = UDim2.new(0.7, 0, 0.75, 0),
	SpinWheelSize      = UDim2.new(0.5, 0, 0.5, 0),
}

-------------------------------------------------
-- STALL CONFIG (world layout)
-------------------------------------------------
DesignConfig.Stalls = {
	{ name = "Buy",      color = DesignConfig.Colors.StallBlue,   icon = "rbxassetid://0" },
	{ name = "Sell",     color = DesignConfig.Colors.StallRed,    icon = "rbxassetid://0" },
	{ name = "Potions",  color = DesignConfig.Colors.StallPurple, icon = "rbxassetid://0" },
	{ name = "Upgrades", color = DesignConfig.Colors.StallGreen,  icon = "rbxassetid://0" },
}

DesignConfig.StallSpacing = 20 -- studs between stalls
DesignConfig.HubCenter = Vector3.new(0, 0.5, -40) -- world position of hub center

-------------------------------------------------
-- PLOT / LANE LAYOUT
-------------------------------------------------
DesignConfig.Plot = {
	LaneCount      = 3,
	PadsPerLane    = 6,
	PadSize        = Vector3.new(8, 1, 8),
	PadSpacing     = 12,  -- studs between pads
	LaneSpacing    = 16,  -- studs between lanes
	LaneStart      = Vector3.new(0, 0.5, 20), -- where lanes begin
}

return DesignConfig
