-- Minimal single-slot prompt interaction.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local SlotPadController = {}
local player = Players.LocalPlayer
local DisplayInteract = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("DisplayInteract")
local TOUCH_SOUND_ID = "rbxassetid://7112275565"

local HoldController = nil
local wiredGreenParts = {}
local myBasePosition = nil
local cachedTouchSound = nil

local function getTouchSound()
	if cachedTouchSound and cachedTouchSound.Parent then
		return cachedTouchSound
	end
	for _, child in ipairs(SoundService:GetChildren()) do
		if child:IsA("Sound") and child.SoundId == TOUCH_SOUND_ID then
			cachedTouchSound = child
			return child
		end
	end
	return nil
end

local function isGreenCollectPart(part: BasePart): boolean
	local c = part.Color
	return part.Material == Enum.Material.Neon
		and c.G > 0.6 and c.G > c.R and c.G > c.B
		and part.Size.Y <= 1
end

local function wireGreenTouch(part)
	if wiredGreenParts[part] then return end
	wiredGreenParts[part] = true
	local isInside = false

	part.Touched:Connect(function(hit)
		local char = player.Character
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		if hit ~= root then return end
		-- Only play for the active green box while a streamer is displayed.
		local gui = part:FindFirstChild("MoneyCounterGui")
		local label = gui and gui:FindFirstChild("MoneyLabel")
		local hasMoneyToCollect = false
		if label and label:IsA("TextLabel") and label.Visible then
			local raw = label.Text or ""
			local digits = raw:gsub("[^%d]", "")
			local amount = tonumber(digits) or 0
			hasMoneyToCollect = amount > 0
		end
		if not hasMoneyToCollect then
			return
		end
		if isInside then return end
		isInside = true
		local sfx = getTouchSound()
		if sfx then
			SoundService:PlayLocalSound(sfx)
		end
	end)

	part.TouchEnded:Connect(function(hit)
		local char = player.Character
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		if hit ~= root then return end
		isInside = false
	end)
end

local function scanAndWire()
	local playerBases = Workspace:FindFirstChild("PlayerBases")
	if not playerBases then return end

	for _, inst in ipairs(playerBases:GetDescendants()) do
		if inst:IsA("BasePart") and isGreenCollectPart(inst) then
			if myBasePosition then
				-- only wire parts near my assigned base
				if (inst.Position - myBasePosition).Magnitude <= 80 then
					wireGreenTouch(inst)
				end
			end
		end
	end
end

function SlotPadController.Init(_holdCtrl, _inventoryCtrl)
	HoldController = _holdCtrl
	ProximityPromptService.PromptTriggered:Connect(function(prompt, _inputType)
		if not prompt or prompt.Name ~= "BaseSingleSlotPrompt" then return end
		local padSlot = tonumber(prompt:GetAttribute("PadSlot")) or 1
		local heldId, heldEffect = nil, nil
		if HoldController and HoldController.IsHolding() then
			heldId, heldEffect = HoldController.GetHeld()
		end
		DisplayInteract:FireServer(padSlot, heldId, heldEffect)
	end)
	task.defer(scanAndWire)
	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") and isGreenCollectPart(inst) and myBasePosition then
			if (inst.Position - myBasePosition).Magnitude <= 80 then
				wireGreenTouch(inst)
			end
		end
	end)
end

function SlotPadController.SetBasePosition(pos)
	myBasePosition = pos
	scanAndWire()
end

function SlotPadController.Refresh(_data)
	-- Display state is tracked per-slot on the server.
end

return SlotPadController
