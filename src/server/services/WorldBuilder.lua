--[[
	WorldBuilder.lua
	Bright minty-green rectangular map with a single wide dark-purple
	conveyor strip running down the center, green chevron arrows,
	purple glow entrance, stalls at one end, and palm trees.
	Matches the reference RNG game aesthetic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)

local WorldBuilder = {}

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.CanCollide ~= false
	p.Size = props.Size or Vector3.new(4, 1, 4)
	p.Position = props.Position or Vector3.new(0, 0, 0)
	p.Color = props.Color or Color3.fromRGB(200, 200, 200)
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Name = props.Name or "Part"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Transparency then p.Transparency = props.Transparency end
	if props.Reflectance then p.Reflectance = props.Reflectance end
	if props.CFrame then p.CFrame = props.CFrame end
	p.Parent = props.Parent or Workspace
	return p
end

local function billboard(parent, text, textColor, bgColor, offset)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(8, 0, 2, 0)
	bb.StudsOffset = offset or Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = false
	bb.Parent = parent
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = bgColor and 0.3 or 1
	lbl.BackgroundColor3 = bgColor or Color3.new(0, 0, 0)
	lbl.TextColor3 = textColor or DesignConfig.Colors.White
	lbl.Font = DesignConfig.Fonts.Accent
	lbl.TextScaled = true
	lbl.Text = text
	lbl.Parent = bb
	if bgColor then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.2, 0)
		c.Parent = lbl
	end
	return bb
end

-------------------------------------------------
-- FORCE BRIGHT DAYTIME
-------------------------------------------------

local function setupLighting()
	Lighting.Brightness = 3
	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 0
	Lighting.Ambient = Color3.fromRGB(140, 140, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 140)
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	Lighting.ColorShift_Top = Color3.new(0, 0, 0)
	Lighting.FogEnd = 100000
	Lighting.FogStart = 0
	Lighting.FogColor = Color3.fromRGB(192, 220, 255)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") or child:IsA("BloomEffect")
			or child:IsA("ColorCorrectionEffect") or child:IsA("BlurEffect") then
			child:Destroy()
		end
	end

	local atm = Instance.new("Atmosphere")
	atm.Density = 0.3
	atm.Offset = 0
	atm.Color = Color3.fromRGB(200, 225, 255)
	atm.Decay = Color3.fromRGB(100, 140, 200)
	atm.Glare = 0
	atm.Haze = 0
	atm.Parent = Lighting
end

-------------------------------------------------
-- BASEPLATE
-------------------------------------------------

local function buildBaseplate()
	local w, l = DesignConfig.MapWidth, DesignConfig.MapLength
	local cz = l / 2 - 150

	part({
		Name = "Baseplate",
		Size = Vector3.new(w, 1, l),
		Position = Vector3.new(0, 0, cz),
		Color = DesignConfig.Colors.Baseplate,
	})

	part({
		Name = "Water",
		Size = Vector3.new(w * 3, 0.5, l * 3),
		Position = Vector3.new(0, -0.5, cz),
		Color = DesignConfig.Colors.Water,
		CanCollide = false,
		Transparency = 0.25,
	})
end

-------------------------------------------------
-- HUB & STALLS
-------------------------------------------------

local function buildStall(cfg, pos, parent)
	local m = Instance.new("Model")
	m.Name = "Stall_" .. cfg.name

	part({ Name = "Counter", Size = Vector3.new(12, 3, 5), Position = pos + Vector3.new(0,1.5,0),
		Color = Color3.fromRGB(140,100,60), Parent = m })
	part({ Name = "Top", Size = Vector3.new(12.4, 0.4, 5.4), Position = pos + Vector3.new(0,3.2,0),
		Color = cfg.color, Parent = m })
	local awning = part({ Name = "Awning", Size = Vector3.new(14, 0.5, 7), Position = pos + Vector3.new(0,8,-0.5),
		Color = cfg.color, Parent = m })
	part({ Name = "Stripe", Size = Vector3.new(14, 0.6, 1), Position = pos + Vector3.new(0,7.9,2.5),
		Color = DesignConfig.Colors.White, Parent = m })
	for _, x in ipairs({-6, 6}) do
		part({ Name = "Pole", Size = Vector3.new(0.6,8,0.6), Position = pos + Vector3.new(x,4,2.5),
			Color = Color3.fromRGB(220,220,220), Parent = m })
	end
	part({ Name = "NPC", Size = Vector3.new(2,3,1.5), Position = pos + Vector3.new(0,4.5,-1),
		Color = cfg.color, Parent = m })
	part({ Name = "Head", Size = Vector3.new(1.5,1.5,1.5), Position = pos + Vector3.new(0,6.5,-1),
		Color = Color3.fromRGB(255,205,148), Parent = m })
	billboard(awning, cfg.name, DesignConfig.Colors.White, cfg.color, Vector3.new(0,3,0))

	m.Parent = parent or Workspace
	return m
end

local function buildHub()
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = Workspace

	local stalls = DesignConfig.Stalls
	local sp = DesignConfig.StallSpacing
	local ctr = DesignConfig.HubCenter
	local tw = (#stalls - 1) * sp
	local sx = ctr.X - tw / 2

	for i, s in ipairs(stalls) do
		buildStall(s, Vector3.new(sx + (i-1)*sp, ctr.Y, ctr.Z), hub)
	end

	part({ Name = "HubFloor", Size = Vector3.new(tw + 40, 0.2, 30),
		Position = ctr + Vector3.new(0, 0.1, 0),
		Color = Color3.fromRGB(140, 215, 170), Parent = hub })
end

-------------------------------------------------
-- SINGLE WIDE CONVEYOR with green chevron arrows
-------------------------------------------------

local function buildConveyor()
	local folder = Instance.new("Folder")
	folder.Name = "Conveyors"
	folder.Parent = Workspace

	local cfg = DesignConfig.Conveyor
	local w = cfg.Width
	local startZ = cfg.StartZ
	local endZ = cfg.EndZ
	local length = endZ - startZ
	local centerZ = startZ + length / 2
	local halfW = w / 2

	-- Main dark conveyor surface
	local strip = part({
		Name = "ConveyorStrip_1",
		Size = Vector3.new(w, 0.3, length),
		Position = Vector3.new(0, 0.55, centerZ),
		Color = DesignConfig.Colors.ConveyorBase,
		Reflectance = 0.03,
		Parent = folder,
	})

	-- Purple underglow
	local glow = Instance.new("PointLight")
	glow.Color = DesignConfig.Colors.ConveyorGlow
	glow.Brightness = 0.5
	glow.Range = 20
	glow.Parent = strip

	-- GREEN CHEVRON ARROWS (V-shaped, like the reference)
	for z = startZ + 5, endZ - 10, cfg.ArrowSpacing do
		-- Center bar of the chevron
		part({
			Name = "ChevronBar",
			Size = Vector3.new(w * 0.6, 0.1, 1.2),
			Position = Vector3.new(0, 0.72, z),
			Color = DesignConfig.Colors.ConveyorArrow,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = folder,
		})

		-- Left wing of chevron (angled)
		local leftWing = part({
			Name = "ChevronL",
			Size = Vector3.new(w * 0.35, 0.1, 1.2),
			Color = DesignConfig.Colors.ConveyorArrow,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = folder,
		})
		leftWing.CFrame = CFrame.new(Vector3.new(-w * 0.18, 0.72, z + 2.5))
			* CFrame.Angles(0, math.rad(35), 0)

		-- Right wing of chevron (angled)
		local rightWing = part({
			Name = "ChevronR",
			Size = Vector3.new(w * 0.35, 0.1, 1.2),
			Color = DesignConfig.Colors.ConveyorArrow,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = folder,
		})
		rightWing.CFrame = CFrame.new(Vector3.new(w * 0.18, 0.72, z + 2.5))
			* CFrame.Angles(0, math.rad(-35), 0)
	end

	-- Side accent lines (thin neon)
	for _, side in ipairs({-1, 1}) do
		part({
			Name = "SideLine",
			Size = Vector3.new(0.5, 0.15, length),
			Position = Vector3.new(side * (halfW - 0.5), 0.72, centerZ),
			Color = DesignConfig.Colors.ConveyorStripe,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = folder,
		})
	end

	-- Side rails
	for _, side in ipairs({-1, 1}) do
		part({
			Name = "Rail",
			Size = Vector3.new(cfg.RailWidth, cfg.RailHeight, length + 6),
			Position = Vector3.new(side * (halfW + cfg.RailWidth/2 + 0.5), cfg.RailHeight/2 + 0.5, centerZ),
			Color = DesignConfig.Colors.ConveyorBorder,
			Parent = folder,
		})
	end

	-- PURPLE GLOW ENTRANCE (like reference — glowing purple arch)
	local glowEntry = part({
		Name = "GlowEntry",
		Size = Vector3.new(w + 8, 10, 4),
		Position = Vector3.new(0, 5.5, startZ - 2),
		Color = DesignConfig.Colors.ConveyorGlow,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CanCollide = false,
		Parent = folder,
	})
	local entryLight = Instance.new("PointLight")
	entryLight.Color = DesignConfig.Colors.ConveyorGlow
	entryLight.Brightness = 3
	entryLight.Range = 40
	entryLight.Parent = glowEntry

	billboard(glowEntry, "SPEED BOOST", DesignConfig.Colors.ConveyorArrow, nil, Vector3.new(0, 3, 0))

	-- PUSH LOGIC
	strip.Touched:Connect(function(hit)
		local char = hit.Parent
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not hum or not root then return end
		if root:FindFirstChild("ConveyorPush") then return end

		local bv = Instance.new("BodyVelocity")
		bv.Name = "ConveyorPush"
		bv.Velocity = Vector3.new(0, 0, cfg.Speed)
		bv.MaxForce = Vector3.new(0, 0, 60000)
		bv.P = 1250
		bv.Parent = root
	end)

	strip.TouchEnded:Connect(function(hit)
		local char = hit.Parent
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		task.delay(0.15, function()
			local still = false
			for _, p in ipairs(root:GetTouchingParts()) do
				if p.Name:match("^ConveyorStrip") then still = true; break end
			end
			if not still then
				local push = root:FindFirstChild("ConveyorPush")
				if push then push:Destroy() end
			end
		end)
	end)
end

-------------------------------------------------
-- PALM TREES (taller, more tropical like reference)
-------------------------------------------------

local function buildTree(pos, parent)
	local m = Instance.new("Model")
	m.Name = "PalmTree"

	-- Trunk (slightly curved look with 2 segments)
	part({ Name = "Trunk1", Size = Vector3.new(2, 10, 2),
		Position = pos + Vector3.new(0, 5, 0),
		Color = Color3.fromRGB(150, 105, 50), Parent = m })
	part({ Name = "Trunk2", Size = Vector3.new(1.8, 8, 1.8),
		Position = pos + Vector3.new(0.5, 13, 0.3),
		Color = Color3.fromRGB(160, 115, 55), Parent = m })

	-- Leaves radiating outward
	local lc = Color3.fromRGB(55, 185, 65)
	local leaves = {
		{Vector3.new(5, 16, 0), Vector3.new(7, 0.5, 3)},
		{Vector3.new(-5, 16, 0), Vector3.new(7, 0.5, 3)},
		{Vector3.new(0, 16, 5), Vector3.new(3, 0.5, 7)},
		{Vector3.new(0, 16, -5), Vector3.new(3, 0.5, 7)},
		{Vector3.new(4, 16.5, 4), Vector3.new(6, 0.5, 3)},
		{Vector3.new(-4, 16.5, -4), Vector3.new(6, 0.5, 3)},
		{Vector3.new(4, 16.5, -4), Vector3.new(6, 0.5, 3)},
		{Vector3.new(-4, 16.5, 4), Vector3.new(6, 0.5, 3)},
	}
	for i, l in ipairs(leaves) do
		part({ Name = "Leaf"..i, Size = l[2], Position = pos + l[1],
			Color = lc, Parent = m })
	end
	-- Top ball
	part({ Name = "Top", Size = Vector3.new(3, 2.5, 3),
		Position = pos + Vector3.new(0.5, 17, 0.3),
		Color = Color3.fromRGB(45, 165, 55), Parent = m })

	m.Parent = parent
	return m
end

local function buildDecorations()
	local deco = Instance.new("Folder")
	deco.Name = "Decorations"
	deco.Parent = Workspace

	local halfW = DesignConfig.MapWidth / 2 - 20

	-- Trees along map edges
	for z = -60, 850, 80 do
		buildTree(Vector3.new(-halfW, 0, z), deco)
		buildTree(Vector3.new(halfW, 0, z), deco)
	end

	-- Trees between bases and edge
	for z = 50, 800, 150 do
		buildTree(Vector3.new(-halfW + 30, 0, z + 30), deco)
		buildTree(Vector3.new(halfW - 30, 0, z + 30), deco)
	end

	-- Trees near hub
	buildTree(Vector3.new(-70, 0, -120), deco)
	buildTree(Vector3.new(70, 0, -120), deco)
	buildTree(Vector3.new(-40, 0, -40), deco)
	buildTree(Vector3.new(40, 0, -40), deco)
end

-------------------------------------------------
-- SPAWN
-------------------------------------------------

local function buildSpawn()
	local sp = Instance.new("SpawnLocation")
	sp.Name = "SpawnPoint"
	sp.Anchored = true
	sp.Size = Vector3.new(10, 1, 10)
	sp.Position = Vector3.new(0, 0.5, -40)
	sp.Color = Color3.fromRGB(140, 230, 175)
	sp.Material = Enum.Material.SmoothPlastic
	sp.TopSurface = Enum.SurfaceType.Smooth
	sp.BottomSurface = Enum.SurfaceType.Smooth
	sp.Parent = Workspace
end

-------------------------------------------------
-- PATHS
-------------------------------------------------

local function buildPaths()
	local pf = Instance.new("Folder")
	pf.Name = "Paths"
	pf.Parent = Workspace

	part({ Name = "PathToHub", Size = Vector3.new(10, 0.15, 40),
		Position = Vector3.new(0, 0.1, -60),
		Color = DesignConfig.Colors.PathColor, Parent = pf })
	part({ Name = "PathToConv", Size = Vector3.new(10, 0.15, 50),
		Position = Vector3.new(0, 0.1, -15),
		Color = DesignConfig.Colors.PathColor, Parent = pf })
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function WorldBuilder.Build()
	for _, name in ipairs({
		"Baseplate", "Water", "Hub", "Decorations",
		"SpawnPoint", "Paths", "PlayerBases", "Conveyors",
	}) do
		local e = Workspace:FindFirstChild(name)
		if e then e:Destroy() end
	end

	setupLighting()
	buildBaseplate()
	buildHub()
	buildConveyor()
	buildDecorations()
	buildSpawn()
	buildPaths()

	print("[WorldBuilder] Map built — " ..
		DesignConfig.MapWidth .. "x" .. DesignConfig.MapLength ..
		" with single conveyor & 16 base slots")
end

return WorldBuilder
