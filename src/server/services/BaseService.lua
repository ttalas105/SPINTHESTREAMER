--[[
	BaseService.lua
	Single-slot interaction on existing base geometry:
	- Use one existing green box + one existing grey slot from each assigned base model.
	- Prompt appears above green box to place/remove held streamer.
	- Placed streamer sits centered on grey slot and faces the green box.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BaseReady = RemoteEvents:WaitForChild("BaseReady")
local DisplayInteract = RemoteEvents:WaitForChild("DisplayInteract")
local EquipResult = RemoteEvents:WaitForChild("EquipResult")
local UnequipResult = RemoteEvents:WaitForChild("UnequipResult")

local BaseService = {}

BaseService._bases = {}          -- userId -> { position, slotIndex, baseModel, greenPart, greyPart, prompt }
BaseService._occupiedSlots = {}  -- set of occupied slot indices
BaseService._displayModels = {}  -- userId -> Model (single slot only)
BaseService._pendingMoney = {}   -- userId -> accumulated display money
BaseService._collectDebounce = {} -- userId -> bool
BaseService._nextMoneyTickAt = {} -- userId -> os.clock timestamp

local BASE_POSITIONS = DesignConfig.BasePositions
local PlayerData
local DISPLAY_SCALE_MULT = 1.15

local function formatNumber(n)
	local s = tostring(math.floor(n))
	local out = ""
	local len = #s
	for i = 1, len do
		out = out .. s:sub(i, i)
		if (len - i) % 3 == 0 and i < len then
			out = out .. ","
		end
	end
	return out
end

local function color3ToHex(c: Color3): string
	local r = math.clamp(math.floor(c.R * 255 + 0.5), 0, 255)
	local g = math.clamp(math.floor(c.G * 255 + 0.5), 0, 255)
	local b = math.clamp(math.floor(c.B * 255 + 0.5), 0, 255)
	return string.format("#%02X%02X%02X", r, g, b)
end

local function addDisplayBillboard(model: Model, adornee: BasePart, streamerItem)
	local streamerId = type(streamerItem) == "table" and streamerItem.id or streamerItem
	local effectName = type(streamerItem) == "table" and streamerItem.effect or nil
	local info = Streamers.ById[streamerId]
	if not info then return end

	local rarityColor = DesignConfig.RarityColors[info.rarity] or Color3.fromRGB(255, 255, 255)
	local cps = info.cashPerSecond or 0
	if effectName then
		local eff = Effects.ByName[effectName]
		if eff and eff.cashMultiplier then
			cps = math.floor(cps * eff.cashMultiplier)
		end
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "DisplayInfo"
	bb.Adornee = adornee
	bb.Size = UDim2.new(0, 260, 0, 70)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 60
	bb.Parent = model

	local label = Instance.new("TextLabel")
	label.Name = "InfoLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextWrapped = true
	label.RichText = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = string.format(
		"<font color=\"%s\">%s</font>\n$%s/s",
		color3ToHex(rarityColor),
		info.displayName or streamerId,
		formatNumber(cps)
	)
	label.Parent = bb

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label
end

local function ensureMoneyGui(baseInfo)
	if not baseInfo or not baseInfo.greenPart then return nil end
	local green = baseInfo.greenPart
	local gui = green:FindFirstChild("MoneyCounterGui")
	if gui and gui:IsA("SurfaceGui") then
		local label = gui:FindFirstChild("MoneyLabel")
		if label and label:IsA("TextLabel") then
			return label
		end
		gui:Destroy()
	end

	gui = Instance.new("SurfaceGui")
	gui.Name = "MoneyCounterGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 35
	gui.AlwaysOnTop = true
	gui.Parent = green

	local label = Instance.new("TextLabel")
	label.Name = "MoneyLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Visible = false
	label.Text = ""
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label

	return label
end

local updateMoneyText

local function tryCollectMoney(player: Player)
	local data = PlayerData and PlayerData.Get(player)
	if not data then return end
	local equipped = data.equippedPads and data.equippedPads["1"]
	if not equipped then return end

	local userId = player.UserId
	if BaseService._collectDebounce[userId] then return end
	BaseService._collectDebounce[userId] = true

	local amount = BaseService._pendingMoney[userId] or 0
	if amount > 0 then
		local collected = math.floor(amount)
		BaseService._pendingMoney[userId] = 0
		PlayerData.AddCash(player, collected)
		-- Restart income timer from now so next increment is a full second away.
		BaseService._nextMoneyTickAt[userId] = os.clock() + 1
		updateMoneyText(player)
	end

	task.delay(0.25, function()
		BaseService._collectDebounce[userId] = nil
	end)
end

updateMoneyText = function(player: Player)
	local baseInfo = BaseService._bases[player.UserId]
	if not baseInfo then return end
	local label = ensureMoneyGui(baseInfo)
	if not label then return end
	local data = PlayerData and PlayerData.Get(player)
	local hasPlaced = data and data.equippedPads and data.equippedPads["1"] ~= nil
	if not hasPlaced then
		label.Visible = false
		label.Text = ""
		return
	end
	local amount = BaseService._pendingMoney[player.UserId] or 0
	label.Visible = true
	label.Text = "$" .. formatNumber(amount)
end

local function findAvailableSlot(): number?
	for i = 1, #BASE_POSITIONS do
		if not BaseService._occupiedSlots[i] then
			return i
		end
	end
	return nil
end

local function isGreenCandidate(part: BasePart): boolean
	local c = part.Color
	return part.Material == Enum.Material.Neon and c.G > 0.6 and c.G > c.R and c.G > c.B
end

local function isGreyCandidate(part: BasePart): boolean
	local c = part.Color
	local d1 = math.abs(c.R - c.G)
	local d2 = math.abs(c.G - c.B)
	local d3 = math.abs(c.R - c.B)
	local nearGrey = d1 < 0.12 and d2 < 0.12 and d3 < 0.12
	return nearGrey and part.Size.X >= 2 and part.Size.Z >= 2 and part.Material ~= Enum.Material.Neon
end

local function findBestSlotParts(baseModel: Model): (BasePart?, BasePart?)
	local greenParts = {}
	local greyParts = {}
	for _, d in ipairs(baseModel:GetDescendants()) do
		if d:IsA("BasePart") then
			if isGreenCandidate(d) then
				table.insert(greenParts, d)
			elseif isGreyCandidate(d) then
				table.insert(greyParts, d)
			end
		end
	end
	if #greenParts == 0 or #greyParts == 0 then
		return nil, nil
	end

	-- Pick the "first" green box deterministically (one end of the row),
	-- then pair it with the closest grey slot.
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, g in ipairs(greenParts) do
		minX = math.min(minX, g.Position.X)
		maxX = math.max(maxX, g.Position.X)
		minZ = math.min(minZ, g.Position.Z)
		maxZ = math.max(maxZ, g.Position.Z)
	end
	local useX = (maxX - minX) >= (maxZ - minZ)
	table.sort(greenParts, function(a, b)
		local av = useX and a.Position.X or a.Position.Z
		local bv = useX and b.Position.X or b.Position.Z
		if math.abs(av - bv) < 0.001 then
			return a.Name < b.Name
		end
		return av < bv
	end)

	-- Use opposite end of the row from previous selection.
	local chosenGreen = greenParts[#greenParts]
	local bestGrey = nil
	local bestDist = math.huge
	for _, s in ipairs(greyParts) do
		local d = (chosenGreen.Position - s.Position).Magnitude
		if d < bestDist then
			bestDist = d
			bestGrey = s
		end
	end
	return chosenGreen, bestGrey
end

local function cleanDisplayModel(model: Model)
	local toDestroy = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")
			or d:IsA("BillboardGui") or d:IsA("SurfaceGui")
			or d:IsA("ClickDetector") or d:IsA("ProximityPrompt")
			or d:IsA("Sound")
		then
			table.insert(toDestroy, d)
		end
	end
	for _, d in ipairs(toDestroy) do
		pcall(function() d:Destroy() end)
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.PlatformStand = true
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then animator:Destroy() end
	end

	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
		end
	end
end

local function clearPlacedModel(player: Player)
	local existing = BaseService._displayModels[player.UserId]
	if existing then
		pcall(function() existing:Destroy() end)
		BaseService._displayModels[player.UserId] = nil
	end
end

local function placeOnGreySlot(player: Player, streamerItem): boolean
	local baseInfo = BaseService._bases[player.UserId]
	if not baseInfo or not baseInfo.greyPart or not baseInfo.greenPart then return false end

	local streamerId = type(streamerItem) == "table" and streamerItem.id or streamerItem
	local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	if not modelsFolder then return false end
	local template = modelsFolder:FindFirstChild(streamerId)
	if not template then return false end

	clearPlacedModel(player)

	local clone = template:Clone()
	clone.Name = "SingleSlotDisplay"
	cleanDisplayModel(clone)

	local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
	if not primary then
		clone:Destroy()
		return false
	end
	clone.PrimaryPart = primary

	-- Slight display-only upscale for all streamers.
	local ok, _, size = pcall(function() return clone:GetBoundingBox() end)
	if ok and size and size.Y > 0 then
		clone:ScaleTo(DISPLAY_SCALE_MULT)
	end

	local rootPart = clone:FindFirstChild("HumanoidRootPart", true)
	if not (rootPart and rootPart:IsA("BasePart")) then
		rootPart = clone.PrimaryPart
	end
	if not (rootPart and rootPart:IsA("BasePart")) then
		local fallback = clone:FindFirstChildWhichIsA("BasePart", true)
		if fallback then
			rootPart = fallback
		end
	end

	local grey = baseInfo.greyPart
	local green = baseInfo.greenPart
	-- Keep character upright: face the green box on the horizontal plane only.
	local flatTarget = Vector3.new(green.Position.X, grey.Position.Y, green.Position.Z)
	if (flatTarget - grey.Position).Magnitude < 0.05 then
		flatTarget = grey.Position + Vector3.new(0, 0, -1)
	end
	local faceCF = CFrame.lookAt(grey.Position, flatTarget)
	clone:PivotTo(faceCF)

	-- Lock X/Z by root position so accessories/mesh bounds do not shift slot placement.
	if rootPart then
		local rootPos = rootPart.Position
		local xzDelta = Vector3.new(grey.Position.X - rootPos.X, 0, grey.Position.Z - rootPos.Z)
		clone:PivotTo(clone:GetPivot() + xzDelta)
	end

	local padTopY = grey.Position.Y + (grey.Size.Y / 2)
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum and rootPart then
		-- Ground by humanoid foot plane so accessories/outfits do not cause floating.
		local feetY = rootPart.Position.Y - (rootPart.Size.Y * 0.5 + hum.HipHeight)
		local yLift = padTopY - feetY + 0.03
		clone:PivotTo(clone:GetPivot() + Vector3.new(0, yLift, 0))
	else
		-- Fallback for non-humanoid models.
		local boxCF, boxSize = clone:GetBoundingBox()
		local bottomY = boxCF.Position.Y - (boxSize.Y / 2)
		local yLift = padTopY - bottomY + 0.03
		clone:PivotTo(clone:GetPivot() + Vector3.new(0, yLift, 0))
	end

	-- Streamer-specific correction: Cinna rig can sink; clamp by actual bounds bottom.
	if streamerId == "Cinna" then
		local cinnaCF, cinnaSize = clone:GetBoundingBox()
		local cinnaBottom = cinnaCF.Position.Y - (cinnaSize.Y / 2)
		local minBottom = padTopY + 0.03
		if cinnaBottom < minBottom then
			clone:PivotTo(clone:GetPivot() + Vector3.new(0, minBottom - cinnaBottom, 0))
		end
	end

	local parent = baseInfo.baseModel or Workspace
	clone.Parent = parent
	if rootPart then
		addDisplayBillboard(clone, rootPart, streamerItem)
	end
	BaseService._displayModels[player.UserId] = clone
	return true
end

local function updatePromptText(player: Player)
	local baseInfo = BaseService._bases[player.UserId]
	if not baseInfo or not baseInfo.prompt then return end
	local data = PlayerData and PlayerData.Get(player)
	local hasPlaced = data and data.equippedPads and data.equippedPads["1"] ~= nil
	baseInfo.prompt.ActionText = hasPlaced and "Remove Streamer" or "Place Streamer"
	baseInfo.prompt.ObjectText = "Base Slot"
end

local function bindCollectTouch(baseInfo, player: Player)
	if not baseInfo or not baseInfo.greenPart then return end
	baseInfo.greenPart.Touched:Connect(function(hit)
		local char = hit.Parent
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local touchPlayer = Players:GetPlayerFromCharacter(char)
		if not touchPlayer or touchPlayer.UserId ~= player.UserId then return end
		tryCollectMoney(touchPlayer)
	end)
end

local function bindPrompt(baseInfo, player: Player)
	if not baseInfo.greyPart then return end
	local promptAttachment = Instance.new("Attachment")
	promptAttachment.Name = "DisplayPromptAttachment"
	promptAttachment.Position = Vector3.new(0, 4.5, 0)
	promptAttachment.Parent = baseInfo.greyPart

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BaseSingleSlotPrompt"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptAttachment
	baseInfo.prompt = prompt
	updatePromptText(player)
	updateMoneyText(player)
	bindCollectTouch(baseInfo, player)
end

local function assignBase(player)
	local slot = findAvailableSlot()
	if not slot then
		warn("[BaseService] Server full (no base slot) for " .. player.Name)
		return
	end

	BaseService._occupiedSlots[slot] = true
	local slotInfo = BASE_POSITIONS[slot]
	local playerBasesFolder = Workspace:FindFirstChild("PlayerBases")
	local baseModel = playerBasesFolder and playerBasesFolder:FindFirstChild("BaseSlot_" .. slot)
	local greenPart, greyPart = nil, nil
	if baseModel and baseModel:IsA("Model") then
		greenPart, greyPart = findBestSlotParts(baseModel)
	end
	BaseService._bases[player.UserId] = {
		position = slotInfo.position,
		slotIndex = slot,
		baseModel = baseModel,
		greenPart = greenPart,
		greyPart = greyPart,
		prompt = nil,
	}
	BaseService._pendingMoney[player.UserId] = 0
	if greenPart and greyPart then
		bindPrompt(BaseService._bases[player.UserId], player)
	else
		warn("[BaseService] Could not find green/grey slot parts in BaseSlot_" .. tostring(slot))
	end

	BaseReady:FireClient(player, {
		position = slotInfo.position,
		floorSize = DesignConfig.Base.FloorSize,
	})
end

function BaseService.Init(playerDataModule, _potionServiceModule)
	PlayerData = playerDataModule

	Players.PlayerAdded:Connect(function(player)
		task.wait(1)
		assignBase(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local baseInfo = BaseService._bases[player.UserId]
		if baseInfo then
			clearPlacedModel(player)
			if baseInfo.prompt then
				pcall(function() baseInfo.prompt:Destroy() end)
			end
			BaseService._occupiedSlots[baseInfo.slotIndex] = nil
			BaseService._bases[player.UserId] = nil
		end
		BaseService._pendingMoney[player.UserId] = nil
	end)

	-- Handle already-connected players
	for _, player in ipairs(Players:GetPlayers()) do
		if not BaseService._bases[player.UserId] then
			task.spawn(function()
				assignBase(player)
			end)
		end
	end

	DisplayInteract.OnServerEvent:Connect(function(player, _padSlot, heldStreamerId, _heldEffect)
		local data = PlayerData and PlayerData.Get(player)
		local baseInfo = BaseService._bases[player.UserId]
		if not data or not baseInfo then return end
		if not baseInfo.greenPart or not baseInfo.greyPart then return end

		local equipped = data.equippedPads["1"]
		if equipped then
			local streamerId = type(equipped) == "table" and equipped.id or equipped
			local effect = type(equipped) == "table" and equipped.effect or nil
			local pending = BaseService._pendingMoney[player.UserId] or 0
			local ok = PlayerData.UnequipFromPad(player, 1)
			if ok then
				if pending > 0 then
					PlayerData.AddCash(player, math.floor(pending))
				end
				clearPlacedModel(player)
				BaseService._pendingMoney[player.UserId] = 0
				BaseService._nextMoneyTickAt[player.UserId] = nil
				updateMoneyText(player)
				updatePromptText(player)
				UnequipResult:FireClient(player, {
					success = true,
					padSlot = 1,
					streamerId = streamerId,
					effect = effect,
				})
			end
			return
		end

		if not heldStreamerId or typeof(heldStreamerId) ~= "string" then
			return
		end

		local ok = PlayerData.EquipToPad(player, heldStreamerId, 1)
		if ok then
			local item = data.equippedPads["1"]
			if placeOnGreySlot(player, item) then
				BaseService._pendingMoney[player.UserId] = 0
				BaseService._nextMoneyTickAt[player.UserId] = os.clock() + 1
				updateMoneyText(player)
				updatePromptText(player)
				EquipResult:FireClient(player, {
					success = true,
					padSlot = 1,
					streamerId = heldStreamerId,
				})
			end
		else
			EquipResult:FireClient(player, { success = false, reason = "Cannot place here." })
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerData and PlayerData.Get(player)
				if not data then
					continue
				end
				local item = data.equippedPads and data.equippedPads["1"]
				if not item then
					BaseService._nextMoneyTickAt[player.UserId] = nil
					continue
				end
				local streamerId = type(item) == "table" and item.id or item
				local effectName = type(item) == "table" and item.effect or nil
				local info = Streamers.ById[streamerId]
				if not info then
					continue
				end
				local perSec = info.cashPerSecond or 0
				if effectName then
					local eff = Effects.ByName[effectName]
					if eff and eff.cashMultiplier then
						perSec = perSec * eff.cashMultiplier
					end
				end
				local userId = player.UserId
				local nextTick = BaseService._nextMoneyTickAt[userId]
				if not nextTick then
					BaseService._nextMoneyTickAt[userId] = now + 1
					nextTick = BaseService._nextMoneyTickAt[userId]
				end
				if now >= nextTick then
					BaseService._pendingMoney[userId] = (BaseService._pendingMoney[userId] or 0) + math.floor(perSec)
					BaseService._nextMoneyTickAt[userId] = now + 1
					updateMoneyText(player)
				end
			end
		end
	end)
end

function BaseService.GetBasePosition(player): Vector3?
	local baseInfo = BaseService._bases[player.UserId]
	return baseInfo and baseInfo.position or nil
end

-- Kept for compatibility; now updates single-slot prompt text.
function BaseService.UpdateBasePads(player)
	if not player then return end
	updatePromptText(player)
end

-- Kept for compatibility; clear single-slot display on rebirth.
function BaseService.ClearDisplaysForRebirth(player)
	if not player then return end
	clearPlacedModel(player)
	BaseService._pendingMoney[player.UserId] = 0
	BaseService._nextMoneyTickAt[player.UserId] = nil
	updateMoneyText(player)
	updatePromptText(player)
end

return BaseService
