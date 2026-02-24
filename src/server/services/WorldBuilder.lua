--[[
	WorldBuilder.lua
	Builds the game world:
	  - Bright minty-green rectangular map
	  - Shop stalls from online asset with custom NPCs
	  - Speed pads from online asset (forward + backward)
	  - 4 player bases from online asset (2 per side)
	  - Palm trees and decorations
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local InsertService = game:GetService("InsertService")
local TweenService = game:GetService("TweenService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)

local WorldBuilder = {}

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function p(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = props.CanCollide ~= false
	part.Size = props.Size or Vector3.new(4, 1, 4)
	part.Color = props.Color or Color3.fromRGB(200, 200, 200)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Name = props.Name or "Part"
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.Transparency then part.Transparency = props.Transparency end
	if props.Reflectance then part.Reflectance = props.Reflectance end
	if props.CFrame then
		part.CFrame = props.CFrame
	elseif props.Position then
		part.Position = props.Position
	end
	if props.Shape then part.Shape = props.Shape end
	part.Parent = props.Parent or Workspace
	return part
end

local function billboard(parent, text, textColor, bgColor, size, offset, opts)
	opts = opts or {}
	local bb = Instance.new("BillboardGui")
	bb.Size = size or UDim2.new(8, 0, 2, 0)
	bb.StudsOffset = offset or Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = false
	bb.Parent = parent
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = bgColor and 0.15 or 1
	lbl.BackgroundColor3 = bgColor or Color3.new(0, 0, 0)
	lbl.TextColor3 = textColor or DesignConfig.Colors.White
	lbl.Font = opts.font or DesignConfig.Fonts.Accent
	lbl.TextScaled = true
	lbl.Text = text
	lbl.Parent = bb
	if bgColor then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.2, 0)
		c.Parent = lbl
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = opts.strokeThickness or 2
	stroke.Color = opts.strokeColor or Color3.fromRGB(0, 0, 0)
	stroke.Parent = lbl
	return bb
end

local function getModelBounds(model)
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local pos = part.Position
			local half = part.Size / 2
			min = Vector3.new(
				math.min(min.X, pos.X - half.X),
				math.min(min.Y, pos.Y - half.Y),
				math.min(min.Z, pos.Z - half.Z))
			max = Vector3.new(
				math.max(max.X, pos.X + half.X),
				math.max(max.Y, pos.Y + half.Y),
				math.max(max.Z, pos.Z + half.Z))
		end
	end
	return min, max
end

-- Load an asset, strip scripts, anchor parts, return the first Model child with parts
local function loadAndPrepAsset(assetId, label)
	local ok, asset = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not asset then
		-- Expected in Studio if place doesn't own the asset; fallback builds still work
		print("[WorldBuilder] Could not load " .. label .. " (use fallback); " .. tostring(asset or "error"))
		return nil
	end
	print("[WorldBuilder] Loaded " .. label)

	-- Strip scripts
	for _, obj in ipairs(asset:GetDescendants()) do
		if obj:IsA("BaseScript") or obj:IsA("ModuleScript") then obj:Destroy() end
	end
	-- Anchor all parts
	for _, part in ipairs(asset:GetDescendants()) do
		if part:IsA("BasePart") then part.Anchored = true end
	end
	-- Freeze humanoids
	for _, hum in ipairs(asset:GetDescendants()) do
		if hum:IsA("Humanoid") then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	return asset
end

-- Move a model so its bottom-center is at targetPos with optional Y rotation
local function positionModel(model, targetPos, yRotDeg)
	yRotDeg = yRotDeg or 0
	local bmin, bmax = getModelBounds(model)
	local center = Vector3.new((bmin.X+bmax.X)/2, bmin.Y, (bmin.Z+bmax.Z)/2)
	local delta = CFrame.new(targetPos) * CFrame.Angles(0, math.rad(yRotDeg), 0) * CFrame.new(center):Inverse()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then part.CFrame = delta * part.CFrame end
	end
end

-------------------------------------------------
-- LIGHTING
-------------------------------------------------

local function setupLighting()
	Lighting.Brightness = 2
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 41.733
	Lighting.Ambient = Color3.new(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	Lighting.ColorShift_Top = Color3.new(0, 0, 0)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
end

-------------------------------------------------
-- BASEPLATE
-------------------------------------------------

local function buildBaseplate()
	local w, l = DesignConfig.MapWidth, DesignConfig.MapLength
	local cz = l / 2 - 150

	p({ Name = "Baseplate",
		Size = Vector3.new(w, 1, l),
		Position = Vector3.new(0, 0, cz),
		Color = DesignConfig.Colors.Baseplate })

	p({ Name = "Water",
		Size = Vector3.new(w * 3, 0.5, l * 3),
		Position = Vector3.new(0, -0.5, cz),
		Color = DesignConfig.Colors.Water,
		CanCollide = false, Transparency = 0.25 })
end

-------------------------------------------------
-- NPC BUILDER (R15 with pcall -> part-based fallback)
-------------------------------------------------

local function buildNPC(cfg, pos, parent)
	local name = cfg.name or "NPC"
	local skin = cfg.skinColor or Color3.fromRGB(255, 220, 185)
	local outfit = cfg.outfitColor or Color3.fromRGB(100, 100, 200)
	local pants = cfg.pantsColor or Color3.fromRGB(40, 40, 60)

	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = skin
		desc.LeftArmColor = skin
		desc.RightArmColor = skin
		desc.TorsoColor = outfit
		desc.LeftLegColor = pants
		desc.RightLegColor = pants
		desc.HeadScale = 1.2
		desc.BodyTypeScale = 0
		desc.ProportionScale = 0
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)

	if ok and model then
		model.Name = "NPC_" .. name
		for _, pt in ipairs(model:GetDescendants()) do
			if pt:IsA("BasePart") then pt.Anchored = true end
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
				* CFrame.Angles(0, math.rad(180), 0)
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		model.Parent = parent
		return model
	end

	-- Fallback: part-based character
	warn("[WorldBuilder] R15 failed, using parts for " .. name)
	local npc = Instance.new("Model")
	npc.Name = "NPC_" .. name
	local head = p({ Name = "Head", Size = Vector3.new(2, 2, 2),
		Position = pos + Vector3.new(0, 5.5, 0), Color = skin, Parent = npc })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere; mesh.Parent = head
	p({ Name = "Torso", Size = Vector3.new(2, 2.2, 1.2),
		Position = pos + Vector3.new(0, 3.5, 0), Color = outfit, Parent = npc })
	p({ Name = "LegL", Size = Vector3.new(0.8, 2.4, 0.8),
		Position = pos + Vector3.new(-0.5, 1.2, 0), Color = pants, Parent = npc })
	p({ Name = "LegR", Size = Vector3.new(0.8, 2.4, 0.8),
		Position = pos + Vector3.new(0.5, 1.2, 0), Color = pants, Parent = npc })
	npc.Parent = parent
	return npc
end

-------------------------------------------------
-- SHOP HUB (asset 95566802299515 — use stand asset when it loads)
-------------------------------------------------

local SHOP_ASSET_ID = 95566802299515
local STALL_SPACING = 30

local function buildHub()
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = Workspace

	local stalls = DesignConfig.Stalls
	local ctr = DesignConfig.HubCenter

	local asset = loadAndPrepAsset(SHOP_ASSET_ID, "Shop asset")
	local stallTemplate = nil
	local shopLoaded = false

	if asset then
		local best, bestParts = nil, 0
		local function search(obj, depth)
			if obj:IsA("Model") and depth >= 2 then
				local pc = 0
				for _, d in ipairs(obj:GetDescendants()) do
					if d:IsA("BasePart") then pc = pc + 1 end
				end
				local bmin, bmax = getModelBounds(obj)
				local sz = bmax - bmin
				if pc > bestParts and sz.X > 4 and sz.Z > 4 then
					best = obj
					bestParts = pc
				end
			end
			for _, child in ipairs(obj:GetChildren()) do
				if child:IsA("Model") or child:IsA("Folder") then search(child, depth + 1) end
			end
		end
		search(asset, 0)
		if not best then
			for _, child in ipairs(asset:GetChildren()) do
				if child:IsA("Model") then best = child; break end
			end
		end
		stallTemplate = best
		if stallTemplate then
			print("[WorldBuilder] Stall template: " .. stallTemplate.Name .. " (" .. bestParts .. " parts)")
		end
	end

	if stallTemplate then
		local totalW = (#stalls - 1) * STALL_SPACING
		local startX = ctr.X - totalW / 2

		for i, stallCfg in ipairs(stalls) do
			local x = startX + (i - 1) * STALL_SPACING
			local targetPos = Vector3.new(x, ctr.Y, ctr.Z)

			local clone = stallTemplate:Clone()
			clone.Name = "Stall_" .. stallCfg.name

			for _, gui in ipairs(clone:GetDescendants()) do
				if gui:IsA("BillboardGui") or gui:IsA("SurfaceGui") then gui:Destroy() end
			end
			for _, lbl in ipairs(clone:GetDescendants()) do
				if lbl:IsA("TextLabel") or lbl:IsA("TextButton") then lbl.Text = stallCfg.name end
			end
			local humModels = {}
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("Humanoid") and desc.Parent:IsA("Model") then
					table.insert(humModels, desc.Parent)
				end
			end
			for _, m in ipairs(humModels) do m:Destroy() end

			-- Recolor shop to match its title color
			local stallColor = stallCfg.color or Color3.fromRGB(100, 100, 200)
			local toRemove = {}
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("Texture") or desc:IsA("Decal") or desc:IsA("SurfaceAppearance") then
					table.insert(toRemove, desc)
				elseif desc:IsA("BasePart") then
					local sz = desc.Size
					if sz.X < 4 and sz.Y < 1 and sz.Z < 4 then
						table.insert(toRemove, desc)
					end
				end
			end
			for _, obj in ipairs(toRemove) do
				pcall(function() obj:Destroy() end)
			end
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					if part:IsA("MeshPart") then
						part.TextureID = ""
					end
					local h, s, _ = stallColor:ToHSV()
					local _, _, partV = part.Color:ToHSV()
					part.Color = Color3.fromHSV(h, math.clamp(s * 0.8, 0, 1), math.clamp(partV * 0.9 + 0.1, 0.3, 1))
					part.Material = Enum.Material.SmoothPlastic
				end
				if part:IsA("SpecialMesh") then
					part.TextureId = ""
				end
			end

			positionModel(clone, targetPos)
			clone.Parent = hub

			local bmin, bmax = getModelBounds(clone)
			local signAnchor = p({ Name = "Sign_" .. stallCfg.name,
				Size = Vector3.new(1, 1, 1),
				Position = targetPos + Vector3.new(0, (bmax.Y - bmin.Y) + 5, 0),
				Transparency = 1, CanCollide = false, Parent = hub })
			billboard(signAnchor, string.upper(stallCfg.name),
				DesignConfig.Colors.White,
				stallCfg.color or Color3.fromRGB(100, 100, 200),
				UDim2.new(16, 0, 4.5, 0), Vector3.new(0, 0, 0),
				{ font = Enum.Font.FredokaOne, strokeThickness = 4, strokeColor = Color3.fromRGB(20, 20, 40) })

			if stallCfg.npc then
				local npcCfg = stallCfg.npc
				npcCfg.name = stallCfg.name
				buildNPC(npcCfg, targetPos + Vector3.new(0, 0, -2), hub)
			end
		end

		shopLoaded = true
		p({ Name = "MarketFloor",
			Size = Vector3.new(totalW + 50, 0.4, 60),
			Position = ctr + Vector3.new(0, 0.3, 0),
			Color = Color3.fromRGB(60, 75, 120),
			Material = Enum.Material.Cobblestone, Parent = hub })
		print("[WorldBuilder] Hub built with shop stand asset")
	end

	if not shopLoaded then
		print("[WorldBuilder] Using fallback stalls (Shop asset not available)")
		local SP = 26
		local totalW = (#stalls - 1) * SP
		local startX = ctr.X - totalW / 2
		for i, cfg in ipairs(stalls) do
			local pos = Vector3.new(startX + (i - 1) * SP, ctr.Y, ctr.Z)
			local signPart = p({ Name = "Sign_" .. cfg.name,
				Size = Vector3.new(12, 3.5, 0.4),
				Position = pos + Vector3.new(0, 13, 0),
				Color = cfg.color, Transparency = 0.1, Parent = hub })
			billboard(signPart, string.upper(cfg.name), DesignConfig.Colors.White, nil,
				UDim2.new(16, 0, 4.5, 0), Vector3.new(0, 0, 0),
				{ font = Enum.Font.FredokaOne, strokeThickness = 4, strokeColor = Color3.fromRGB(20, 20, 40) })
			if cfg.npc then
				local npcCfg = cfg.npc
				npcCfg.name = cfg.name
				buildNPC(npcCfg, pos, hub)
			end
		end
		p({ Name = "MarketFloor",
			Size = Vector3.new(totalW + 40, 0.4, 50),
			Position = ctr + Vector3.new(0, 0.3, 0),
			Color = Color3.fromRGB(60, 75, 120),
			Material = Enum.Material.Cobblestone, Parent = hub })
	end
end

-------------------------------------------------
-- SPEED PADS (asset 11651534875)
-- Two strips: one forward (+Z), one backward (-Z)
-------------------------------------------------

local function buildSpeedPads()
	local folder = Instance.new("Folder")
	folder.Name = "SpeedPads"
	folder.Parent = Workspace

	local cfg = DesignConfig.SpeedPad
	local speed = cfg.Speed

	local asset = loadAndPrepAsset(cfg.AssetId, "Speed pad")
	local padTemplate = nil

	if asset then
		-- Log children
		print("[WorldBuilder] Speed pad asset children:")
		for _, child in ipairs(asset:GetChildren()) do
			local pc = 0
			for _, d in ipairs(child:GetDescendants()) do
				if d:IsA("BasePart") then pc = pc + 1 end
			end
			print("  " .. child.ClassName .. ": " .. child.Name .. " (" .. pc .. " parts)")
			if pc > 0 and not padTemplate then padTemplate = child end
		end
		if not padTemplate then padTemplate = asset end

		-- Log template bounds
		local bmin, bmax = getModelBounds(padTemplate)
		local sz = bmax - bmin
		print("[WorldBuilder] Speed pad template: " .. padTemplate.Name
			.. " size=" .. string.format("%.0fx%.0fx%.0f", sz.X, sz.Y, sz.Z))
	end

	local function placeStrip(name, xPos, yRot, pushZ)
		local stripFolder = Instance.new("Model")
		stripFolder.Name = name

		if padTemplate then
			local tmin, tmax = getModelBounds(padTemplate)
			local sz = tmax - tmin
			local totalLen = cfg.Length or 300

			print("[WorldBuilder] Speed pad size: " .. string.format("%.0fx%.0fx%.0f", sz.X, sz.Y, sz.Z))

			-- Determine which axis is longer and whether we need to rotate
			local needRotate = sz.X > sz.Z
			local tileStep = needRotate and sz.X or sz.Z
			if tileStep < 2 then tileStep = 6 end

			-- Overlap tiles generously to eliminate all visible seams
			local overlap = tileStep * 0.15
			local effectiveStep = tileStep - overlap

			local startZ = cfg.CenterZ - totalLen / 2
			local numTiles = math.ceil(totalLen / effectiveStep)
			local baseRot = needRotate and 90 or 0

			print("[WorldBuilder] Tiling " .. numTiles .. " pads seamlessly (step=" .. string.format("%.1f", effectiveStep) .. ")")

			local skyBlue = Color3.fromRGB(135, 206, 235)
			for i = 0, numTiles - 1 do
				local tile = padTemplate:Clone()
				tile.Name = "Tile_" .. i
				for _, desc in ipairs(tile:GetDescendants()) do
					if desc:IsA("Texture") or desc:IsA("Decal") or desc:IsA("SurfaceAppearance") then
						desc:Destroy()
					end
				end
				for _, part in ipairs(tile:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.Color = skyBlue
						part.Material = Enum.Material.SmoothPlastic
						if part:IsA("MeshPart") then
							part.TextureID = ""
						end
					end
					if part:IsA("SpecialMesh") then
						part.TextureId = ""
					end
				end
				local tileZ = startZ + i * effectiveStep
				positionModel(tile, Vector3.new(xPos, 0.5, tileZ), baseRot + yRot)
				tile.Parent = stripFolder
			end
		else
			-- Fallback: one long plain strip
			p({ Name = "Strip", Size = Vector3.new(20, 0.5, cfg.Length),
				Position = Vector3.new(xPos, 0.75, cfg.CenterZ),
				Color = DesignConfig.Colors.ConveyorBase, Parent = stripFolder })
		end

		stripFolder.Parent = folder

		-- Collect all pad parts for overlap checking
		local padParts = {}
		for _, part in ipairs(stripFolder:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(padParts, part)
			end
		end

		-- Helper: check if a root part is still touching any pad in this strip
		local function stillOnPad(root)
			for _, pp in ipairs(padParts) do
				-- Check overlap via distance (more reliable than GetTouchingParts)
				local dist = (root.Position - pp.Position)
				local halfSize = pp.Size / 2 + Vector3.new(2, 2, 2) -- generous margin
				if math.abs(dist.X) < halfSize.X
					and math.abs(dist.Y) < halfSize.Y + 3
					and math.abs(dist.Z) < halfSize.Z then
					return true
				end
			end
			return false
		end

		-- Wire push logic to ALL parts in the strip
		for _, part in ipairs(padParts) do
			part.Touched:Connect(function(hit)
				local char = hit.Parent; if not char then return end
				local hum = char:FindFirstChildOfClass("Humanoid")
				local root = char:FindFirstChild("HumanoidRootPart")
				if not hum or not root then return end
				-- Update velocity if already has push, or create new
				local existing = root:FindFirstChild("SpeedPush")
				if existing then
					existing.Velocity = Vector3.new(0, 0, pushZ)
					return
				end
				local bv = Instance.new("BodyVelocity")
				bv.Name = "SpeedPush"
				bv.MaxForce = Vector3.new(0, 0, 50000)
				bv.Velocity = Vector3.new(0, 0, pushZ)
				bv.Parent = root
			end)
			part.TouchEnded:Connect(function(hit)
				local char = hit.Parent; if not char then return end
				local root = char:FindFirstChild("HumanoidRootPart")
				if not root then return end
				-- Wait a moment then check if still on ANY pad tile
				task.delay(0.3, function()
					if not stillOnPad(root) then
						local psh = root:FindFirstChild("SpeedPush")
						if psh then psh:Destroy() end
					end
				end)
			end)
		end
		return stripFolder
	end

	-- Add scrolling arrow indicators to a strip
	local function addArrows(stripFolder, direction)
		local arrowSpacing = 16
		local stripMin, stripMax = getModelBounds(stripFolder)
		local centerX = (stripMin.X + stripMax.X) / 2
		local topY = stripMax.Y + 0.05
		local stripWidth = math.abs(stripMax.X - stripMin.X)
		local arrowW = math.min(stripWidth * 0.9, 22)
		local arrowD = 20
		local minZ = stripMin.Z + arrowD / 2
		local maxZ = stripMax.Z - arrowD / 2

		for z = minZ, maxZ, arrowSpacing do
			local arrowPart = Instance.new("Part")
			arrowPart.Name = "ArrowIndicator"
			arrowPart.Size = Vector3.new(arrowW, 0.05, arrowD)
			arrowPart.Position = Vector3.new(centerX, topY, z)
			arrowPart.Anchored = true
			arrowPart.CanCollide = false
			arrowPart.CanTouch = false
			arrowPart.CanQuery = false
			arrowPart.Transparency = 1
			arrowPart.Parent = stripFolder

			-- Rotate part so SurfaceGui scroll aligns with travel direction
			local yRot = direction > 0 and 90 or -90
			arrowPart.CFrame = CFrame.new(arrowPart.Position) * CFrame.Angles(0, math.rad(yRot), 0)

			local sg = Instance.new("SurfaceGui")
			sg.Name = "ArrowGui"
			sg.Face = Enum.NormalId.Top
			sg.CanvasSize = Vector2.new(400, 400)
			sg.LightInfluence = 0
			sg.Brightness = 1.5
			sg.AlwaysOnTop = false
			sg.Parent = arrowPart

			local container = Instance.new("Frame")
			container.Name = "ArrowContainer"
			container.Size = UDim2.new(1, 0, 1, 0)
			container.BackgroundTransparency = 1
			container.ClipsDescendants = true
			container.Parent = sg

			local ROWS = 2
			for copy = 0, 1 do
				local arrowFrame = Instance.new("Frame")
				arrowFrame.Name = "Arrows_" .. copy
				arrowFrame.Size = UDim2.new(1, 0, 1, 0)
				arrowFrame.Position = UDim2.new(0, 0, copy, 0)
				arrowFrame.BackgroundTransparency = 1
				arrowFrame.Parent = container

				for i = 0, ROWS - 1 do
					local lbl = Instance.new("TextLabel")
					lbl.Size = UDim2.new(0.9, 0, 1 / ROWS, 0)
					lbl.Position = UDim2.new(0.05, 0, i / ROWS, 0)
					lbl.BackgroundTransparency = 1
					lbl.Text = "▲"
					lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
					lbl.TextTransparency = 0.2
					lbl.Font = Enum.Font.GothamBold
					lbl.TextScaled = true
					lbl.Parent = arrowFrame
				end
			end

			-- Animate: scroll frames upward continuously
			task.spawn(function()
				local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
				for _, child in ipairs(container:GetChildren()) do
					if child:IsA("Frame") then
						local startY = child.Position.Y.Scale
						TweenService:Create(child, tweenInfo, {
							Position = UDim2.new(0, 0, startY - 1, 0)
						}):Play()
					end
				end
			end)
		end
	end

	-- Forward (+Z) on the left, Backward (-Z) on the right rotated 180
	local fwd = placeStrip("SpeedPad_Forward",  -cfg.StripGap, 0,   speed)
	local bwd = placeStrip("SpeedPad_Backward",  cfg.StripGap, 180, -speed)

	if fwd then addArrows(fwd, 1) end
	if bwd then addArrows(bwd, -1) end

	-- Debug: log final positions
	if fwd then
		local fmin, fmax = getModelBounds(fwd)
		print("[WorldBuilder] Forward pad: " .. tostring(fmin) .. " to " .. tostring(fmax))
	end
	if bwd then
		local bmin, bmax = getModelBounds(bwd)
		print("[WorldBuilder] Backward pad: " .. tostring(bmin) .. " to " .. tostring(bmax))
	end

	print("[WorldBuilder] Speed pads placed")
end

-------------------------------------------------
-- PLAYER BASES (asset 112269866373242)
-- 4 bases: 2 left, 2 right of speed pads
-- BaseService handles the per-player pad grid
-------------------------------------------------

-- Build a simple procedural base (raised platform + border) for when asset is not used
local function buildProceduralBaseSlot(name, basePos, parent)
	local h = 1
	local w, d = 50, 45
	-- Floor
	p({ Name = name .. "_Floor",
		Size = Vector3.new(w, h, d),
		Position = basePos + Vector3.new(0, h / 2, 0),
		Color = DesignConfig.Colors.BaseFloor,
		Parent = parent })
	-- Border (yellow outline like reference)
	local borderH = 1.5
	local borderT = 1.2
	p({ Name = name .. "_BorderFront",
		Size = Vector3.new(w + borderT * 2, borderH, borderT),
		Position = basePos + Vector3.new(0, borderH / 2, d / 2 + borderT / 2),
		Color = DesignConfig.Colors.BaseBorder,
		Parent = parent })
	p({ Name = name .. "_BorderBack",
		Size = Vector3.new(w + borderT * 2, borderH, borderT),
		Position = basePos + Vector3.new(0, borderH / 2, -d / 2 - borderT / 2),
		Color = DesignConfig.Colors.BaseBorder,
		Parent = parent })
	p({ Name = name .. "_BorderLeft",
		Size = Vector3.new(borderT, borderH, d + borderT * 2),
		Position = basePos + Vector3.new(-w / 2 - borderT / 2, borderH / 2, 0),
		Color = DesignConfig.Colors.BaseBorder,
		Parent = parent })
	p({ Name = name .. "_BorderRight",
		Size = Vector3.new(borderT, borderH, d + borderT * 2),
		Position = basePos + Vector3.new(w / 2 + borderT / 2, borderH / 2, 0),
		Color = DesignConfig.Colors.BaseBorder,
		Parent = parent })
end

local function buildBaseSlots()
	local asset = loadAndPrepAsset(DesignConfig.BaseAsset.AssetId, "Base asset")
	local baseTemplate = nil

	if asset then
		for _, child in ipairs(asset:GetChildren()) do
			local pc = 0
			for _, d in ipairs(child:GetDescendants()) do
				if d:IsA("BasePart") then pc = pc + 1 end
			end
			if pc > 0 then baseTemplate = child; break end
		end
		if not baseTemplate then baseTemplate = asset end

		if baseTemplate then
			local stored = baseTemplate:Clone()
			stored.Name = "BaseTemplate"
			stored.Parent = ReplicatedStorage
			print("[WorldBuilder] Base template stored (" .. #stored:GetDescendants() .. " descendants)")
		end
	end

	local basesFolder = Workspace:FindFirstChild("PlayerBases")
	if not basesFolder then
		basesFolder = Instance.new("Folder")
		basesFolder.Name = "PlayerBases"
		basesFolder.Parent = Workspace
	end

	for i, slotInfo in ipairs(DesignConfig.BasePositions) do
		local basePos = slotInfo.position
		local rotation = slotInfo.rotation or 0
		local name = "BaseSlot_" .. i

		if baseTemplate then
			local clone = baseTemplate:Clone()
			clone.Name = name

			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then part.Anchored = true end
			end
			for _, hum in ipairs(clone:GetDescendants()) do
				if hum:IsA("Humanoid") then
					hum.WalkSpeed = 0
					hum.JumpPower = 0
					hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				end
			end

			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					local sz = part.Size
					if sz.X < 2 and sz.Y < 2 and sz.Z < 2 then
						part:Destroy()
					else
						local r, g, b = part.Color.R, part.Color.G, part.Color.B
						local isYellow = (r > 0.7 and g > 0.6 and b < 0.4)
						local isSmallCircle = (part.Shape == Enum.PartType.Cylinder or part.Shape == Enum.PartType.Ball)
							and math.max(sz.X, sz.Y, sz.Z) < 10
						local isGlowing = part.Material == Enum.Material.Neon
						if (isYellow and (isSmallCircle or isGlowing)) or (isGlowing and isYellow) then
							part:Destroy()
						end
					end
				end
				if part:IsA("SpawnLocation") then part:Destroy() end
			end

			positionModel(clone, basePos, rotation)
			clone.Parent = basesFolder
			print("[WorldBuilder] Placed base slot " .. i .. " (asset) at " .. tostring(basePos))
		else
			-- Always-visible procedural base (old style): raised platform with border
			buildProceduralBaseSlot(name, basePos, basesFolder)
			print("[WorldBuilder] Placed base slot " .. i .. " (procedural) at " .. tostring(basePos))
		end
	end

	print("[WorldBuilder] All " .. #DesignConfig.BasePositions .. " base structures placed!")
end

-------------------------------------------------
-- PALM TREES
-------------------------------------------------

local function buildTree(pos, parent)
	local m = Instance.new("Model")
	m.Name = "PalmTree"
	p({ Name = "Trunk1", Size = Vector3.new(2, 10, 2),
		Position = pos + Vector3.new(0, 5, 0),
		Color = Color3.fromRGB(150, 105, 50), Parent = m })
	p({ Name = "Trunk2", Size = Vector3.new(1.8, 8, 1.8),
		Position = pos + Vector3.new(0.5, 13, 0.3),
		Color = Color3.fromRGB(160, 115, 55), Parent = m })
	local lc = Color3.fromRGB(55, 185, 65)
	for _, leaf in ipairs({
		{Vector3.new(5, 16, 0), Vector3.new(7, 0.5, 3)},
		{Vector3.new(-5, 16, 0), Vector3.new(7, 0.5, 3)},
		{Vector3.new(0, 16, 5), Vector3.new(3, 0.5, 7)},
		{Vector3.new(0, 16, -5), Vector3.new(3, 0.5, 7)},
	}) do
		p({ Name = "Leaf", Size = leaf[2], Position = pos + leaf[1],
			Color = lc, Parent = m })
	end
	p({ Name = "Top", Size = Vector3.new(3, 2.5, 3),
		Position = pos + Vector3.new(0.5, 17, 0.3),
		Color = Color3.fromRGB(45, 165, 55), Parent = m })
	m.Parent = parent
end

local function buildDecorations()
	local deco = Instance.new("Folder")
	deco.Name = "Decorations"
	deco.Parent = Workspace
	local halfW = DesignConfig.MapWidth / 2 - 20
	for z = -60, 600, 120 do
		buildTree(Vector3.new(-halfW, 0, z), deco)
		buildTree(Vector3.new(halfW, 0, z), deco)
	end
end

-------------------------------------------------
-- SPAWN
-------------------------------------------------

local function buildSpawn()
	local sp = Instance.new("SpawnLocation")
	sp.Name = "SpawnPoint"
	sp.Anchored = true
	sp.Size = Vector3.new(12, 1, 12)
	sp.Position = Vector3.new(0, 0.5, 15)
	sp.Color = DesignConfig.Colors.Baseplate
	sp.Material = Enum.Material.SmoothPlastic
	sp.Transparency = 1
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
	p({ Name = "PathToHub", Size = Vector3.new(10, 0.15, 60),
		Position = Vector3.new(0, 0.1, -70),
		Color = DesignConfig.Colors.PathColor, Parent = pf })
end

-------------------------------------------------
-- MAP BOUNDARIES (INVISIBLE WALLS)
-------------------------------------------------

local function buildBoundaries()
	local bounds = Instance.new("Folder")
	bounds.Name = "Boundaries"
	bounds.Parent = Workspace

	local w, l = DesignConfig.MapWidth, DesignConfig.MapLength
	local cz = l / 2 - 150
	local halfW = w / 2
	local halfL = l / 2

	local wallHeight = 60
	local wallThickness = 2
	local wallColor = DesignConfig.Colors.Baseplate

	-- Front (toward negative Z)
	p({
		Name = "Boundary_Front",
		Size = Vector3.new(w, wallHeight, wallThickness),
		Position = Vector3.new(0, wallHeight / 2, cz - halfL - wallThickness / 2),
		Color = wallColor,
		Transparency = 1,
		Parent = bounds,
	})

	-- Back (toward positive Z)
	p({
		Name = "Boundary_Back",
		Size = Vector3.new(w, wallHeight, wallThickness),
		Position = Vector3.new(0, wallHeight / 2, cz + halfL + wallThickness / 2),
		Color = wallColor,
		Transparency = 1,
		Parent = bounds,
	})

	-- Left (negative X)
	p({
		Name = "Boundary_Left",
		Size = Vector3.new(wallThickness, wallHeight, l + wallThickness * 2),
		Position = Vector3.new(-halfW - wallThickness / 2, wallHeight / 2, cz),
		Color = wallColor,
		Transparency = 1,
		Parent = bounds,
	})

	-- Right (positive X)
	p({
		Name = "Boundary_Right",
		Size = Vector3.new(wallThickness, wallHeight, l + wallThickness * 2),
		Position = Vector3.new(halfW + wallThickness / 2, wallHeight / 2, cz),
		Color = wallColor,
		Transparency = 1,
		Parent = bounds,
	})
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function WorldBuilder.Build()
	for _, name in ipairs({
		"Baseplate", "Water", "Hub", "Decorations", "Boundaries",
		"SpawnPoint", "Paths", "PlayerBases", "PlayerBaseData", "SpeedPads", "Conveyors",
	}) do
		local e = Workspace:FindFirstChild(name)
		if e then e:Destroy() end
	end

	setupLighting()
	buildBaseplate()
	buildHub()
	buildSpeedPads()
	buildBaseSlots()
	buildSpawn()
	buildPaths()
	buildBoundaries()

	print("[WorldBuilder] Built — shops + speed pads + 4 base structures placed")
end

return WorldBuilder
