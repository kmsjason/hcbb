-- Get services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Create settings table
local set = {
	AutoAimBat = false, -- Offsets the bat, makes you miss hits though
	AutoHitBat = true, -- Controls if the script will auto hit for you
	WindupDist = 65, -- Change the distance
	HitDist = 16, --How far should the ball be when you swing?
	BallEsp = false, --Shows some really weird stuff on the screen
	YOffset = -12, --Offsets your mouse Y coordinate by this amount (for improved hitting, i.e. getting under the ball)
	OnlyHitInBox = true, --Only swing at strikes
	AimWithMouse = true, --Honestly not sure what this does
	showBoundsAndPrediction = false, --Show ball prediction
	showStrikezone = false, --Whether or not you want the strike zone to be shown at all times
	tweenSpeed = 0, --Affects steady bonus
}

-- Get player related variables
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- Get game related variables
local theBall = nil
local currentPathTable = {}
local predictedPos = Vector3.new()

local Circle = Drawing.new("Circle")
Circle.Visible = true
Circle.Thickness = 2
Circle.Radius = 10
Circle.Color = Color3.new(0, 255, 0)

local PredictionCircle = Drawing.new("Circle")
PredictionCircle.Visible = true
PredictionCircle.Thickness = 2
PredictionCircle.Radius = 30
PredictionCircle.Color = Color3.new(255, 0, 0)

local InsidePredictionCircle = Drawing.new("Circle")
InsidePredictionCircle.Visible = true
InsidePredictionCircle.Thickness = 2
InsidePredictionCircle.Filled = true
InsidePredictionCircle.Transparency = 0.5
InsidePredictionCircle.Radius = 30
InsidePredictionCircle.Color = Color3.new(255, 0, 0)

local predictionPart = Instance.new("Part")
predictionPart.Anchored = true
predictionPart.Size = Vector3.new(0.5, 0.5, 0.5)
predictionPart.BrickColor = BrickColor.new("Really red")
predictionPart.CanCollide = false
predictionPart.Transparency = set.showBoundsAndPrediction and 0.35 or 1
if set.showStrikezone then
	predictionPart.Parent = workspace
end

local function find_constant(func, sig)
	local s = "9271YE7DGWDAHSDBSSS"
	for i, v in ipairs(getconstants(func)) do
		if tostring(v):find(sig) then
			return true
		end
	end
	return false
end

local lastTick = 0
local old

old = hookmetamethod(game, "__namecall", function(self, ...)
	if not checkcaller() and getnamecallmethod() == "Clone" and self and self.Parent and self.Parent.Name == "Ball" then
		if tick() > lastTick + 2 then
			lastTick = tick()
			theBall = self.Parent
		end
	end

	return old(self, ...)
end)

local camera = workspace.CurrentCamera
for i, v in ipairs(getgc(true)) do
	if type(v) == "function" and islclosure(v) and not (syn and is_synapse_function or Krnl and iskrnlclosure)(v) then
		if tostring(getfenv(v).script) == "GoFirst" then
			for a, c in pairs(getupvalues(v)) do
				if
					type(c) == "function"
					and islclosure(c)
					and find_constant(c, "NextNumber")
					and (find_constant(c, "abs") or find_constant(c, "sin"))
				then
					setupvalue(v, a, function()
						return Vector3.new()
					end)
				end
			end
		end
	elseif type(v) == "table" and rawget(v, "GetPos") then
		local old = v.SetPitchtab
		v["SetPitchtab"] = function(self, thingy)
			task.delay(0.1, function()
				if not workspace.Ignore:FindFirstChild("BGUI") then
					return
				end
				local borderBox = workspace.Ignore.BGUI.BlackBoarder
				local closestMag = math.huge
				local newPos = Vector3.new()
				for i = 0, 1, 0.01 do
					local pos = v:GetPos(i, currentPathTable, false, nil, thingy)
					if pos and pos.p ~= Vector3.new(0, 0, 0) then
						local mag = (pos.p - borderBox.Position).Magnitude
						if mag < closestMag then
							closestMag = mag
							newPos = pos.p
						end
					end
				end
				if newPos ~= Vector3.new() then
					PredictionCircle.Visible = set.showBoundsAndPrediction
					InsidePredictionCircle.Visible = set.showBoundsAndPrediction
					local pos, isInScreen = workspace.CurrentCamera:WorldToViewportPoint(newPos)
					PredictionCircle.Position = Vector2.new(pos.x, pos.y)
					InsidePredictionCircle.Position = Vector2.new(pos.x, pos.y)

					--part.Position = newPos
					predictedPos = newPos
				else
					PredictionCircle.Visible = false
					InsidePredictionCircle.Visible = false
				end
			end)
			return old(self, thingy)
		end
	end
end

ReplicatedStorage.RESC.SEVREPBALLTHROW.OnClientEvent:connect(function(_, p219)
	currentPathTable = p219
end)

local toChange = nil
local hasWindedUp = false
local hasSwang = false
local aiming = false

local tween
local completedTween

function actuallyAim()
	if theBall ~= nil and theBall.Parent ~= nil then
		local toAimAt = theBall.Position
		if predictedPos and predictedPos ~= Vector3.new() then
			toAimAt = predictedPos
		end
		local ballPos = camera:WorldToScreenPoint(toAimAt + Vector3.new(0, -theBall.Size.Y / 2, 0))
		local mousePos = camera:WorldToScreenPoint(Mouse.Hit.p)
		local aimAt = Vector2.new()
		local normalPos = Vector2.new(ballPos.X, ballPos.Y)
		if toChange then
			local cursorV2 = camera:WorldToScreenPoint(toChange.Position + Vector3.new(0, toChange.Size.Y / 2, 0))
			local myMousePos = Vector2.new(mousePos.X, mousePos.Y)
			local cursorPos = Vector2.new(cursorV2.X, cursorV2.Y)

			local difference = (myMousePos - cursorPos)
			normalPos = normalPos + difference + Vector2.new(0, set.YOffset)
		end
		aimAt = normalPos

		local shouldAim = false
		if set.AutoHitBat then
			local toMag = workspace.Plates.SwingTarget.Position
			if predictedPos and predictedPos ~= Vector3.new() then
				toMag = predictedPos
			end
			local ballMag = (theBall.Position - toMag).Magnitude
			if ballMag <= set.WindupDist and not hasWindedUp then
				hasWindedUp = true
				task.delay(2, function()
					hasWindedUp = false
				end)
				mouse1click()
			end
			if hasWindedUp and not hasSwang then
				local borderBox = workspace.Ignore.BGUI.BlackBoarder
				local ballPos = camera:WorldToScreenPoint(toAimAt)
				local BorderPositions = {
					TopLeft = camera:WorldToScreenPoint(
						borderBox.Position
							+ Vector3.new(0, borderBox.Size.Y / 2 + 0.2 + 0.25, borderBox.Size.X / 2 + 0.2 + 0.25)
					),
					TopRight = camera:WorldToScreenPoint(
						borderBox.Position
							+ Vector3.new(0, borderBox.Size.Y / 2 + 0.2 + 0.25, -borderBox.Size.X / 2 - 0.2 - 0.25)
					),
					BottomRight = camera:WorldToScreenPoint(
						borderBox.Position
							+ Vector3.new(0, -borderBox.Size.Y / 2 - 0.2 - 0.25, -borderBox.Size.X / 2 - 0.2 - 0.25)
					),
					BottomLeft = camera:WorldToScreenPoint(
						borderBox.Position
							+ Vector3.new(0, -borderBox.Size.Y / 2 - 0.2 - 0.25, borderBox.Size.X / 2 + 0.2 + 0.25)
					),
				}

				local strikezoneParts = {
					TopLeft = Instance.new("Part"),
					TopRight = Instance.new("Part"),
					BottomLeft = Instance.new("Part"),
					BottomRight = Instance.new("Part"),
				}

				for i, v in pairs(strikezoneParts) do
					v.Anchored = true
					v.CanCollide = false
					v.BrickColor = BrickColor.new("Cyan")
					v.Size = Vector3.new(0.25, 0.25, 0.25)
					v.Transparency = set.showBoundsAndPrediction and 0.1 or 1
					if set.showStrikezone then
						v.Parent = workspace
					end
				end

				if set.showBoundsAndPrediction then
					predictionPart.Transparency = 0.35
				else
					predictionPart.Transparency = 1
				end

				strikezoneParts.TopLeft.Position = borderBox.Position
					+ Vector3.new(0, borderBox.Size.Y / 2 + 0.2 + 0.25, borderBox.Size.X / 2 + 0.2 + 0.25)
				strikezoneParts.TopRight.Position = borderBox.Position
					+ Vector3.new(0, borderBox.Size.Y / 2 + 0.2 + 0.25, -borderBox.Size.X / 2 - 0.2 - 0.25)
				strikezoneParts.BottomRight.Position = borderBox.Position
					+ Vector3.new(0, -borderBox.Size.Y / 2 - 0.2, -borderBox.Size.X / 2 - 0.2 - 0.25)
				strikezoneParts.BottomLeft.Position = borderBox.Position
					+ Vector3.new(0, -borderBox.Size.Y / 2 - 0.2, borderBox.Size.X / 2 + 0.2 + 0.25)

				--TopLeft

				if
					not set.OnlyHitInBox
					or (
						ballPos.X <= BorderPositions.TopRight.X
						and ballPos.X >= BorderPositions.TopLeft.X
						and ballPos.Y <= BorderPositions.BottomRight.Y
						and ballPos.Y >= BorderPositions.TopRight.Y
					)
				then
					--Fixed bug that prevented swinging at strikes
					shouldAim = true
					if ballMag <= set.HitDist then
						mouse1click()
						hasSwang = true

						task.delay(2, function()
							hasSwang = false
							theBall = nil
						end)
					end
				end
			end
		end

		if set.AimWithMouse and not aiming and theBall then
			aiming = true
			local CFValue = Instance.new("CFrameValue")
			CFValue.Value = CFrame.new(mousePos.X, mousePos.Y, 0)
			local con = true
			if set.tweenSpeed ~= 0 then
				tween = game:GetService("TweenService"):Create(
					CFValue,
					TweenInfo.new(set.tweenSpeed, Enum.EasingStyle.Quad),
					{ Value = CFrame.new(aimAt.X, aimAt.Y, 0) }
				)
				tween:Play()

				completedTween = tween.Completed:Connect(function()
					con = false
					task.delay(2, function()
						aiming = false
					end)
				end)
				theBall.Changed:Connect(function()
					if theBall and theBall.Parent then
						tween:Pause()

						local toAimAt = theBall.Position
						if predictedPos and predictedPos ~= Vector3.new() then
							toAimAt = predictedPos
						end
						ballPos = camera:WorldToScreenPoint(toAimAt + Vector3.new(0, -theBall.Size.Y / 2, 0))
						mousePos = camera:WorldToScreenPoint(Mouse.Hit.p)
						aimAt = Vector2.new()
						normalPos = Vector2.new(ballPos.X, ballPos.Y)
						if toChange then
							local cursorV2 =
								camera:WorldToScreenPoint(toChange.Position + Vector3.new(0, toChange.Size.Y / 2, 0))
							local myMousePos = Vector2.new(mousePos.X, mousePos.Y)
							local cursorPos = Vector2.new(cursorV2.X, cursorV2.Y)

							local difference = (myMousePos - cursorPos)
							normalPos = normalPos + difference + Vector2.new(0, set.YOffset)
						end
						aimAt = normalPos

						tween = game:GetService("TweenService"):Create(
							CFValue,
							TweenInfo.new(set.tweenSpeed, Enum.EasingStyle.Quad),
							{ Value = CFrame.new(aimAt.X, aimAt.Y, 0) }
						)
						tween:Play()

						completedTween:Disconnect()
						completedTween = tween.Completed:Connect(function()
							con = false
							task.delay(2, function()
								aiming = false
							end)
						end)
					end
				end)
				task.spawn(function()
					while con do
						task.wait()
						mousemoveabs(CFValue.Value.X, CFValue.Value.Y)
					end
				end)
			else
				aiming = false
				mousemoveabs(aimAt.X, aimAt.Y)
				mousemoverel(1, 1)
			end
		end
	end
end

local specialTable = {}
for i, v in ipairs(getgc(true)) do
	if type(v) == "table" and rawget(v, "CENT_VECTOR2_1") then
		specialTable = v
	end
end

local Mouse, Backup = game.Players.LocalPlayer:GetMouse()
Backup = hookmetamethod(
	Mouse,
	"__index",
	newcclosure(function(self, idx)
		if not checkcaller() and idx == "X" and theBall then
			local ballPos = camera:WorldToScreenPoint(theBall.Position)
			local offset = rawget(specialTable, "CENT_VECTOR2_1")

			if offset and set.AutoAimBat then
				return ballPos.X - offset.X
			end
		end
		if not checkcaller() and idx == "Y" and theBall then
			local ballPos = camera:WorldToScreenPoint(theBall.Position)
			local offset = rawget(specialTable, "CENT_VECTOR2_1")
			if offset and set.AutoAimBat then
				return ballPos.Y - offset.Y
			end
		end

		return Backup(self, idx)
	end)
)

local function setToChange(self)
	if self.ClassName == "Part" and self.Name ~= "Shad" and self.Name ~= "Self" and self.Name ~= "HitTracker" then
		self:GetPropertyChangedSignal("CFrame"):Connect(function()
			toChange = self
		end)
	end
end

for i, v in ipairs(workspace.Ignore:GetChildren()) do
	setToChange(v)
end

workspace.Ignore.ChildAdded:Connect(setToChange)

RunService.Heartbeat:connect(function()
	if theBall == nil or theBall.Parent == nil then
		Circle.Visible = false
	else
		actuallyAim()
		Circle.Visible = set.BallEsp
		local pos, isInScreen = workspace.CurrentCamera:WorldToViewportPoint(theBall.Position)
		Circle.Position = Vector2.new(pos.x, pos.y)
	end
end)
