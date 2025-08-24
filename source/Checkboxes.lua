local Corners = require(script.Parent.Corners)
local Checkbox = {}

function Checkbox.make(theme, initial, onToggle)
	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(20,20)
	box.BackgroundColor3 = Color3.fromRGB(255,255,255)
	box.BorderSizePixel = 0
	Corners.make(box, 4)
	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1,1)
	mark.TextXAlignment = Enum.TextXAlignment.Center
	mark.TextYAlignment = Enum.TextYAlignment.Center
	mark.Font = Enum.Font.Gotham
	mark.TextSize = 16
	mark.TextColor3 = Color3.fromRGB(30,30,30)
	mark.Text = initial and "?" or ""
	mark.Parent = box
	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1,1)
	hit.AutoButtonColor = false
	hit.Text = ""
	hit.Parent = box
	hit.MouseButton1Click:Connect(function()
		initial = not initial
		mark.Text = initial and "?" or ""
		if onToggle then onToggle(initial) end
	end)
	return box, function(v)
		initial = (v and true or false)
		mark.Text = initial and "?" or ""
	end
end

return Checkbox
