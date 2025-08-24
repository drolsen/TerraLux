-- UI (ModuleScript)
-- Controls + functional dropdown list. Safe APIs; no custom methods added to Instances.
local Theme = require(script.Theme)
local UI = {}
local CORNER = 8
function UI.setCornerRadius(px) CORNER = px or CORNER end

-- ===== Utilities =====
local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or CORNER)
	c.Parent = inst
	return c
end
local function stroke(inst)
	local s = Instance.new("UIStroke")
	s.Thickness = 1
	s.Color = Theme.ControlBorder
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end
local function getStroke(frame)
	for _, ch in ipairs(frame:GetChildren()) do
		if ch:IsA("UIStroke") then return ch end
	end
	return nil
end
local function isSelected(frame) return frame:GetAttribute("Selected") == true end

-- ===== Button styling =====
local function styleButton(holder, label, click, enabled, selected)
	holder.Active, click.Active = enabled, enabled
	if not enabled then
		holder.BackgroundColor3 = (holder.Name == "AddBiomeButton") and Theme.ControlBgBlueDisabled or Theme.ControlBgDisabled
		if label then label.TextColor3 = Theme.ControlTextDisabled label.TextTransparency = 0.1 end
	else
		if selected then
			holder.BackgroundColor3 = (holder.Name == "AddBiomeButton") and Theme.ControlBgBlueActive or Theme.ControlBgActive
		else
			holder.BackgroundColor3 = (holder.Name == "AddBiomeButton") and Theme.ControlBgBlue or Theme.ControlBg
		end
		if label then label.TextColor3 = Theme.ControlText label.TextTransparency = 0 end
	end
	holder:SetAttribute("Enabled", enabled)
	holder:SetAttribute("Selected", selected)
end

-- ===== Public APIs =====
function UI.SetButtonEnabled(btnFrame, enabled)
	local label = btnFrame:FindFirstChild("TextLabel")
	local click = btnFrame:FindFirstChild("ClickArea")
	if not click then return end
	styleButton(btnFrame, label and label:IsA("TextLabel") and label or nil, click, enabled and true or false, isSelected(btnFrame))
end
function UI.SetButtonSelected(btnFrame, selected)
	local label = btnFrame:FindFirstChild("TextLabel")
	local click = btnFrame:FindFirstChild("ClickArea")
	if not click then return end
	styleButton(btnFrame, label and label:IsA("TextLabel") and label or nil, click, btnFrame:GetAttribute("Enabled") ~= false, selected and true or false)
end

function UI.SetDropdownText(dropdownFrame, text)
	local label = dropdownFrame:FindFirstChild("Value")
	if label and label:IsA("TextLabel") then label.Text = text or "" end
end
function UI.SetDropdownEnabled(dropdownFrame, enabled)
	local label = dropdownFrame:FindFirstChild("Value")
	local chev  = dropdownFrame:FindFirstChild("Chevron")
	local click = dropdownFrame:FindFirstChild("ClickArea")
	if click and click:IsA("TextButton") then click.Active = enabled and true or false end
	dropdownFrame.Active = enabled and true or false
	if enabled then
		dropdownFrame.BackgroundColor3 = Theme.ControlBg
		if label then label.TextColor3 = Theme.ControlText label.TextTransparency = 0 end
		if chev then chev.TextColor3 = Theme.ControlText chev.TextTransparency = 0 end
	else
		dropdownFrame.BackgroundColor3 = Theme.ControlBgDisabled
		if label then label.TextColor3 = Theme.ControlTextDisabled label.TextTransparency = 0.1 end
		if chev then chev.TextColor3 = Theme.ControlTextDisabled chev.TextTransparency = 0.1 end
	end
	local st = getStroke(dropdownFrame)
	if st then st.Color = Theme.ControlBorder end
	dropdownFrame:SetAttribute("Enabled", enabled and true or false)
end

function UI.SetDropdownOpen(dropdownFrame, open)
	local holder = dropdownFrame:FindFirstChild("ListHolder")
	if holder then holder.Visible = open and true or false end
end

function UI.GetInputText(inputFrame)
	local tb = inputFrame:FindFirstChild("Input")
	return (tb and tb:IsA("TextBox") and tb.Text) or ""
end
function UI.FocusInput(inputFrame)
	local tb = inputFrame:FindFirstChild("Input")
	if tb and tb:IsA("TextBox") then tb:CaptureFocus() end
end

-- ===== Controls =====
function UI.ToolbarButton(props)
	local name     = props.Name or "ToolbarButton"
	local width    = props.Width or 100
	local height   = props.Height or 36
	local text     = props.Text
	local image    = props.Icon
	local disabled = props.Disabled == true
	local backgroundColor = props.BackgroundColor or Theme.ControlBg
	local align    = tostring(props.TextAlign or "Left")

	local holder = Instance.new("Frame")
	holder.Name = name
	holder.Size = UDim2.fromOffset(width, height)
	holder.BackgroundColor3 = backgroundColor
	holder.BorderSizePixel = 0
	corner(holder, CORNER) ; stroke(holder)
	holder:SetAttribute("role", "button")

	local click = Instance.new("TextButton")
	click.Name = "ClickArea"
	click.BackgroundTransparency = 1
	click.Text = ""
	click.AutoButtonColor = false
	click.Size = UDim2.fromScale(1,1)
	click.Parent = holder

	local label
	if text then
		label = Instance.new("TextLabel")
		label.Name = "TextLabel"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 1, 0)
		label.AnchorPoint = Vector2.new(.5, 0)
		label.Position = UDim2.new(0.5, 0)
		label.TextXAlignment = (align == "Center") and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Font = Enum.Font.Gotham
		label.TextSize = 16
		label.TextColor3 = Theme.ControlText
		label.Text = text
		label.Parent = holder
	end

	if image then
		local icon = Instance.new("ImageLabel")
		icon.Name = name.."Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.BackgroundTransparency = 1
		icon.Position = UDim2.new(0.5, 0)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = image
		icon.Size = UDim2.new(0, 23, 1, 0)
		icon.Parent = holder
	end

	holder.MouseEnter:Connect(function()
		if holder:GetAttribute("Enabled") and not isSelected(holder) then
			holder.BackgroundColor3 = (holder.Name == "AddBiomeButton") and Theme.ControlBgBlueActive or Theme.ControlBgHover
		end
	end)
	holder.MouseLeave:Connect(function()
		if holder:GetAttribute("Enabled") and not isSelected(holder) then
			holder.BackgroundColor3 = (holder.Name == "AddBiomeButton") and Theme.ControlBgBlue or Theme.ControlBg
		end
	end)
	click.MouseButton1Down:Connect(function()
		if holder:GetAttribute("Enabled") and not isSelected(holder) then
			holder.BackgroundColor3 = (holder.Name == "AddBiomeButton") and Theme.ControlBgBlueActive or Theme.ControlBgActive
		end
	end)
	click.MouseButton1Up:Connect(function()
		if holder:GetAttribute("Enabled") and not isSelected(holder) then
			holder.BackgroundColor3 = (holder.Name == "AddBiomeButton") and Theme.ControlBgBlueActive or Theme.ControlBgHover
		end
	end)

	styleButton(holder, label, click, not disabled, false)
	return holder
end

function UI.Separator(props)
	local vertical = props.Vertical ~= false
	local length = props.Length or 40
	local f = Instance.new("Frame")
	f.Name = vertical and "SeparatorV" or "SeparatorH"
	f.BackgroundTransparency = 1
	f.Size = vertical and UDim2.fromOffset(8, length) or UDim2.fromOffset(length, 8)

	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BorderSizePixel = 0
	line.BackgroundColor3 = Theme.ToolbarLine
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Parent = f
	line.Position = UDim2.fromScale(0.5, 0.5)
	line.Size = vertical and UDim2.fromOffset(1, length) or UDim2.fromOffset(length, 1)
	return f
end

-- Functional dropdown
function UI.ToolbarDropdown(props)
	local name     = props.Name or "ToolbarDropdown"
	local width    = props.Width or 220
	local height   = props.Height or 36
	local text     = props.Text or "Select"
	local position = props.Position or UDim2.new(0, 0, 0, 0)
	local disabled = props.Disabled == true

	local holder = Instance.new("Frame")
	holder.Name = name
	holder.ZIndex = 80
	holder.Size = UDim2.fromOffset(width, height)
	holder.BackgroundColor3 = Theme.ControlBg
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = false
	holder.Position = position
	corner(holder, CORNER) ; stroke(holder)
	holder:SetAttribute("role", "dropdown")

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	padding.Parent = holder

	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.Text = text
	label.TextColor3 = Theme.ControlText
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Parent = holder
	label.ZIndex = 80

	local chev = Instance.new("TextLabel")
	chev.Name = "Chevron"
	chev.BackgroundTransparency = 1
	chev.Size = UDim2.fromOffset(20, height)
	chev.Position = UDim2.new(1, -15, 0, 0)
	chev.TextXAlignment = Enum.TextXAlignment.Center
	chev.TextYAlignment = Enum.TextYAlignment.Center
	chev.Font = Enum.Font.Gotham
	chev.TextSize = 16
	chev.Text = "?"
	chev.TextColor3 = Theme.ControlText
	chev.Parent = holder
	chev.ZIndex = 80

	-- Click area
	local click = Instance.new("TextButton")
	click.Name = "ClickArea"
	click.BackgroundTransparency = 1
	click.Text = ""
	click.AutoButtonColor = false
	click.Size = UDim2.fromScale(1,1)
	click.ZIndex = 90
	click.Parent = holder

	-- List container (scrollable)
	local listHolder = Instance.new("Frame")
	listHolder.Name = "ListHolder"
	listHolder.Visible = false
	listHolder.ZIndex = 100
	listHolder.BackgroundColor3 = Theme.ControlBg
	listHolder.BorderSizePixel = 0
	listHolder.Position = UDim2.new(0, -10, 1, 4)
	listHolder.Size = UDim2.fromOffset(width, math.max(140, height * 4))
	corner(listHolder, CORNER) ; stroke(listHolder)
	listHolder.Parent = holder

	local listScroll = Instance.new("ScrollingFrame")
	listScroll.Name = "ListScroll"
	listScroll.BackgroundTransparency = 1
	listScroll.BorderSizePixel = 0
	listScroll.CanvasSize = UDim2.new(0,0,0,0)
	listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listScroll.ScrollBarThickness = 6
	listScroll.Size = UDim2.fromScale(1,1)
	listScroll.Parent = listHolder
	listScroll.ZIndex = 101

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = listScroll

	-- Hover visuals for holder only when enabled
	holder.MouseEnter:Connect(function()
		if holder:GetAttribute("Enabled") then holder.BackgroundColor3 = Theme.ControlBgHover end
	end)
	holder.MouseLeave:Connect(function()
		if holder:GetAttribute("Enabled") then holder.BackgroundColor3 = Theme.ControlBg end
	end)

	UI.SetDropdownEnabled(holder, not disabled)
	return holder
end

-- Build/refresh dropdown rows (simple)
function UI.BuildDropdownList(dropdownFrame, items, onSelect)
	local holder = dropdownFrame:FindFirstChild("ListHolder")
	local scroll = holder and holder:FindFirstChild("ListScroll")
	if not (holder and scroll) then return end

	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("TextButton") or ch:IsA("Frame") then ch:Destroy() end
	end

	local ROW_H = 26
	for _, name in ipairs(items) do
		local row = Instance.new("TextButton")
		row.Name = "Item_"..name
		row.BackgroundColor3 = Theme.ControlBg
		row.AutoButtonColor = false
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextYAlignment = Enum.TextYAlignment.Center
		row.Font = Enum.Font.Gotham
		row.TextSize = 14
		row.TextColor3 = Theme.ControlText
		row.Text = "  "..name
		row.Size = UDim2.new(1, -4, 0, ROW_H)
		row.Parent = scroll
		row.ZIndex = 102

		row.MouseEnter:Connect(function() row.BackgroundColor3 = Theme.ControlBgHover end)
		row.MouseLeave:Connect(function() row.BackgroundColor3 = Theme.ControlBg end)
		row.MouseButton1Click:Connect(function()
			if onSelect then onSelect(name) end
		end)
	end

	local count = #items
	local maxHeight = math.min(200, (ROW_H + 2) * math.max(1, count))
	holder.Size = UDim2.fromOffset(math.max(120, dropdownFrame.AbsoluteSize.X), maxHeight)
end

-- Build dropdown rows with a trailing delete (X) button on the right.
function UI.BuildDropdownListWithDelete(dropdownFrame, items, onSelect, onDelete)
	local holder = dropdownFrame:FindFirstChild("ListHolder")
	local scroll = holder and holder:FindFirstChild("ListScroll")
	if not (holder and scroll) then return end

	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("TextButton") or ch:IsA("Frame") then ch:Destroy() end
	end

	local ROW_H = 26
	for _, name in ipairs(items) do
		local row = Instance.new("Frame")
		row.Name = "Item_"..name
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -4, 0, ROW_H)
		row.ZIndex = 102
		row.ClipsDescendants = false
		row.Parent = scroll

		local bg = Instance.new("TextButton")
		bg.Name = "SelectArea"
		bg.Text = "  "..name
		bg.Font = Enum.Font.Gotham
		bg.TextSize = 14
		bg.TextXAlignment = Enum.TextXAlignment.Left
		bg.TextYAlignment = Enum.TextYAlignment.Center
		bg.TextColor3 = Theme.ControlText
		bg.AutoButtonColor = false
		bg.BorderSizePixel = 0
		bg.Size = UDim2.new(1, -34, 1, 0)
		bg.BackgroundColor3 = Theme.ControlBg
		bg.Parent = row
		bg.ZIndex = 102
		bg.MouseEnter:Connect(function() bg.BackgroundColor3 = Theme.ControlBgHover end)
		bg.MouseLeave:Connect(function() bg.BackgroundColor3 = Theme.ControlBg end)
		bg.MouseButton1Click:Connect(function()
			if onSelect then onSelect(name) end
		end)

		local del = Instance.new("TextButton")
		del.Name = "Delete"
		del.Text = "–"
		del.Font = Enum.Font.GothamBold
		del.TextSize = 14
		del.TextColor3 = Color3.fromRGB(240,240,240)
		del.AutoButtonColor = false
		del.BorderSizePixel = 0
		del.Size = UDim2.fromOffset(20, 20)
		del.AnchorPoint = Vector2.new(1,0.5)
		del.Position = UDim2.new(1, 0, 0.5, 0)
		del.BackgroundColor3 = Color3.fromRGB(232, 58, 68)
		del.Parent = row
		del.ZIndex = 200
		corner(del, 4)

		del.MouseEnter:Connect(function() del.BackgroundColor3 = Color3.fromRGB(200, 58, 67) end)
		del.MouseLeave:Connect(function() del.BackgroundColor3 = Color3.fromRGB(232, 58, 68) end)
		del.MouseButton1Click:Connect(function()
			if onDelete then onDelete(name) end
		end)
	end

	local count = #items
	local maxHeight = math.min(200, (ROW_H + 2) * math.max(1, count))
	holder.Size = UDim2.fromOffset(math.max(120, dropdownFrame.AbsoluteSize.X), maxHeight)
end

-- Dropdown-styled text input (with safe long-text behavior)
function UI.ToolbarTextInput(props)
	local name   = props.Name or "ToolbarTextInput"
	local width  = props.Width or 220
	local height = props.Height or 36
	local placeholder = props.Placeholder or ""

	local holder = Instance.new("Frame")
	holder.Name = name
	holder.Size = UDim2.fromOffset(width, height)
	holder.BackgroundColor3 = Theme.ControlBg
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	corner(holder, CORNER) ; stroke(holder)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = holder

	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.BackgroundTransparency = 1
	input.ClearTextOnFocus = false
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.TextYAlignment = Enum.TextYAlignment.Center
	input.Font = Enum.Font.Gotham
	input.TextSize = 16
	input.Text = ""
	input.PlaceholderText = placeholder
	input.PlaceholderColor3 = Theme.ControlTextDisabled
	input.TextColor3 = Theme.ControlText
	input.TextTruncate = Enum.TextTruncate.AtEnd
	input.Size = UDim2.fromScale(1, 1)
	input.Parent = holder

	-- web-like long text: show while focused, ellipsis on blur
	input.Focused:Connect(function() input.TextTruncate = Enum.TextTruncate.None end)
	input.FocusLost:Connect(function() input.TextTruncate = Enum.TextTruncate.AtEnd end)

	holder.MouseEnter:Connect(function() holder.BackgroundColor3 = Theme.ControlBgHover end)
	holder.MouseLeave:Connect(function() holder.BackgroundColor3 = Theme.ControlBg end)

	return holder
end

----------------------------------------------------------------
-- ========== PROPERTY CARDS / ROWS / FIELDS ===========
----------------------------------------------------------------
-- New: opts.OnToggle(card, expanded) for state memory, and opts.Expanded initial.
function UI.PropertyCard(opts)
	local title   = opts.Title or "Card"
	local cardKey = opts.CardKey or title
	local modeTag = opts.ModeTag or "Biome"
	local expanded = (opts.Expanded == true) -- default false when nil
	local onToggle = opts.OnToggle

	local card = Instance.new("Frame")
	card.Name = "Card_" .. cardKey
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -12, 0, 0)
	card.ZIndex = 1
	card:SetAttribute("CardMode", modeTag)
	card:SetAttribute("CardKey", cardKey)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = card
	local st = Instance.new("UIStroke"); st.Thickness = 1; st.Color = Theme.ControlBorder; st.Parent = card

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = Theme.ControlBgHover
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 32)
	header.Position = UDim2.fromOffset(4, 0)
	header.ZIndex = 2
	header.Parent = card
	local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 6); hc.Parent = header

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = header

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamMedium
	titleLbl.TextSize = 14
	titleLbl.TextColor3 = Theme.ControlText
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.AnchorPoint = Vector2.new(0, 0.5)
	titleLbl.Position = UDim2.new(0, 10, 0.5, 0)
	titleLbl.Size = UDim2.new(1, -40, 1, 0)
	titleLbl.Text = title
	titleLbl.ZIndex = 3
	titleLbl.Parent = header

	local chevron = Instance.new("TextButton")
	chevron.Name = "Chevron"
	chevron.BackgroundTransparency = 1
	chevron.AutoButtonColor = false
	chevron.Text = expanded and "?" or "?"
	chevron.Font = Enum.Font.Gotham
	chevron.TextSize = 18
	chevron.TextColor3 = Theme.ControlText
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -8, 0.5, 0)
	chevron.Size = UDim2.fromOffset(20, 20)
	chevron.ZIndex = 3
	chevron.Parent = header

	local headerHit = Instance.new("TextButton")
	headerHit.Name = "HeaderHit"
	headerHit.BackgroundTransparency = 1
	headerHit.AutoButtonColor = false
	headerHit.Text = ""
	headerHit.Size = UDim2.fromScale(1,1)
	headerHit.ZIndex = 4
	headerHit.Parent = header

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 0
	content.BackgroundColor3 = Theme.ControlBg
	content.ClipsDescendants = true	
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Size = UDim2.new(1, 0, 0, 0)
	content.Position = UDim2.fromOffset(4, 0)
	content.ZIndex = 1
	content.Parent = card
	
	local contentPad = Instance.new("UIPadding")
	contentPad.PaddingTop = UDim.new(0, 40); 
	contentPad.PaddingBottom = UDim.new(0, 10)
	contentPad.PaddingLeft = UDim.new(0, 5)
	contentPad.PaddingRight = UDim.new(0, 5)
	contentPad.Parent = content	
	
	local contentCorners = Instance.new("UICorner")
	contentCorners.CornerRadius = UDim.new(0, 10)
	contentCorners.Parent = content		

	local contentList = Instance.new("UIListLayout")
	contentList.FillDirection = Enum.FillDirection.Vertical
	contentList.Padding = UDim.new(0, 6)
	contentList.SortOrder = Enum.SortOrder.LayoutOrder
	contentList.Parent = content

	local function setExpanded(on)
		content.Visible = on
		chevron.Text = on and "?" or "?"
		card:SetAttribute("Expanded", on)
		if onToggle then pcall(onToggle, card, on) end
	end
	setExpanded(expanded)

	chevron.MouseButton1Click:Connect(function() setExpanded(not content.Visible) end)
	headerHit.MouseButton1Click:Connect(function() setExpanded(not content.Visible) end)

	return card, content
end

function UI.PropertyRow(parentContent, labelText, divider, labelOrder)
	local row = Instance.new("Frame")
	row.Name = "Row_" .. (labelText or "Prop")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 30)
	row.ZIndex = 0
	row.Parent = parentContent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Text = labelText or ""
	label.Font = Enum.Font.Gotham
	label.TextSize = 13
	label.TextColor3 = Theme.TextSecondary
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.fromOffset(4, 0)
	label.Size = UDim2.new(0, 132, 1, 0)
	label.LayoutOrder = labelOrder or 1
	label.Parent = row

	local fieldArea = Instance.new("Frame")
	fieldArea.Name = "Fields"
	fieldArea.BackgroundTransparency = 1
	fieldArea.Position = UDim2.new(0, 140, 0, 0)
	fieldArea.Size = UDim2.new(1, -148, 1, 0)
	fieldArea.ZIndex = 0
	label.LayoutOrder = labelOrder or 2
	fieldArea.Parent = row

	local h = Instance.new("UIListLayout")
	h.FillDirection = Enum.FillDirection.Horizontal
	h.HorizontalAlignment = Enum.HorizontalAlignment.Right
	h.VerticalAlignment = Enum.VerticalAlignment.Center
	h.SortOrder = Enum.SortOrder.LayoutOrder
	h.Padding = UDim.new(0, 6)
	h.Parent = fieldArea

	if divider ~= false then 
		local div = Instance.new("Frame")
		div.Name = "RowDivider"
		div.BorderSizePixel = 0
		div.BackgroundColor3 = Theme.ToolbarLine
		div.Size = UDim2.new(1, -8, 0, 1)
		div.Position = UDim2.new(0, 4, 1, 0)
		div.Parent = row		
	end

	return row, fieldArea
end

local INPUT_BG   = Color3.fromRGB(247, 248, 250)
local INPUT_TEXT = Color3.fromRGB(25, 27, 32)

local function makeNumberPill(width)
	local box = Instance.new("TextBox")
	box.Name = "Number"
	box.BackgroundColor3 = INPUT_BG
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Arial
	box.FontFace.Weight = Enum.FontWeight.Regular
	box.TextSize = 14
	box.TextColor3 = INPUT_TEXT
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.Text = ""
	box.Size = UDim2.fromOffset(width or 30, 22)
	local r = Instance.new("UICorner"); r.CornerRadius = UDim.new(0, 8); r.Parent = box
	return box
end

function UI.AddNumberFields(fieldArea, minisArray, width)
	local widths = {}
	if type(width) == "table" then widths = width else
		local w = tonumber(width) or 30
		for _ = 1, #(minisArray or {""}) do table.insert(widths, w) end
	end
	local res = {}
	local labels = minisArray or {""}
	for i, mini in ipairs(labels) do
		if mini ~= "" then
			local m = Instance.new("TextLabel")
			m.Name = "Mini"; m.BackgroundTransparency = 1
			m.Font = Enum.Font.Arial; m.TextSize = 14
			m.FontFace.Weight = Enum.FontWeight.Regular
			m.TextColor3 = Theme.TextSecondary; m.TextXAlignment = Enum.TextXAlignment.Left
			m.Text = mini; m.Size = UDim2.fromOffset(12, 22)
			m.Parent = fieldArea
		end
		local box = makeNumberPill(widths[i] or widths[1] or 30)
		box.Parent = fieldArea
		table.insert(res, box)
	end
	return res
end

function UI.ClearChildrenExcept(frame)
	for _, ch in ipairs(frame:GetChildren()) do
		if not (ch:IsA("UIListLayout") or ch:IsA("UIPadding")) then
			ch:Destroy()
		end
	end
end

return UI
