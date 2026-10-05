--!strict
-- One colour/font/animation vocabulary for the whole UI.

return table.freeze({
	Primary = Color3.fromRGB(255, 170, 40), -- warm orange: main actions
	Accent = Color3.fromRGB(80, 170, 255), -- sky blue: secondary actions
	Success = Color3.fromRGB(60, 200, 110),
	Danger = Color3.fromRGB(235, 70, 80),
	Panel = Color3.fromRGB(28, 30, 42),
	PanelLight = Color3.fromRGB(48, 52, 70),
	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(175, 180, 200),
	Stroke = Color3.fromRGB(10, 10, 18),

	Font = Enum.Font.FredokaOne,
	BodyFont = Enum.Font.BuilderSansBold,

	FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	BOUNCY = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
})
