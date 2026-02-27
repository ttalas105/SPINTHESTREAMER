--[[
	TutorialController.lua
	First-time player tutorial: guides through spinning a crate and placing
	the streamer on a base pad. Only runs once per player.

	Single ScreenGui at DisplayOrder 2 — never blocks other UIs.
	Uses a 3D BillboardGui arrow above the Spin Stall and highlights the
	existing BASE tab button when it's time to go to base.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local UIHelper = require(script.Parent.UIHelper)

local TutorialController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local TutorialComplete = RemoteEvents:WaitForChild("TutorialComplete")

-------------------------------------------------
-- STATE
-------------------------------------------------

local STATES = {
	INACTIVE     = 0,
	GO_TO_SHOP   = 1,
	BUY_CRATE    = 2,
	SPINNING     = 3,
	GO_TO_BASE   = 4,
	PLACE_ON_PAD = 5,
	CELEBRATE    = 6,
	DONE         = 7,
}
TutorialController.STATES = STATES

local currentState = STATES.INACTIVE

local screenGui
local bubbleFrame
local bubbleLabel
local bubbleIcon
local celebrateFrame

local spinStallPos = nil
local basePosition = nil
local receivedStreamerName = nil

-- 3D arrow state
local arrowAnchor = nil

-- BASE button highlight state
local baseHighlightStroke = nil
local baseHighlightTween = nil
local blockedFlashTween = nil
local lastBlockedFlashAt = 0

-- Forward declarations
local setState
local cleanup
local remove3DArrow
local removeBaseHighlight

-------------------------------------------------
-- STYLE CONSTANTS
-------------------------------------------------

local NEON_PINK    = Color3.fromRGB(255, 80, 200)
local NEON_BLUE    = Color3.fromRGB(80, 200, 255)
local NEON_GREEN   = Color3.fromRGB(80, 255, 130)
local NEON_YELLOW  = Color3.fromRGB(255, 240, 80)
local NEON_ORANGE  = Color3.fromRGB(255, 160, 40)
local BUBBLE_BG    = Color3.fromRGB(255, 245, 100)
local BUBBLE_TEXT  = Color3.fromRGB(40, 10, 80)

local RAINBOW = { NEON_GREEN, NEON_YELLOW, NEON_ORANGE, NEON_PINK, Color3.fromRGB(180, 100, 255), NEON_BLUE }
local BLOCKED_FLASH_COOLDOWN = 0.22

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function getStreamerDisplayName(streamerId)
	for _, s in ipairs(Streamers.List) do
		if s.id == streamerId then return s.displayName end
	end
	return streamerId or "Streamer"
end

local function findSpinStallPosition()
	local hub = workspace:FindFirstChild("Hub")
	if not hub then return nil end
	local anchor = hub:FindFirstChild("SpinPromptAnchor")
	if anchor and anchor:IsA("BasePart") then return anchor.Position end
	local stall = hub:FindFirstChild("Stall_Spin")
	if stall and stall:IsA("Model") then
		local primary = stall.PrimaryPart or stall:FindFirstChildWhichIsA("BasePart")
		if primary then return primary.Position end
	end
	return nil
end

-------------------------------------------------
-- BUBBLE (colorful bouncy text prompt at top)
-------------------------------------------------

local bouncingBubble = nil

local function createBubble()
	bubbleFrame = Instance.new("Frame")
	bubbleFrame.Name = "TutorialBubble"
	bubbleFrame.Size = UDim2.new(0, 520, 0, 80)
	bubbleFrame.Position = UDim2.new(0.5, 0, 0, 100)
	bubbleFrame.AnchorPoint = Vector2.new(0.5, 0)
	bubbleFrame.BackgroundColor3 = BUBBLE_BG
	bubbleFrame.BorderSizePixel = 0
	bubbleFrame.Parent = screenGui

	UIHelper.MakeResponsiveModal(bubbleFrame, 520, 80)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 28)
	corner.Parent = bubbleFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = NEON_ORANGE
	stroke.Thickness = 4.5
	stroke.Transparency = 0.05
	stroke.Parent = bubbleFrame

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 130)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 210, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 130)),
	})
	grad.Rotation = 90
	grad.Parent = bubbleFrame

	UIHelper.CreateShadow(bubbleFrame)

	task.spawn(function()
		local ci = 1
		while stroke and stroke.Parent do
			ci = ci % #RAINBOW + 1
			TweenService:Create(stroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine), {
				Color = RAINBOW[ci],
			}):Play()
			task.wait(0.8)
		end
	end)

	bubbleIcon = Instance.new("TextLabel")
	bubbleIcon.Name = "Icon"
	bubbleIcon.Size = UDim2.new(0, 60, 0, 60)
	bubbleIcon.Position = UDim2.new(0, 12, 0.5, 0)
	bubbleIcon.AnchorPoint = Vector2.new(0, 0.5)
	bubbleIcon.BackgroundTransparency = 1
	bubbleIcon.TextScaled = true
	bubbleIcon.Font = Enum.Font.FredokaOne
	bubbleIcon.TextColor3 = Color3.new(1, 1, 1)
	bubbleIcon.Text = ""
	bubbleIcon.Parent = bubbleFrame

	bubbleLabel = Instance.new("TextLabel")
	bubbleLabel.Name = "Message"
	bubbleLabel.Size = UDim2.new(1, -86, 1, -12)
	bubbleLabel.Position = UDim2.new(0, 76, 0, 6)
	bubbleLabel.BackgroundTransparency = 1
	bubbleLabel.Font = Enum.Font.FredokaOne
	bubbleLabel.TextSize = 24
	bubbleLabel.TextColor3 = BUBBLE_TEXT
	bubbleLabel.TextWrapped = true
	bubbleLabel.TextXAlignment = Enum.TextXAlignment.Left
	bubbleLabel.Text = ""
	bubbleLabel.Parent = bubbleFrame

	bubbleFrame.Visible = false
end

local function showBubble(icon, text)
	bubbleIcon.Text = icon
	bubbleLabel.Text = text
	bubbleFrame.Visible = true
	UIHelper.ScaleIn(bubbleFrame, 0.35)

	if bouncingBubble then bouncingBubble:Cancel() end
	local up = TweenService:Create(bubbleFrame, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = UDim2.new(0.5, 0, 0, 108),
	})
	up:Play()
	bouncingBubble = up
end

local function hideBubble()
	if bouncingBubble then bouncingBubble:Cancel(); bouncingBubble = nil end
	if bubbleFrame then bubbleFrame.Visible = false end
end

-------------------------------------------------
-- 3D BILLBOARD ARROW (bounces above the target)
-------------------------------------------------

remove3DArrow = function()
	if arrowAnchor then
		arrowAnchor:Destroy()
		arrowAnchor = nil
	end
end

local function create3DArrow(worldPos)
	remove3DArrow()

	local part = Instance.new("Part")
	part.Name = "TutorialArrowAnchor"
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.Anchored = true
	part.Position = worldPos + Vector3.new(0, 12, 0)
	part.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TutorialArrowBB"
	billboard.Size = UDim2.new(0, 120, 0, 120)
	billboard.AlwaysOnTop = true
	billboard.Active = false
	billboard.Parent = part

	local arrowLabel = Instance.new("TextLabel")
	arrowLabel.Size = UDim2.new(1, 0, 1, 0)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Text = "\u{2B07}"
	arrowLabel.TextScaled = true
	arrowLabel.Font = Enum.Font.FredokaOne
	arrowLabel.TextColor3 = NEON_GREEN
	arrowLabel.Parent = billboard

	local arrowStroke = Instance.new("UIStroke")
	arrowStroke.Color = Color3.fromRGB(0, 60, 20)
	arrowStroke.Thickness = 3
	arrowStroke.Parent = arrowLabel

	-- Bounce up and down
	TweenService:Create(part, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = worldPos + Vector3.new(0, 14, 0),
	}):Play()

	-- Rainbow cycle
	task.spawn(function()
		local ci = 1
		while arrowLabel and arrowLabel.Parent do
			ci = ci % #RAINBOW + 1
			TweenService:Create(arrowLabel, TweenInfo.new(0.7, Enum.EasingStyle.Sine), {
				TextColor3 = RAINBOW[ci],
			}):Play()
			task.wait(0.7)
		end
	end)

	-- Glowing ring on the ground — raycast down to floor while ignoring tutorial/shop helpers
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	local ignore = { part }
	local hub = workspace:FindFirstChild("Hub")
	if hub then
		local spinAnchor = hub:FindFirstChild("SpinPromptAnchor")
		local spinStall = hub:FindFirstChild("Stall_Spin")
		local spinSign = hub:FindFirstChild("Sign_Spin")
		if spinAnchor then table.insert(ignore, spinAnchor) end
		if spinStall then table.insert(ignore, spinStall) end
		if spinSign then table.insert(ignore, spinSign) end
	end
	rayParams.FilterDescendantsInstances = ignore

	local rayOrigin = Vector3.new(worldPos.X, math.max(worldPos.Y + 80, 120), worldPos.Z)
	local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -300, 0), rayParams)
	local groundY = rayResult and rayResult.Position.Y or (worldPos.Y - 1)
	local ringPos = Vector3.new(worldPos.X, groundY + 0.08, worldPos.Z)

	local ring = Instance.new("Part")
	ring.Name = "TutorialRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 10, 10)
	ring.CFrame = CFrame.new(ringPos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = NEON_GREEN
	ring.Transparency = 0.4
	ring.Parent = part

	task.spawn(function()
		while ring and ring.Parent do
			TweenService:Create(ring, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Transparency = 0.7,
			}):Play()
			task.wait(1)
			if not ring or not ring.Parent then break end
			TweenService:Create(ring, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Transparency = 0.3,
			}):Play()
			task.wait(1)
		end
	end)

	arrowAnchor = part
end

-------------------------------------------------
-- BASE BUTTON HIGHLIGHT
-- Finds the existing Tab_BASE button and adds a
-- pulsing neon stroke to draw attention to it.
-------------------------------------------------

local function highlightBaseButton()
	removeBaseHighlight()

	local topNavGui = playerGui:FindFirstChild("TopNavGui")
	if not topNavGui then return end
	local container = topNavGui:FindFirstChild("TopNavContainer")
	if not container then return end
	local baseBtn = container:FindFirstChild("Tab_BASE")
	if not baseBtn then return end

	baseHighlightStroke = Instance.new("UIStroke")
	baseHighlightStroke.Name = "TutorialHighlight"
	baseHighlightStroke.Color = NEON_GREEN
	baseHighlightStroke.Thickness = 5
	baseHighlightStroke.Transparency = 0
	baseHighlightStroke.Parent = baseBtn

	-- Rainbow pulse on the highlight stroke
	task.spawn(function()
		local ci = 1
		while baseHighlightStroke and baseHighlightStroke.Parent do
			ci = ci % #RAINBOW + 1
			TweenService:Create(baseHighlightStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine), {
				Color = RAINBOW[ci],
			}):Play()
			task.wait(0.6)
		end
	end)

	-- Pulsing size
	baseHighlightTween = TweenService:Create(baseBtn, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Size = UDim2.new(0, 145, 0, 50),
	})
	baseHighlightTween:Play()
end

removeBaseHighlight = function()
	if baseHighlightTween then
		baseHighlightTween:Cancel()
		baseHighlightTween = nil
	end
	if baseHighlightStroke then
		-- Restore the button's original size
		local btn = baseHighlightStroke.Parent
		if btn then
			btn.Size = UDim2.new(0, 130, 0, 44)
		end
		baseHighlightStroke:Destroy()
		baseHighlightStroke = nil
	end
end

-------------------------------------------------
-- CELEBRATION
-------------------------------------------------

local function createCelebration()
	celebrateFrame = Instance.new("Frame")
	celebrateFrame.Name = "TutorialCelebrate"
	celebrateFrame.Size = UDim2.new(0, 500, 0, 200)
	celebrateFrame.Position = UDim2.new(0.5, 0, 0.4, 0)
	celebrateFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	celebrateFrame.BackgroundColor3 = Color3.fromRGB(255, 240, 100)
	celebrateFrame.BorderSizePixel = 0
	celebrateFrame.Visible = false
	celebrateFrame.Parent = screenGui

	UIHelper.MakeResponsiveModal(celebrateFrame, 500, 200)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 30)
	corner.Parent = celebrateFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = NEON_PINK
	stroke.Thickness = 5
	stroke.Transparency = 0.1
	stroke.Parent = celebrateFrame

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 100)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 240, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 100)),
	})
	grad.Rotation = 90
	grad.Parent = celebrateFrame

	UIHelper.CreateShadow(celebrateFrame)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Position = UDim2.new(0.5, 0, 0, 20)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "\u{1F389} TUTORIAL COMPLETE! \u{1F389}"
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = Color3.fromRGB(60, 10, 100)
	title.Parent = celebrateFrame

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(255, 200, 50)
	titleStroke.Thickness = 2
	titleStroke.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(0.9, 0, 0, 50)
	sub.Position = UDim2.new(0.5, 0, 0, 90)
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.BackgroundTransparency = 1
	sub.Text = "You're ready to play!\nSpin crates, collect streamers, and build your empire!"
	sub.TextScaled = true
	sub.Font = Enum.Font.FredokaOne
	sub.TextColor3 = Color3.fromRGB(80, 40, 120)
	sub.TextWrapped = true
	sub.Parent = celebrateFrame
end

local function showCelebration()
	celebrateFrame.Visible = true
	UIHelper.ScaleIn(celebrateFrame, 0.4)
	UIHelper.CameraShake(0.5, 0.3)

	local confettiEmojis = { "\u{2728}", "\u{1F389}", "\u{1F38A}", "\u{2B50}", "\u{1F31F}", "\u{1F4AB}" }
	for _ = 1, 20 do
		local c = Instance.new("TextLabel")
		c.Size = UDim2.new(0, 40, 0, 40)
		c.Position = UDim2.new(math.random() * 0.8 + 0.1, 0, -0.05, 0)
		c.BackgroundTransparency = 1
		c.Text = confettiEmojis[math.random(#confettiEmojis)]
		c.TextScaled = true
		c.Font = Enum.Font.FredokaOne
		c.TextColor3 = RAINBOW[math.random(#RAINBOW)]
		c.Rotation = math.random(-30, 30)
		c.Parent = screenGui

		local endY = 0.9 + math.random() * 0.2
		local dur = 1.5 + math.random() * 1.5
		TweenService:Create(c, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(c.Position.X.Scale + (math.random() - 0.5) * 0.3, 0, endY, 0),
			Rotation = math.random(-180, 180),
		}):Play()
		task.delay(dur + 0.2, function()
			c:Destroy()
		end)
	end

	task.delay(4.5, function()
		if celebrateFrame then
			UIHelper.ScaleOut(celebrateFrame, 0.3)
		end
		task.delay(0.4, function()
			currentState = STATES.DONE
			cleanup()
		end)
	end)
end

-------------------------------------------------
-- STATE MACHINE
-------------------------------------------------

setState = function(newState)
	currentState = newState

	if newState == STATES.GO_TO_SHOP then
		spinStallPos = findSpinStallPosition()
		if spinStallPos then
			create3DArrow(spinStallPos)
		end
		showBubble("\u{1F3AA}", "Go to the Spin Shop and open a crate!")

	elseif newState == STATES.BUY_CRATE then
		remove3DArrow()
		showBubble("\u{1F4E6}", "Buy Crate 1 to get your first streamer!")

	elseif newState == STATES.SPINNING then
		showBubble("\u{1F3B0}", "Watch the spin! Who will you get?")

	elseif newState == STATES.GO_TO_BASE then
		remove3DArrow()
		local name = receivedStreamerName or "your streamer"
		showBubble("\u{1F3E0}", "Click the BASE button to go place " .. name .. "!")
		highlightBaseButton()

	elseif newState == STATES.PLACE_ON_PAD then
		removeBaseHighlight()
		hideBubble()
		local name = receivedStreamerName or "your streamer"
		showBubble("\u{1F449}", "Select " .. name .. " from your inventory and tap a pad!")

	elseif newState == STATES.CELEBRATE then
		hideBubble()
		remove3DArrow()
		removeBaseHighlight()
		TutorialComplete:FireServer()
		showCelebration()

	elseif newState == STATES.DONE then
		cleanup()
	end
end

-------------------------------------------------
-- CLEANUP
-------------------------------------------------

cleanup = function()
	remove3DArrow()
	removeBaseHighlight()
	if screenGui then screenGui:Destroy(); screenGui = nil end
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

function TutorialController.Init()
	screenGui = UIHelper.CreateScreenGui("TutorialGui", 2)
	screenGui.Parent = playerGui

	createBubble()
	createCelebration()
end

function TutorialController.ShouldStart(data)
	if data.tutorialComplete ~= false then
		return false
	end
	local hasItems = data.inventory and #data.inventory > 0
	local hasCollection = data.collection and next(data.collection) ~= nil
	local hasRebirths = (data.rebirthCount or 0) > 0
	if hasItems or hasCollection or hasRebirths then
		return false
	end
	return true
end

function TutorialController.Start()
	if currentState ~= STATES.INACTIVE then return end
	setState(STATES.GO_TO_SHOP)
end

function TutorialController.IsActive()
	return currentState ~= STATES.INACTIVE and currentState ~= STATES.DONE
end

function TutorialController.GetState()
	return currentState
end

function TutorialController.OnSpinStandOpened()
	if currentState == STATES.GO_TO_SHOP then
		setState(STATES.BUY_CRATE)
	end
end

function TutorialController.OnSpinStarted()
	if currentState == STATES.BUY_CRATE then
		setState(STATES.SPINNING)
	end
end

function TutorialController.OnSpinResult(data)
	if currentState == STATES.SPINNING or currentState == STATES.BUY_CRATE then
		if data.streamerId then
			receivedStreamerName = getStreamerDisplayName(data.streamerId)
		end
		if currentState == STATES.BUY_CRATE then
			setState(STATES.SPINNING)
		end
		task.delay(3, function()
			if currentState == STATES.SPINNING then
				setState(STATES.GO_TO_BASE)
			end
		end)
	end
end

function TutorialController.OnEquipResult(data)
	if currentState == STATES.PLACE_ON_PAD and data and data.success then
		setState(STATES.CELEBRATE)
	end
end

function TutorialController.OnBaseReady(data)
	if data and data.position then
		basePosition = data.position
	end
end

function TutorialController.OnTabChanged(tabName)
	if currentState == STATES.GO_TO_BASE and tabName == "BASE" then
		removeBaseHighlight()
		setState(STATES.PLACE_ON_PAD)
	end
end

function TutorialController.ForceComplete()
	if currentState == STATES.DONE or currentState == STATES.INACTIVE then return end
	hideBubble()
	remove3DArrow()
	removeBaseHighlight()
	TutorialComplete:FireServer()
	currentState = STATES.DONE
	cleanup()
end

function TutorialController.OnBlockedMainInput()
	if not TutorialController.IsActive() then return end
	local now = os.clock()
	if (now - lastBlockedFlashAt) < BLOCKED_FLASH_COOLDOWN then return end
	lastBlockedFlashAt = now

	if blockedFlashTween then
		blockedFlashTween:Cancel()
		blockedFlashTween = nil
	end

	if bubbleFrame and bubbleFrame.Visible then
		local originalColor = bubbleFrame.BackgroundColor3
		local originalRotation = bubbleFrame.Rotation
		local originalSize = bubbleFrame.Size

		blockedFlashTween = TweenService:Create(bubbleFrame, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = Color3.fromRGB(255, 255, 170),
			Rotation = 2,
			Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset + 14, originalSize.Y.Scale, originalSize.Y.Offset + 4),
		})
		blockedFlashTween:Play()
		blockedFlashTween.Completed:Connect(function()
			TweenService:Create(bubbleFrame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = originalColor,
				Rotation = -2,
				Size = originalSize,
			}):Play()
			task.delay(0.12, function()
				if bubbleFrame then
					TweenService:Create(bubbleFrame, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Rotation = originalRotation,
					}):Play()
				end
			end)
		end)
	elseif baseHighlightStroke and baseHighlightStroke.Parent then
		local btn = baseHighlightStroke.Parent
		TweenService:Create(baseHighlightStroke, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Thickness = 8,
			Transparency = 0,
		}):Play()
		TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Rotation = 2,
		}):Play()
		task.delay(0.1, function()
			if baseHighlightStroke and baseHighlightStroke.Parent then
				TweenService:Create(baseHighlightStroke, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					Thickness = 5,
					Transparency = 0.2,
				}):Play()
			end
			if btn and btn.Parent then
				TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Rotation = 0,
				}):Play()
			end
		end)
	end
end

return TutorialController
