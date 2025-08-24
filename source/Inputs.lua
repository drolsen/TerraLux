local Corners = require(script.Parent.Corners)
local Strokes = require(script.Parent.Strokes)
local Theme = require(script.Parent.Theme)

local Inputs = {
	label = {},
	stepper = {},
	rowNumber = {}
}


function Inputs.label.make(theme, text, w)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = theme.TextSecondary
	l.Size = UDim2.new(0, w or 120, 1, 0)
	return l
end

function Inputs.stepper.make(theme, width, step, min, max, alignRight, text:nil)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset((width or 56)+16+2, 22)

	if text ~= nil then
		local label = Instance.new("TextLabel")
		label.Text = text
		label.BackgroundTransparency = 1
		label.TextSize = 9
		label.TextColor3 = Color3.new(1, 1, 1)
		label.ZIndex = 5
		label.Size = UDim2.new(0, 45, 1, 0)
		label.Position = UDim2.new(0, 0, 0, 0)
		label.Parent = holder
	end

	local pill = Instance.new("TextBox")
	pill.Size = UDim2.fromOffset(35, 22)
	pill.BackgroundColor3 = Color3.fromRGB(247,248,250)
	pill.TextColor3 = Color3.fromRGB(25,27,32)
	pill.TextXAlignment = Enum.TextXAlignment.Left
	pill.ClearTextOnFocus = false
	pill.Font = Enum.Font.Arial
	pill.TextSize = 14
	pill.Text = ""
	pill.BorderSizePixel = 0
	pill.Position = UDim2.fromOffset(40, 0)
	
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0,8)
	padding.Parent = pill
	Corners.make(pill, 8)
	pill.Parent = holder

	local spin = Instance.new("Frame")
	spin.Name = "Spin"
	spin.Size = UDim2.fromOffset(16, 22)
	spin.Position = UDim2.fromOffset((width or 56)+10, 0)
	spin.BackgroundColor3 = theme.ControlBg
	spin.BorderSizePixel = 0
	Corners.make(spin, 6); 
	Strokes.make(spin, theme.ControlBorder, 1)
	spin.Parent = holder

	local up = Instance.new("TextButton")
	up.Size = UDim2.new(1,0,0,11); up.BackgroundTransparency = 1; up.Text = "?"; up.TextSize = 12
	up.Font = Enum.Font.Gotham; up.TextColor3 = theme.ControlText; up.Parent = spin
	local dn = up:Clone(); dn.Text = "?"; dn.Position = UDim2.fromOffset(0,11); dn.Parent = spin

	local function clamp(v)
		if min ~= nil and v < min then v = min end
		if max ~= nil and v > max then v = max end
		return v
	end
	
	up.MouseButton1Click:Connect(function()
		local n = tonumber(pill.Text) or 0
		n = clamp(n + (step or 1))
		pill.Text = tostring(n); pill:ReleaseFocus()
	end)
	dn.MouseButton1Click:Connect(function()
		local n = tonumber(pill.Text) or 0
		n = clamp(n - (step or 1))
		pill.Text = tostring(n); pill:ReleaseFocus()
	end)

	return holder, pill
end

return Inputs
