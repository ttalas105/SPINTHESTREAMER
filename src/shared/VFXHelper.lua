--[[
	VFXHelper.lua  (shared — usable from client and server)

	Attaches element VFX/auras to streamer models.

	Each VFX/<Element>/ folder contains a TEST DUMMY model that shows
	exactly where the auras sit on a character. The dummy has a Humanoid
	and standard R15/R6 body parts — those are NOT cloned.  Only the VFX
	objects (ParticleEmitters, Attachments with emitters, Beams, Trails,
	lights, non-body-part meshes, etc.) are extracted and re-parented
	onto the matching body parts of the real streamer model.

	Usage:
	  VFXHelper.Attach(model, "Acid")
	  VFXHelper.Reposition(model)
	  VFXHelper.Remove(model)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXHelper = {}

local vfxFolder = nil

local function getVFXFolder()
	if vfxFolder then return vfxFolder end
	vfxFolder = ReplicatedStorage:FindFirstChild("VFX")
	return vfxFolder
end

-- Standard character rig part names (R15 + R6) — these are NOT VFX
local RIG_PARTS = {
	["HumanoidRootPart"] = true,
	["Head"] = true,
	["UpperTorso"] = true,
	["LowerTorso"] = true,
	["LeftUpperArm"] = true,
	["LeftLowerArm"] = true,
	["LeftHand"] = true,
	["RightUpperArm"] = true,
	["RightLowerArm"] = true,
	["RightHand"] = true,
	["LeftUpperLeg"] = true,
	["LeftLowerLeg"] = true,
	["LeftFoot"] = true,
	["RightUpperLeg"] = true,
	["RightLowerLeg"] = true,
	["RightFoot"] = true,
	-- R6
	["Torso"] = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
}

-- Objects that are part of the character rig infrastructure, not VFX
local RIG_CLASSES = {
	["Humanoid"] = true,
	["Animator"] = true,
	["Motor6D"] = true,
	["Weld"] = true,
	["WeldConstraint"] = true,
	["Shirt"] = true,
	["Pants"] = true,
	["BodyColors"] = true,
	["CharacterMesh"] = true,
	["ShirtGraphic"] = true,
	["Script"] = true,
	["LocalScript"] = true,
	["ModuleScript"] = true,
}

-- VFX classes that we always want to clone
local VFX_CLASSES = {
	["ParticleEmitter"] = true,
	["Beam"] = true,
	["Trail"] = true,
	["Fire"] = true,
	["Smoke"] = true,
	["Sparkles"] = true,
	["PointLight"] = true,
	["SpotLight"] = true,
	["SurfaceLight"] = true,
}

--- Find the test dummy model inside an element folder.
local function findDummy(folder: Folder): Model?
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
			return child
		end
	end
	return nil
end

--- Walk up from a descendant to find which rig body part it sits on.
local function findParentBodyPart(obj: Instance, dummyModel: Model): BasePart?
	local current = obj.Parent
	while current and current ~= dummyModel do
		if current:IsA("BasePart") and RIG_PARTS[current.Name] then
			return current
		end
		current = current.Parent
	end
	return nil
end

--- Find the matching body part on a streamer model by name.
--- Falls back to HumanoidRootPart, then PrimaryPart, then any BasePart.
local function findMatchingPart(model: Model, partName: string): BasePart?
	local match = model:FindFirstChild(partName, true)
	if match and match:IsA("BasePart") then return match end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

--- Check if an Attachment contains any VFX children.
local function attachmentHasVFX(att: Attachment): boolean
	for _, child in ipairs(att:GetChildren()) do
		if VFX_CLASSES[child.ClassName] then return true end
	end
	return false
end

--- Check if a BasePart is a VFX part (not a standard rig part).
local function isVFXPart(part: BasePart, dummyModel: Model): boolean
	if RIG_PARTS[part.Name] then return false end
	if part == dummyModel.PrimaryPart then return false end
	return true
end

------------------------------------------------------------------
-- Attach: extract VFX from the dummy and clone onto streamer
------------------------------------------------------------------

function VFXHelper.Attach(model: Model, effectName: string?)
	if not effectName or effectName == "" then return end

	local root = getVFXFolder()
	if not root then return end

	local effectFolder = root:FindFirstChild(effectName)
	if not effectFolder then return end

	local dummy = findDummy(effectFolder)
	if not dummy then return end

	local dummyRoot = dummy:FindFirstChild("HumanoidRootPart")
		or dummy.PrimaryPart
		or dummy:FindFirstChildWhichIsA("BasePart")
	if not dummyRoot then return end

	-- Tag container so we can remove all VFX later
	local container = Instance.new("Folder")
	container.Name = "_VFX"
	container.Parent = model

	-- Collect VFX objects from the dummy
	for _, desc in ipairs(dummy:GetDescendants()) do
		-- Skip rig infrastructure
		if RIG_CLASSES[desc.ClassName] then continue end

		-- Case 1: Attachment with VFX children — clone entire attachment
		if desc:IsA("Attachment") and attachmentHasVFX(desc) then
			local bodyPart = findParentBodyPart(desc, dummy)
			if bodyPart then
				local target = findMatchingPart(model, bodyPart.Name)
				if target then
					local clone = desc:Clone()
					-- Preserve local CFrame exactly as on the dummy
					clone:SetAttribute("_VFX", true)
					clone.Parent = target
				end
			end
			continue
		end

		-- Case 2: VFX class parented directly to a rig part (no attachment)
		if VFX_CLASSES[desc.ClassName] then
			local parent = desc.Parent
			-- Skip if parent is an Attachment (handled in Case 1)
			if parent and parent:IsA("Attachment") then continue end
			if parent and parent:IsA("BasePart") and RIG_PARTS[parent.Name] then
				local target = findMatchingPart(model, parent.Name)
				if target then
					local clone = desc:Clone()
					clone:SetAttribute("_VFX", true)
					clone.Parent = target
				end
			end
			continue
		end

		-- Case 3: Non-rig BasePart (VFX geometry like glowing orbs, rings, etc.)
		if desc:IsA("BasePart") and isVFXPart(desc, dummy) then
			-- Only process direct children or top-level VFX parts
			-- (skip parts inside nested models that are handled as a group)
			local parentModel = desc.Parent
			if parentModel and parentModel:IsA("Model") and parentModel ~= dummy then
				continue -- will be handled when we process the parent Model
			end

			local offset = dummyRoot.CFrame:ToObjectSpace(desc.CFrame)
			local streamerRoot = model:FindFirstChild("HumanoidRootPart")
				or model.PrimaryPart
				or model:FindFirstChildWhichIsA("BasePart")
			if streamerRoot then
				local clone = desc:Clone()
				clone.Anchored = true
				clone.CanCollide = false
				clone.CanTouch = false
				clone.CanQuery = false
				clone.CFrame = streamerRoot.CFrame * offset
				clone.Parent = container
			end
			continue
		end

		-- Case 4: Non-rig Model inside the dummy (VFX model group, e.g. beam rig)
		if desc:IsA("Model") and desc.Parent == dummy and desc ~= dummy then
			if desc:FindFirstChildOfClass("Humanoid") then continue end -- skip nested dummies
			local descCF = desc:GetPivot()
			local offset = dummyRoot.CFrame:ToObjectSpace(descCF)
			local streamerRoot = model:FindFirstChild("HumanoidRootPart")
				or model.PrimaryPart
				or model:FindFirstChildWhichIsA("BasePart")
			if streamerRoot then
				local clone = desc:Clone()
				clone:PivotTo(streamerRoot.CFrame * offset)
				for _, p in ipairs(clone:GetDescendants()) do
					if p:IsA("BasePart") then
						p.Anchored = true
						p.CanCollide = false
						p.CanTouch = false
						p.CanQuery = false
					end
				end
				clone.Parent = container
			end
		end
	end
end

------------------------------------------------------------------
-- Reposition: move VFX BaseParts/Models to follow moved model
------------------------------------------------------------------

function VFXHelper.Reposition(model: Model)
	local container = model:FindFirstChild("_VFX")
	if not container then return end

	local streamerRoot = model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart")
	if not streamerRoot then return end

	-- We need the original offsets. Store them on first reposition.
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("BasePart") then
			local offset = child:GetAttribute("_VFXOffset")
			if not offset then
				offset = streamerRoot.CFrame:ToObjectSpace(child.CFrame)
				child:SetAttribute("_VFXOffset", offset)
			end
			child.CFrame = streamerRoot.CFrame * offset
		elseif child:IsA("Model") then
			local offset = child:GetAttribute("_VFXOffset")
			if not offset then
				offset = streamerRoot.CFrame:ToObjectSpace(child:GetPivot())
				child:SetAttribute("_VFXOffset", offset)
			end
			child:PivotTo(streamerRoot.CFrame * offset)
		end
	end
end

------------------------------------------------------------------
-- Remove: strip all VFX from a model
------------------------------------------------------------------

function VFXHelper.Remove(model: Model)
	local container = model:FindFirstChild("_VFX")
	if container then
		container:Destroy()
	end
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:GetAttribute("_VFX") then
			desc:Destroy()
		end
	end
end

return VFXHelper
