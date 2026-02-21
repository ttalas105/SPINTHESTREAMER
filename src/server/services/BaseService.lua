--[[
	BaseService.lua
	Multi-display interaction on existing base geometry:
	- Uses all green/grey display pairs found in each assigned base model.
	- Each display gets its own prompt, model placement, and money counter.
	- Opposite side slot ordering is mirrored so numbering/model direction flips.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local SlotsConfig = require(ReplicatedStorage.Shared.Config.SlotsConfig)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)
local VFXHelper = require(ReplicatedStorage.Shared.VFXHelper)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BaseReady = RemoteEvents:WaitForChild("BaseReady")
local DisplayInteract = RemoteEvents:WaitForChild("DisplayInteract")
local EquipResult = RemoteEvents:WaitForChild("EquipResult")
local UnequipResult = RemoteEvents:WaitForChild("UnequipResult")

local BaseService = {}

BaseService._bases = {} -- userId -> { position, slotIndex, baseModel, displays = { [padSlot] = displayInfo } }
BaseService._occupiedSlots = {} -- set of occupied slot indices
BaseService._displayModels = {} -- userId -> { [padSlot] = Model }
BaseService._pendingMoney = {} -- userId -> { [padSlot] = number }
BaseService._collectDebounce = {} -- userId -> { [padSlot] = bool }
BaseService._nextMoneyTickAt = {} -- userId -> { [padSlot] = os.clock timestamp }
BaseService._equipDebounce = {} -- userId -> { [padSlot] = os.clock timestamp }

local BASE_POSITIONS = DesignConfig.BasePositions
local PlayerData
local PotionService
local DISPLAY_SCALE_MULT = 1.15
local MAX_BASE_DISPLAYS = SlotsConfig.MaxTotalSlots

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

local function getNestedTable(bucket, userId)
	local t = bucket[userId]
	if not t then
		t = {}
		bucket[userId] = t
	end
	return t
end

--- Effective cash/sec for a streamer item including effect, cash upgrade, and potion
local function getEffectiveCps(player: Player, streamerItem): number
	local streamerId = type(streamerItem) == "table" and streamerItem.id or streamerItem
	local effectName = type(streamerItem) == "table" and streamerItem.effect or nil
	local info = Streamers.ById[streamerId]
	if not info then return 0 end
	local cps = info.cashPerSecond or 0
	if effectName then
		local eff = Effects.ByName[effectName]
		if eff and eff.cashMultiplier then
			cps = cps * eff.cashMultiplier
		end
	end
	local cashUpgradeMult = PlayerData and PlayerData.GetCashUpgradeMultiplier(player) or 1
	local potionMult = PotionService and PotionService.GetCashMultiplier(player) or 1
	return cps * cashUpgradeMult * potionMult
end

local function buildBillboardText(info, streamerId, effectName, rarityColor, cps)
	local lines = {}
	if effectName then
		local eff = Effects.ByName[effectName]
		local effColor = eff and eff.color or Color3.fromRGB(200, 200, 200)
		table.insert(lines, string.format(
			"<font color=\"%s\"><b>%s</b></font>",
			color3ToHex(effColor),
			effectName
		))
	end
	table.insert(lines, string.format(
		"<font color=\"%s\">%s</font>",
		color3ToHex(rarityColor),
		info.displayName or streamerId
	))
	table.insert(lines, string.format(
		"<font color=\"#50FF78\">$%s/s</font>",
		formatNumber(cps)
	))
	return table.concat(lines, "\n")
end

local function addDisplayBillboard(model: Model, adornee: BasePart, streamerItem, player: Player?)
	local streamerId = type(streamerItem) == "table" and streamerItem.id or streamerItem
	local effectName = type(streamerItem) == "table" and streamerItem.effect or nil
	local info = Streamers.ById[streamerId]
	if not info then return end

	local rarityColor = DesignConfig.RarityColors[info.rarity] or Color3.fromRGB(255, 255, 255)
	local cps = (player and getEffectiveCps(player, streamerItem)) or (info.cashPerSecond or 0)
	if not player then
		if effectName then
			local eff = Effects.ByName[effectName]
			if eff and eff.cashMultiplier then cps = cps * eff.cashMultiplier end
		end
	end
	cps = math.floor(cps)

	local hasEffect = effectName ~= nil
	local bb = Instance.new("BillboardGui")
	bb.Name = "DisplayInfo"
	bb.Adornee = adornee
	bb.Size = UDim2.new(0, 280, 0, hasEffect and 95 or 70)
	bb.StudsOffset = Vector3.new(0, hasEffect and 5 or 4.5, 0)
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
	label.Text = buildBillboardText(info, streamerId, effectName, rarityColor, cps)
	label.Parent = bb

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = label
end

local function ensureMoneyGui(displayInfo)
	if not displayInfo or not displayInfo.greenPart then return nil end
	local green = displayInfo.greenPart
	local labelRotation = displayInfo.isOppositeSide and 180 or 0
	local gui = green:FindFirstChild("MoneyCounterGui")
	if gui and gui:IsA("SurfaceGui") then
		local label = gui:FindFirstChild("MoneyLabel")
		if label and label:IsA("TextLabel") then
			label.Rotation = labelRotation
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
	label.Rotation = labelRotation
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label

	return label
end

local updateMoneyText

local function tryCollectMoney(player: Player, padSlot: number)
	local key = tostring(padSlot)
	local data = PlayerData and PlayerData.Get(player)
	if not data then return end
	local equipped = data.equippedPads and data.equippedPads[key]
	if not equipped then return end

	local userId = player.UserId
	local debounceBySlot = getNestedTable(BaseService._collectDebounce, userId)
	if debounceBySlot[padSlot] then return end
	debounceBySlot[padSlot] = true

	local pendingBySlot = getNestedTable(BaseService._pendingMoney, userId)
	local amount = pendingBySlot[padSlot] or 0
	if amount > 0 then
		PlayerData.AddCash(player, math.floor(amount))
		pendingBySlot[padSlot] = 0
		-- Restart this slot's income timer from now.
		local nextBySlot = getNestedTable(BaseService._nextMoneyTickAt, userId)
		nextBySlot[padSlot] = os.clock() + 1
		updateMoneyText(player, padSlot)
	end

	task.delay(0.25, function()
		local slotDebounce = BaseService._collectDebounce[userId]
		if slotDebounce then
			slotDebounce[padSlot] = nil
		end
	end)
end

--- Update the $/s display on the placed streamer model to reflect current cash upgrade + potion
local function updateDisplayBillboardCps(player: Player, padSlot: number)
	local bySlot = BaseService._displayModels[player.UserId]
	if not bySlot then return end
	local model = bySlot[padSlot]
	if not model or not model.Parent then return end
	local data = PlayerData and PlayerData.Get(player)
	local item = data and data.equippedPads and data.equippedPads[tostring(padSlot)]
	if not item then return end
	local streamerId = type(item) == "table" and item.id or item
	local effectName = type(item) == "table" and item.effect or nil
	local info = Streamers.ById[streamerId]
	if not info then return end
	local rarityColor = DesignConfig.RarityColors[info.rarity] or Color3.fromRGB(255, 255, 255)
	local cps = math.floor(getEffectiveCps(player, item))
	local bb = model:FindFirstChild("DisplayInfo", true)
	if bb and bb:IsA("BillboardGui") then
		local label = bb:FindFirstChild("InfoLabel")
		if label and label:IsA("TextLabel") then
			label.Text = buildBillboardText(info, streamerId, effectName, rarityColor, cps)
		end
		bb.Size = UDim2.new(0, 280, 0, effectName and 95 or 70)
		bb.StudsOffset = Vector3.new(0, effectName and 5 or 4.5, 0)
	end
end

updateMoneyText = function(player: Player, padSlot: number)
	local baseInfo = BaseService._bases[player.UserId]
	if not baseInfo then return end
	local displayInfo = baseInfo.displays and baseInfo.displays[padSlot]
	if not displayInfo then return end

	local label = ensureMoneyGui(displayInfo)
	if not label then return end

	local data = PlayerData and PlayerData.Get(player)
	local hasPlaced = data and data.equippedPads and data.equippedPads[tostring(padSlot)] ~= nil
	if not hasPlaced then
		label.Visible = false
		label.Text = ""
		return
	end

	local pendingBySlot = BaseService._pendingMoney[player.UserId]
	local amount = pendingBySlot and pendingBySlot[padSlot] or 0
	label.Visible = true
	label.Text = "$" .. formatNumber(amount)
	updateDisplayBillboardCps(player, padSlot)
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

local function getMajorMinor(majorOnX: boolean, position: Vector3): (number, number)
	local major = majorOnX and position.X or position.Z
	local minor = majorOnX and position.Z or position.X
	return major, minor
end

local function nearestGrey(green: BasePart, greys: { BasePart }, used: { [BasePart]: boolean }): BasePart?
	local bestGrey = nil
	local bestDist = math.huge
	for _, grey in ipairs(greys) do
		if not used[grey] then
			local d = (green.Position - grey.Position).Magnitude
			if d < bestDist then
				bestDist = d
				bestGrey = grey
			end
		end
	end
	return bestGrey
end

local function nearestGreyExcluding(
	green: BasePart,
	greys: { BasePart },
	used: { [BasePart]: boolean },
	blockedGrey: BasePart?
): BasePart?
	local bestGrey = nil
	local bestDist = math.huge
	for _, grey in ipairs(greys) do
		if grey ~= blockedGrey and not used[grey] then
			local d = (green.Position - grey.Position).Magnitude
			if d < bestDist then
				bestDist = d
				bestGrey = grey
			end
		end
	end
	return bestGrey
end

local function nearestGreyAny(green: BasePart, greys: { BasePart }): BasePart?
	local bestGrey = nil
	local bestDist = math.huge
	for _, grey in ipairs(greys) do
		local d = (green.Position - grey.Position).Magnitude
		if d < bestDist then
			bestDist = d
			bestGrey = grey
		end
	end
	return bestGrey
end

local function buildDisplayPairs(baseModel: Model): { [number]: { padSlot: number, greenPart: BasePart, greyPart: BasePart, prompt: ProximityPrompt? } }
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
		return {}
	end

	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, g in ipairs(greenParts) do
		minX = math.min(minX, g.Position.X)
		maxX = math.max(maxX, g.Position.X)
		minZ = math.min(minZ, g.Position.Z)
		maxZ = math.max(maxZ, g.Position.Z)
	end
	local majorOnX = (maxX - minX) >= (maxZ - minZ)

	local sortedGreens = table.clone(greenParts)
	table.sort(sortedGreens, function(a, b)
		local aMajor, aMinor = getMajorMinor(majorOnX, a.Position)
		local bMajor, bMinor = getMajorMinor(majorOnX, b.Position)
		if math.abs(aMinor - bMinor) > 0.001 then
			return aMinor < bMinor
		end
		if math.abs(aMajor - bMajor) < 0.001 then
			return a.Name < b.Name
		end
		return aMajor < bMajor
	end)

	-- Split into near/far sides by median on the minor axis.
	local medianMinor = 0
	do
		local mids = {}
		for _, g in ipairs(sortedGreens) do
			local _, minor = getMajorMinor(majorOnX, g.Position)
			table.insert(mids, minor)
		end
		table.sort(mids)
		medianMinor = mids[math.ceil(#mids / 2)] or 0
	end

	local nearSide = {}
	local farSide = {}
	for _, g in ipairs(sortedGreens) do
		local _, minor = getMajorMinor(majorOnX, g.Position)
		if minor <= medianMinor then
			table.insert(nearSide, g)
		else
			table.insert(farSide, g)
		end
	end
	if #nearSide == 0 then
		nearSide, farSide = farSide, nearSide
	end

	local function sortByMajor(list)
		table.sort(list, function(a, b)
			local aMajor = getMajorMinor(majorOnX, a.Position)
			local bMajor = getMajorMinor(majorOnX, b.Position)
			if math.abs(aMajor - bMajor) < 0.001 then
				return a.Name < b.Name
			end
			return aMajor < bMajor
		end)
	end
	sortByMajor(nearSide)
	sortByMajor(farSide)

	local nearGreys = {}
	local farGreys = {}
	for _, grey in ipairs(greyParts) do
		local _, minor = getMajorMinor(majorOnX, grey.Position)
		if minor <= medianMinor then
			table.insert(nearGreys, grey)
		else
			table.insert(farGreys, grey)
		end
	end
	sortByMajor(nearGreys)
	sortByMajor(farGreys)

	local usedGreys = {}
	local pairs = {}
	local slotCounter = 1

	local function assignSide(sideGreens, sideGreys, reverseOrder, isOppositeSide)
		local greensOrdered = {}
		local greysOrdered = {}
		if reverseOrder then
			for i = #sideGreens, 1, -1 do
				table.insert(greensOrdered, sideGreens[i])
			end
			for i = #sideGreys, 1, -1 do
				table.insert(greysOrdered, sideGreys[i])
			end
		else
			greensOrdered = table.clone(sideGreens)
			greysOrdered = table.clone(sideGreys)
		end

		-- Reserve the middle grey on this side so adjacent slots do not consume it.
		local reservedMiddleGrey = greysOrdered[3]

		for idx, green in ipairs(greensOrdered) do
			local grey = nil
			-- Middle slot per side: force exact side-middle mapping first.
			if idx == 3 then
				if reservedMiddleGrey and not usedGreys[reservedMiddleGrey] then
					grey = reservedMiddleGrey
				end
			else
				grey = nearestGreyExcluding(green, sideGreys, usedGreys, reservedMiddleGrey)
			end
			if not grey then
				grey = nearestGrey(green, sideGreys, usedGreys)
			end
			if not grey then
				grey = nearestGrey(green, greyParts, usedGreys)
			end
			if not grey then
				grey = nearestGreyAny(green, greyParts)
			end
			if grey then
				usedGreys[grey] = true
				pairs[slotCounter] = {
					padSlot = slotCounter,
					greenPart = green,
					greyPart = grey,
					isOppositeSide = isOppositeSide == true,
					prompt = nil,
				}
				slotCounter += 1
				if slotCounter > MAX_BASE_DISPLAYS then
					return
				end
			end
		end
	end

	assignSide(nearSide, nearGreys, false, true)
	assignSide(farSide, farGreys, true, false) -- Mirror ordering on opposite side.
	return pairs
end

local function findNearestGreyForGreenInModel(baseModel: Model, greenPart: BasePart): BasePart?
	local bestGrey = nil
	local bestDist = math.huge
	for _, d in ipairs(baseModel:GetDescendants()) do
		if d:IsA("BasePart") and isGreyCandidate(d) then
			local dist = (d.Position - greenPart.Position).Magnitude
			if dist < bestDist then
				bestDist = dist
				bestGrey = d
			end
		end
	end
	return bestGrey
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

local function clearPlacedModel(player: Player, padSlot: number?)
	local bySlot = BaseService._displayModels[player.UserId]
	if not bySlot then return end
	if padSlot then
		local existing = bySlot[padSlot]
		if existing then
			pcall(function() existing:Destroy() end)
			bySlot[padSlot] = nil
		end
		return
	end
	for slot, existing in pairs(bySlot) do
		pcall(function() existing:Destroy() end)
		bySlot[slot] = nil
	end
end

local function placeOnGreySlot(player: Player, padSlot: number, streamerItem): boolean
	local baseInfo = BaseService._bases[player.UserId]
	local displayInfo = baseInfo and baseInfo.displays and baseInfo.displays[padSlot]
	if not displayInfo or not displayInfo.greyPart or not displayInfo.greenPart then return false end

	local streamerId = type(streamerItem) == "table" and streamerItem.id or streamerItem
	local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	if not modelsFolder then return false end
	local template = modelsFolder:FindFirstChild(streamerId)
	if not template then return false end

	clearPlacedModel(player, padSlot)

	local clone = template:Clone()
	clone.Name = "DisplaySlot_" .. tostring(padSlot)
	cleanDisplayModel(clone)

	local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
	if not primary then
		clone:Destroy()
		return false
	end
	clone.PrimaryPart = primary

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

	local grey = displayInfo.greyPart
	-- Middle slots (3 and 8): resolve nearest grey at placement-time to avoid side pairing drift.
	if (padSlot == 3 or padSlot == 8) and baseInfo.baseModel then
		local runtimeGrey = findNearestGreyForGreenInModel(baseInfo.baseModel, displayInfo.greenPart)
		if runtimeGrey then
			grey = runtimeGrey
		end
	end
	local green = displayInfo.greenPart
	local flatTarget = Vector3.new(green.Position.X, grey.Position.Y, green.Position.Z)
	if (flatTarget - grey.Position).Magnitude < 0.05 then
		flatTarget = grey.Position + Vector3.new(0, 0, -1)
	end
	local faceCF = CFrame.lookAt(grey.Position, flatTarget)
	clone:PivotTo(faceCF)

	if rootPart then
		local rootPos = rootPart.Position
		local xzDelta = Vector3.new(grey.Position.X - rootPos.X, 0, grey.Position.Z - rootPos.Z)
		clone:PivotTo(clone:GetPivot() + xzDelta)
	end

	local padTopY = grey.Position.Y + (grey.Size.Y / 2)
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum and rootPart then
		local feetY = rootPart.Position.Y - (rootPart.Size.Y * 0.5 + hum.HipHeight)
		local yLift = padTopY - feetY + 0.03
		clone:PivotTo(clone:GetPivot() + Vector3.new(0, yLift, 0))
	else
		local boxCF, boxSize = clone:GetBoundingBox()
		local bottomY = boxCF.Position.Y - (boxSize.Y / 2)
		local yLift = padTopY - bottomY + 0.03
		clone:PivotTo(clone:GetPivot() + Vector3.new(0, yLift, 0))
	end

	if streamerId == "Cinna" then
		local cinnaCF, cinnaSize = clone:GetBoundingBox()
		local cinnaBottom = cinnaCF.Position.Y - (cinnaSize.Y / 2)
		local minBottom = padTopY + 0.03
		if cinnaBottom < minBottom then
			clone:PivotTo(clone:GetPivot() + Vector3.new(0, minBottom - cinnaBottom, 0))
		end
	end

	-- Middle slots can have asymmetric rigs; force exact X/Z center on pad.
	if padSlot == 3 or padSlot == 8 then
		local boxCF = clone:GetBoundingBox()
		local xzDelta = Vector3.new(grey.Position.X - boxCF.Position.X, 0, grey.Position.Z - boxCF.Position.Z)
		clone:PivotTo(clone:GetPivot() + xzDelta)
	end

	local parent = baseInfo.baseModel or Workspace
	clone.Parent = parent
	if rootPart then
		addDisplayBillboard(clone, rootPart, streamerItem, player)
	end

	-- Attach element VFX/aura if the streamer has an effect
	local effectName = type(streamerItem) == "table" and streamerItem.effect or nil
	if effectName then
		VFXHelper.Attach(clone, effectName)
	end

	getNestedTable(BaseService._displayModels, player.UserId)[padSlot] = clone
	return true
end

local function updatePromptText(player: Player, padSlot: number)
	local baseInfo = BaseService._bases[player.UserId]
	local displayInfo = baseInfo and baseInfo.displays and baseInfo.displays[padSlot]
	if not displayInfo or not displayInfo.prompt then return end
	local data = PlayerData and PlayerData.Get(player)
	local hasPlaced = data and data.equippedPads and data.equippedPads[tostring(padSlot)] ~= nil
	displayInfo.prompt.ActionText = hasPlaced and "Remove Streamer" or "Place Streamer"
	displayInfo.prompt.ObjectText = "Base Slot " .. tostring(padSlot)
end

local function bindCollectTouch(displayInfo, player: Player)
	if not displayInfo or not displayInfo.greenPart then return end
	local padSlot = displayInfo.padSlot
	displayInfo.greenPart.Touched:Connect(function(hit)
		local char = hit.Parent
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local touchPlayer = Players:GetPlayerFromCharacter(char)
		if not touchPlayer or touchPlayer.UserId ~= player.UserId then return end
		tryCollectMoney(touchPlayer, padSlot)
	end)
end

local function bindPrompt(displayInfo, player: Player)
	if not displayInfo.greenPart then return end
	local promptAnchor = Instance.new("Part")
	promptAnchor.Name = "DisplayPromptAnchor_" .. tostring(displayInfo.padSlot)
	promptAnchor.Size = Vector3.new(0.4, 0.4, 0.4)
	promptAnchor.Transparency = 1
	promptAnchor.Anchored = true
	promptAnchor.CanCollide = false
	promptAnchor.CanTouch = false
	promptAnchor.CanQuery = false
	promptAnchor.CFrame = CFrame.new(displayInfo.greenPart.Position + Vector3.new(0, 4.5, 0))
	promptAnchor.Parent = displayInfo.greenPart.Parent
	displayInfo.promptAnchor = promptAnchor

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BaseSingleSlotPrompt"
	prompt:SetAttribute("PadSlot", displayInfo.padSlot)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptAnchor
	displayInfo.prompt = prompt
	updatePromptText(player, displayInfo.padSlot)
	updateMoneyText(player, displayInfo.padSlot)
	bindCollectTouch(displayInfo, player)
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
	local displays = {}
	if baseModel and baseModel:IsA("Model") then
		displays = buildDisplayPairs(baseModel)
	end

	BaseService._bases[player.UserId] = {
		position = slotInfo.position,
		slotIndex = slot,
		baseModel = baseModel,
		displays = displays,
	}
	BaseService._pendingMoney[player.UserId] = {}
	BaseService._nextMoneyTickAt[player.UserId] = {}
	BaseService._displayModels[player.UserId] = {}
	BaseService._collectDebounce[player.UserId] = {}

	if next(displays) ~= nil then
		for padSlot, displayInfo in pairs(displays) do
			bindPrompt(displayInfo, player)
			updatePromptText(player, padSlot)
			updateMoneyText(player, padSlot)
		end
	else
		warn("[BaseService] Could not find green/grey display pairs in BaseSlot_" .. tostring(slot))
	end

	BaseReady:FireClient(player, {
		position = slotInfo.position,
		floorSize = DesignConfig.Base.FloorSize,
	})
end

function BaseService.Init(playerDataModule, potionServiceModule)
	PlayerData = playerDataModule
	PotionService = potionServiceModule

	Players.PlayerAdded:Connect(function(player)
		task.wait(1)
		assignBase(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		local baseInfo = BaseService._bases[userId]
		if baseInfo then
			clearPlacedModel(player)
			for _, displayInfo in pairs(baseInfo.displays or {}) do
				if displayInfo.prompt then
					pcall(function() displayInfo.prompt:Destroy() end)
				end
				if displayInfo.promptAnchor then
					pcall(function() displayInfo.promptAnchor:Destroy() end)
				end
			end
			BaseService._occupiedSlots[baseInfo.slotIndex] = nil
			BaseService._bases[userId] = nil
		end
		BaseService._pendingMoney[userId] = nil
		BaseService._nextMoneyTickAt[userId] = nil
		BaseService._displayModels[userId] = nil
		BaseService._collectDebounce[userId] = nil
		BaseService._equipDebounce[userId] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if not BaseService._bases[player.UserId] then
			task.spawn(function()
				assignBase(player)
			end)
		end
	end

	local EQUIP_DEBOUNCE_SEC = 0.6

	DisplayInteract.OnServerEvent:Connect(function(player, padSlot, heldStreamerId, heldEffect)
		local slot = tonumber(padSlot)
		if not slot or slot < 1 then return end

		-- Per-player per-pad debounce to prevent rapid equip→unequip oscillation
		local userId = player.UserId
		local debounceBySlot = getNestedTable(BaseService._equipDebounce, userId)
		local now = os.clock()
		if debounceBySlot[slot] and (now - debounceBySlot[slot]) < EQUIP_DEBOUNCE_SEC then
			return
		end
		debounceBySlot[slot] = now

		PlayerData.WithLock(player, function()
			local data = PlayerData and PlayerData.Get(player)
			local baseInfo = BaseService._bases[userId]
			local displayInfo = baseInfo and baseInfo.displays and baseInfo.displays[slot]
			if not data or not baseInfo or not displayInfo then return end
			if not displayInfo.greenPart or not displayInfo.greyPart then return end

			local key = tostring(slot)
			local equipped = data.equippedPads[key]
			if equipped then
				local streamerId = type(equipped) == "table" and equipped.id or equipped
				local effect = type(equipped) == "table" and equipped.effect or nil
				local pendingBySlot = getNestedTable(BaseService._pendingMoney, userId)
				local pending = pendingBySlot[slot] or 0
				local ok = PlayerData.UnequipFromPad(player, slot)
				if ok then
					if pending > 0 then
						PlayerData.AddCash(player, math.floor(pending))
					end
					clearPlacedModel(player, slot)
					pendingBySlot[slot] = 0
					getNestedTable(BaseService._nextMoneyTickAt, userId)[slot] = nil
					updateMoneyText(player, slot)
					updatePromptText(player, slot)
					UnequipResult:FireClient(player, {
						success = true,
						padSlot = slot,
						streamerId = streamerId,
						effect = effect,
					})
				end
				return
			end

			if not heldStreamerId or typeof(heldStreamerId) ~= "string" then
				return
			end

			local ok = PlayerData.EquipToPad(player, heldStreamerId, slot, true, heldEffect)
			if ok then
				local item = data.equippedPads[key]
				if placeOnGreySlot(player, slot, item) then
					local pendingBySlot = getNestedTable(BaseService._pendingMoney, userId)
					pendingBySlot[slot] = 0
					getNestedTable(BaseService._nextMoneyTickAt, userId)[slot] = os.clock() + 1
					updateMoneyText(player, slot)
					updatePromptText(player, slot)
					EquipResult:FireClient(player, {
						success = true,
						padSlot = slot,
						streamerId = heldStreamerId,
					})
				end
			else
				EquipResult:FireClient(player, { success = false, reason = "Cannot place here." })
			end
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerData and PlayerData.Get(player)
				local baseInfo = BaseService._bases[player.UserId]
				if not data or not baseInfo then
					continue
				end
				local pendingBySlot = getNestedTable(BaseService._pendingMoney, player.UserId)
				local nextTickBySlot = getNestedTable(BaseService._nextMoneyTickAt, player.UserId)

				for padSlot in pairs(baseInfo.displays or {}) do
					local item = data.equippedPads and data.equippedPads[tostring(padSlot)]
					if not item then
						nextTickBySlot[padSlot] = nil
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

					local nextTick = nextTickBySlot[padSlot]
					if not nextTick then
						nextTickBySlot[padSlot] = now + 1
						nextTick = nextTickBySlot[padSlot]
					end
					if now >= nextTick then
						pendingBySlot[padSlot] = (pendingBySlot[padSlot] or 0) + math.floor(perSec)
						nextTickBySlot[padSlot] = now + 1
						updateMoneyText(player, padSlot)
					end
				end
			end
		end
	end)
end

function BaseService.GetBasePosition(player): Vector3?
	local baseInfo = BaseService._bases[player.UserId]
	return baseInfo and baseInfo.position or nil
end

function BaseService.UpdateBasePads(player)
	if not player then return end
	local baseInfo = BaseService._bases[player.UserId]
	if not baseInfo then return end
	for padSlot in pairs(baseInfo.displays or {}) do
		updatePromptText(player, padSlot)
		updateMoneyText(player, padSlot)
	end
end

function BaseService.ClearDisplaysForRebirth(player)
	if not player then return end
	local userId = player.UserId
	-- Do not clear placed models: streamers stay on pads across rebirth
	BaseService._pendingMoney[userId] = {}
	BaseService._nextMoneyTickAt[userId] = {}
	local baseInfo = BaseService._bases[userId]
	if not baseInfo then return end
	for padSlot in pairs(baseInfo.displays or {}) do
		updateMoneyText(player, padSlot)
		updatePromptText(player, padSlot)
	end
end

return BaseService
