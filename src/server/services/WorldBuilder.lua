--[[
	WorldBuilder.lua
	Generates the world layout from code: baseplate, hub with stalls,
	plot lanes with pads, and decorative props.
	Everything is data-driven from DesignConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local SlotsConfig = require(ReplicatedStorage.Shared.Config.SlotsConfig)

local WorldBuilder = {}

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function createPart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = props.CanCollide ~= false
	part.Size = props.Size or Vector3.new(4, 1, 4)
	part.Position = props.Position or Vector3.new(0, 0, 0)
	part.Color = props.Color or Color3.fromRGB(200, 200, 200)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Name = props.Name or "Part"
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.Transparency then
		part.Transparency = props.Transparency
	end
	part.Parent = props.Parent or Workspace
	return part
end

local function createBillboard(parent, text, textColor, bgColor, studOffset)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(8, 0, 2, 0)
	billboard.StudsOffset = studOffset or Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = bgColor and 0.3 or 1
	label.BackgroundColor3 = bgColor or Color3.new(0, 0, 0)
	label.TextColor3 = textColor or DesignConfig.Colors.White
	label.Font = DesignConfig.Fonts.Primary
	label.TextScaled = true
	label.Text = text
	label.Parent = billboard

	if bgColor then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = label
	end

	return billboard
end

local function addGlow(part, color, brightness)
	local light = Instance.new("PointLight")
	light.Color = color or DesignConfig.Colors.PadGlow
	light.Brightness = brightness or 1
	light.Range = 12
	light.Parent = part
	return light
end

-------------------------------------------------
-- BASEPLATE
-------------------------------------------------

local function buildBaseplate()
	-- Main ground
	local base = createPart({
		Name = "Baseplate",
		Size = Vector3.new(300, 1, 300),
		Position = Vector3.new(0, 0, 0),
		Color = DesignConfig.Colors.Baseplate,
		Material = Enum.Material.SmoothPlastic,
	})

	-- Water surrounding (visual only)
	local waterSize = 600
	local water = createPart({
		Name = "Water",
		Size = Vector3.new(waterSize, 0.5, waterSize),
		Position = Vector3.new(0, -0.5, 0),
		Color = DesignConfig.Colors.Water,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 0.3,
	})

	return base
end

-------------------------------------------------
-- HUB & STALLS
-------------------------------------------------

local function buildStall(stallConfig, position)
	local model = Instance.new("Model")
	model.Name = "Stall_" .. stallConfig.name

	-- Counter base
	local counter = createPart({
		Name = "Counter",
		Size = Vector3.new(10, 3, 4),
		Position = position + Vector3.new(0, 1.5, 0),
		Color = Color3.fromRGB(60, 50, 40),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	-- Counter top
	createPart({
		Name = "CounterTop",
		Size = Vector3.new(10.4, 0.4, 4.4),
		Position = position + Vector3.new(0, 3.2, 0),
		Color = stallConfig.color,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	-- Awning (striped roof)
	local awning = createPart({
		Name = "Awning",
		Size = Vector3.new(12, 0.5, 6),
		Position = position + Vector3.new(0, 7, -0.5),
		Color = stallConfig.color,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	-- Awning stripe (white stripe accent)
	createPart({
		Name = "AwningStripe",
		Size = Vector3.new(12, 0.6, 1),
		Position = position + Vector3.new(0, 6.9, 2),
		Color = DesignConfig.Colors.White,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	-- Support poles
	for _, xOff in ipairs({ -5, 5 }) do
		createPart({
			Name = "Pole",
			Size = Vector3.new(0.5, 7, 0.5),
			Position = position + Vector3.new(xOff, 3.5, 2),
			Color = Color3.fromRGB(200, 200, 200),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end

	-- NPC placeholder (simple block figure behind counter)
	local npcBody = createPart({
		Name = "NPC_Body",
		Size = Vector3.new(2, 3, 1.5),
		Position = position + Vector3.new(0, 4.5, -1),
		Color = stallConfig.color,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	local npcHead = createPart({
		Name = "NPC_Head",
		Size = Vector3.new(1.5, 1.5, 1.5),
		Position = position + Vector3.new(0, 6.5, -1),
		Color = Color3.fromRGB(255, 205, 148),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	-- Floating label above stall
	createBillboard(awning, stallConfig.name, DesignConfig.Colors.White, stallConfig.color, Vector3.new(0, 3, 0))

	model.Parent = Workspace
	return model
end

local function buildHub()
	local hubFolder = Instance.new("Folder")
	hubFolder.Name = "Hub"
	hubFolder.Parent = Workspace

	local stalls = DesignConfig.Stalls
	local spacing = DesignConfig.StallSpacing
	local center = DesignConfig.HubCenter
	local totalWidth = (#stalls - 1) * spacing
	local startX = center.X - totalWidth / 2

	for i, stallConfig in ipairs(stalls) do
		local xPos = startX + (i - 1) * spacing
		local pos = Vector3.new(xPos, center.Y, center.Z)
		local stall = buildStall(stallConfig, pos)
		stall.Parent = hubFolder
	end

	-- Hub floor (slightly different from baseplate for visual distinction)
	createPart({
		Name = "HubFloor",
		Size = Vector3.new(totalWidth + 30, 0.2, 20),
		Position = center + Vector3.new(0, 0.1, 0),
		Color = Color3.fromRGB(220, 220, 230),
		Material = Enum.Material.SmoothPlastic,
		Parent = hubFolder,
	})

	return hubFolder
end

-------------------------------------------------
-- PLOT LANES & PADS
-------------------------------------------------

local function buildPad(position, slotIndex, isUnlocked, lockReason)
	local padSize = DesignConfig.Plot.PadSize
	local color = isUnlocked and DesignConfig.Colors.PadUnlocked or DesignConfig.Colors.PadLocked

	local pad = createPart({
		Name = "Pad_" .. slotIndex,
		Size = padSize,
		Position = position,
		Color = color,
		Material = isUnlocked and Enum.Material.Neon or Enum.Material.SmoothPlastic,
	})

	-- Pad border
	local border = createPart({
		Name = "PadBorder",
		Size = Vector3.new(padSize.X + 0.5, padSize.Y - 0.2, padSize.Z + 0.5),
		Position = position - Vector3.new(0, 0.1, 0),
		Color = isUnlocked and DesignConfig.Colors.PadGlow or Color3.fromRGB(60, 60, 60),
		Material = Enum.Material.SmoothPlastic,
	})
	border.Parent = pad

	if isUnlocked then
		addGlow(pad, DesignConfig.Colors.PadGlow, 0.8)
	else
		-- Locked text
		local lockText = lockReason or ("LOCKED (Rebirth ?)")
		createBillboard(pad, lockText, Color3.fromRGB(255, 100, 100), Color3.fromRGB(40, 40, 40), Vector3.new(0, 3, 0))
	end

	pad.Parent = Workspace
	return pad
end

local function buildPlotLanes()
	local lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "PlotLanes"
	lanesFolder.Parent = Workspace

	local plotCfg = DesignConfig.Plot
	local laneStart = plotCfg.LaneStart
	local totalLaneWidth = (plotCfg.LaneCount - 1) * plotCfg.LaneSpacing
	local startX = laneStart.X - totalLaneWidth / 2

	local padIndex = 1
	for lane = 1, plotCfg.LaneCount do
		local laneFolder = Instance.new("Folder")
		laneFolder.Name = "Lane_" .. lane
		laneFolder.Parent = lanesFolder

		local laneX = startX + (lane - 1) * plotCfg.LaneSpacing

		for padNum = 1, plotCfg.PadsPerLane do
			local zPos = laneStart.Z + (padNum - 1) * plotCfg.PadSpacing
			local pos = Vector3.new(laneX, laneStart.Y, zPos)

			-- Determine lock state (first pad always unlocked, rest depend on rebirth)
			local isUnlocked = padIndex == 1
			local lockReason = nil
			if not isUnlocked then
				-- Figure out which rebirth unlocks this pad
				local rebirthNeeded = 0
				for reqRebirth, slotCount in pairs(SlotsConfig.SlotsByRebirth) do
					if slotCount >= padIndex and (rebirthNeeded == 0 or reqRebirth < rebirthNeeded) then
						rebirthNeeded = reqRebirth
					end
				end
				if rebirthNeeded > 0 then
					lockReason = "LOCKED (Rebirth " .. rebirthNeeded .. ")"
				elseif padIndex == SlotsConfig.MaxRebirthSlots + 1 then
					lockReason = "Premium Slot"
				else
					lockReason = "LOCKED"
				end
			end

			local pad = buildPad(pos, padIndex, isUnlocked, lockReason)
			pad.Parent = laneFolder
			padIndex = padIndex + 1
		end
	end

	return lanesFolder
end

-------------------------------------------------
-- DECORATIVE PROPS
-------------------------------------------------

local function buildPalmTree(position)
	local model = Instance.new("Model")
	model.Name = "PalmTree"

	-- Trunk
	createPart({
		Name = "Trunk",
		Size = Vector3.new(1.5, 12, 1.5),
		Position = position + Vector3.new(0, 6, 0),
		Color = Color3.fromRGB(139, 90, 43),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	-- Leaves (simple blocks radiating outward)
	local leafColor = Color3.fromRGB(50, 180, 50)
	local leafPositions = {
		Vector3.new(3, 11.5, 0),
		Vector3.new(-3, 11.5, 0),
		Vector3.new(0, 11.5, 3),
		Vector3.new(0, 11.5, -3),
		Vector3.new(2, 12, 2),
		Vector3.new(-2, 12, -2),
	}

	for i, offset in ipairs(leafPositions) do
		createPart({
			Name = "Leaf_" .. i,
			Size = Vector3.new(4, 0.5, 2),
			Position = position + offset,
			Color = leafColor,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end

	model.Parent = Workspace
	return model
end

local function buildDecorations()
	local decoFolder = Instance.new("Folder")
	decoFolder.Name = "Decorations"
	decoFolder.Parent = Workspace

	-- Place palm trees around the edges
	local treePositions = {
		Vector3.new(-60, 0, -60),
		Vector3.new(60, 0, -60),
		Vector3.new(-60, 0, 60),
		Vector3.new(60, 0, 60),
		Vector3.new(-40, 0, -20),
		Vector3.new(40, 0, -20),
		Vector3.new(-80, 0, 0),
		Vector3.new(80, 0, 0),
	}

	for _, pos in ipairs(treePositions) do
		local tree = buildPalmTree(pos)
		tree.Parent = decoFolder
	end

	return decoFolder
end

-------------------------------------------------
-- SPAWN POINT
-------------------------------------------------

local function buildSpawn()
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnPoint"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(0, 0.5, 0)
	spawn.Color = DesignConfig.Colors.AccentAlt
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Parent = Workspace
	return spawn
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function WorldBuilder.Build()
	-- Clear any existing generated world
	for _, name in ipairs({ "Baseplate", "Water", "Hub", "PlotLanes", "Decorations", "SpawnPoint" }) do
		local existing = Workspace:FindFirstChild(name)
		if existing then existing:Destroy() end
	end

	buildBaseplate()
	buildHub()
	buildPlotLanes()
	buildDecorations()
	buildSpawn()

	print("[WorldBuilder] World built successfully!")
end

return WorldBuilder
