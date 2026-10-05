--!strict
-- Small helpers for building Scale-based, mobile-friendly UI in code.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Kit = {}

-- Creates an instance, applies props, parents children.
function Kit.new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function Kit.corner(scale: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(scale or 0.2, 0) })
end

function Kit.stroke(thickness: number?, color: Color3?): UIStroke
	return Kit.new("UIStroke", {
		Thickness = thickness or 2,
		Color = color or Theme.Stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Kit.textSize(max: number, min: number?): UITextSizeConstraint
	return Kit.new("UITextSizeConstraint", { MaxTextSize = max, MinTextSize = min or 8 })
end

function Kit.aspect(ratio: number): UIAspectRatioConstraint
	return Kit.new("UIAspectRatioConstraint", { AspectRatio = ratio })
end

function Kit.padding(scale: number): UIPadding
	local u = UDim.new(scale, 0)
	return Kit.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Kit.label(text: string, props: { [string]: any }?): TextLabel
	local p: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = text,
		TextColor3 = Theme.Text,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	}
	for k, v in props or {} do
		p[k] = v
	end
	return Kit.new(
		"TextLabel",
		p,
		{ Kit.textSize(36), Kit.new("UIStroke", { Thickness = 1.5, Color = Theme.Stroke }) }
	)
end

function Kit.panel(props: { [string]: any }): Frame
	local p: { [string]: any } = { BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.05 }
	for k, v in props do
		p[k] = v
	end
	return Kit.new("Frame", p, { Kit.corner(0.06), Kit.stroke(3) })
end

local clickSound = Kit.new("Sound", { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4 })
clickSound.Parent = SoundService

local popping: { [GuiObject]: Tween } = {}

-- Scale pop on press; every button gets this plus a click sound.
function Kit.pop(target: GuiObject)
	local scale = target:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = target })
	local live = popping[target]
	if live then
		live:Cancel()
	end
	scale.Scale = 0.9
	local tween = TweenService:Create(scale, Theme.BOUNCY, { Scale = 1 })
	popping[target] = tween
	tween:Play()
	clickSound.PlaybackSpeed = 0.95 + math.random() * 0.1
	SoundService:PlayLocalSound(clickSound)
end

function Kit.button(text: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
	local p: { [string]: any } = {
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Font = Theme.Font,
		Text = text,
		TextColor3 = Theme.Text,
		TextScaled = true,
	}
	for k, v in props or {} do
		p[k] = v
	end
	local button: TextButton = Kit.new("TextButton", p, {
		Kit.corner(0.25),
		Kit.stroke(2.5),
		Kit.textSize(28),
		Kit.padding(0.12),
	})
	button.Activated:Connect(function()
		if button.Active then
			Kit.pop(button)
			onClick()
		end
	end)
	return button
end

-- Disabled buttons are desaturated and ignore presses.
function Kit.setEnabled(button: GuiButton, enabled: boolean, color: Color3)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then color else Color3.fromRGB(90, 92, 105)
end

-- Fade/scale a panel in or out.
function Kit.show(panel: GuiObject, visible: boolean)
	local scale = panel:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = panel })
	if visible then
		panel.Visible = true
		scale.Scale = 0.85
		TweenService:Create(scale, Theme.BOUNCY, { Scale = 1 }):Play()
	else
		panel.Visible = false
	end
end

function Kit.formatMs(ms: number): string
	local minutes = ms // 60000
	local seconds = (ms % 60000) / 1000
	return string.format("%d:%06.3f", minutes, seconds)
end

return Kit
