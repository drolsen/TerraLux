-- Modules/ModalColorPicker.lua
-- Modal overlay + embedded ColorPicker (HSV/RGB/HEX) with draggable handles.
-- Public API:
--   Modal.Show(parent: Instance, opts?: {
--     title: string?, size: UDim2?, color: Color3?,
--     okText: string?, cancelText: string?,
--     onConfirm: (Color3)->()?, onCancel: (() -> ())?
--   })
-- Returns a Modal object with: Close(cancelled:boolean?)

local UIS        = game:GetService("UserInputService")
local RS         = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

--------------------------------------------------------------------------------
-- Internal ColorPicker
--------------------------------------------------------------------------------
local ColorPicker = {}
ColorPicker.__index = ColorPicker

-- ------------------------------------------------------------------------------
-- Utils
-- ------------------------------------------------------------------------------
local function clamp01(x) return math.clamp(x, 0, 1) end

local function colorToHex(c: Color3)
	local r = math.floor(c.R * 255 + 0.5)
	local g = math.floor(c.G * 255 + 0.5)
	local b = math.floor(c.B * 255 + 0.5)
	return string.format("#%02X%02X%02X", r, g, b)
end

local function hexToColor(s: string?)
	if not s then return nil end
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	if s:sub(1,1) == "#" then s = s:sub(2) end
	if #s == 3 then
		-- #FA3 -> #FFAA33
		s = s:sub(1,1):rep(2)..s:sub(2,2):rep(2)..s:sub(3,3):rep(2)
	end
	if #s ~= 6 then return nil end
	local r = tonumber(s:sub(1,2),16)
	local g = tonumber(s:sub(3,4),16)
	local b = tonumber(s:sub(5,6),16)
	if not r or not g or not b then return nil end
	return Color3.fromRGB(r,g,b)
end

local function hueSequence()
	local CSK = ColorSequenceKeypoint.new
	return ColorSequence.new({
		CSK(0.00, Color3.fromHSV(0/6, 1, 1)),
		CSK(0.17, Color3.fromHSV(1/6, 1, 1)),
		CSK(0.33, Color3.fromHSV(2/6, 1, 1)),
		CSK(0.50, Color3.fromHSV(3/6, 1, 1)),
		CSK(0.67, Color3.fromHSV(4/6, 1, 1)),
		CSK(0.83, Color3.fromHSV(5/6, 1, 1)),
		CSK(1.00, Color3.fromHSV(1,   1, 1)),
	})
end

-- Small factory for labeled numeric field with ?/? steppers
local function makeNumberField(parent: Instance, labelText: string, minV: number, maxV: number, width: number?)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 24)
	row.ZIndex = 1004
	row.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(0, 46, 1, 0)
	lbl.Text = labelText
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 12
	lbl.TextColor3 = Color3.fromRGB(225,227,234)
	lbl.ZIndex = 1004
	lbl.Parent = row

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, width or 54, 1, 0)
	box.Position = UDim2.new(0, 48, 0, 0)
	box.BackgroundColor3 = Color3.fromRGB(44,46,53)
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.TextSize = 12
	box.TextColor3 = Color3.fromRGB(225,227,234)
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Text = "0"
	box.ZIndex = 1004
	box.Parent = row
	local c1 = Instance.new("UICorner");  c1.CornerRadius = UDim.new(0,6); c1.Parent = box
	local s1 = Instance.new("UIStroke");  s1.Color = Color3.fromRGB(55,57,65); s1.Thickness = 1; s1.Parent = box
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,8); pad.Parent = box

	local up = Instance.new("TextButton")
	up.Size = UDim2.new(0, 18, 0, 11)
	up.Position = UDim2.new(0, (width or 54) + 52, 0, 0)
	up.BackgroundColor3 = Color3.fromRGB(56,58,66)
	up.BorderSizePixel = 0
	up.Text = "?"
	up.Font = Enum.Font.GothamBold
	up.TextSize = 10
	up.TextColor3 = Color3.fromRGB(240,242,248)
	up.ZIndex = 1004
	up.Parent = row
	local cu = Instance.new("UICorner"); cu.CornerRadius = UDim.new(0,4); cu.Parent = up

	local down = Instance.new("TextButton")
	down.Size = UDim2.new(0, 18, 0, 11)
	down.Position = UDim2.new(0, (width or 54) + 52, 0, 13)
	down.BackgroundColor3 = Color3.fromRGB(56,58,66)
	down.BorderSizePixel = 0
	down.Text = "?"
	down.Font = Enum.Font.GothamBold
	down.TextSize = 10
	down.TextColor3 = Color3.fromRGB(240,242,248)
	down.ZIndex = 1004
	down.Parent = row
	local cd = Instance.new("UICorner"); cd.CornerRadius = UDim.new(0,4); cd.Parent = down

	local function getNumber()
		return tonumber(box.Text) or 0
	end
	local function setNumber(v: number)
		box.Text = tostring(math.clamp(math.floor(v + 0.5), minV, maxV))
	end

	local changed = Instance.new("BindableEvent")
	box.FocusLost:Connect(function()
		local v = getNumber()
		v = math.clamp(math.floor(v + 0.5), minV, maxV)
		setNumber(v)
		changed:Fire(v)
	end)
	up.MouseButton1Click:Connect(function()
		setNumber(getNumber() + 1)
		changed:Fire(getNumber())
	end)
	down.MouseButton1Click:Connect(function()
		setNumber(getNumber() - 1)
		changed:Fire(getNumber())
	end)

	return {
		row = row,
		box = box,
		set = setNumber,
		get = getNumber,
		Changed = changed.Event,
	}
end

-- ------------------------------------------------------------------------------
-- UI scaffold
-- ------------------------------------------------------------------------------
local function buildUI(_parent: Instance, opts: table)
	opts = opts or {}
	local size = opts.size or UDim2.new(0, 460, 0, 310)

	local root = Instance.new("Frame")
	root.Name = "ColorPicker"
	root.Size = size
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ZIndex = 1002
	root.Parent = _parent

	local title
	if opts.title and opts.title ~= "" then
		title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamMedium
		title.TextSize = 14
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = Color3.fromRGB(225,227,234)
		title.Text = opts.title
		title.Size = UDim2.new(1, 0, 0, 18)
		title.ZIndex = 1005
		title.Parent = root
	end

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.BackgroundTransparency = 1
	main.Size = UDim2.new(1, 0, 1, title and -28 or -10)
	main.Position = UDim2.new(0, 0, 0, title and 22 or 0)
	main.ZIndex = 1003
	main.Parent = root

	local uiList = Instance.new("UIListLayout")
	uiList.FillDirection = Enum.FillDirection.Horizontal
	uiList.SortOrder = Enum.SortOrder.LayoutOrder
	uiList.Padding = UDim.new(0,10)
	uiList.Parent = main

	-- SV square
	local svHolder = Instance.new("Frame")
	svHolder.BackgroundTransparency = 1
	svHolder.Size = UDim2.new(0, 220, 1, 0)
	svHolder.ZIndex = 1004
	svHolder.Parent = main

	local sv = Instance.new("Frame")
	sv.Name = "SV"
	sv.Size = UDim2.new(0, 220, 0, 220)
	sv.BackgroundColor3 = Color3.new(1,1,1)
	sv.BorderSizePixel = 0
	sv.Active = true
	sv.ZIndex = 1004
	sv.Parent = svHolder
	local svCorner = Instance.new("UICorner"); svCorner.CornerRadius = UDim.new(0, 8); svCorner.Parent = sv
	local svStroke = Instance.new("UIStroke"); svStroke.Color = Color3.fromRGB(55,57,65); svStroke.Thickness = 1; svStroke.Parent = sv

	local gradSat = Instance.new("UIGradient")
	gradSat.Rotation = 0
	gradSat.Parent = sv

	local svDark = Instance.new("Frame")
	svDark.BackgroundColor3 = Color3.new(0,0,0)
	svDark.BorderSizePixel = 0
	svDark.Size = UDim2.fromScale(1,1)
	svDark.ZIndex = 1004
	svDark.Parent = sv

	local gradVal = Instance.new("UIGradient")
	gradVal.Rotation = 90
	gradVal.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	gradVal.Parent = svDark

	local svKnob = Instance.new("Frame")
	svKnob.Size = UDim2.fromOffset(14,14)
	svKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	svKnob.Position = UDim2.fromScale(1, 0)
	svKnob.BackgroundColor3 = Color3.fromRGB(245,245,245)
	svKnob.BorderSizePixel = 0
	svKnob.Active = true
	svKnob.ZIndex = 1005
	svKnob.Parent = sv
	local svKnobCorner = Instance.new("UICorner"); svKnobCorner.CornerRadius = UDim.new(1,0); svKnobCorner.Parent = svKnob
	local svKnobStroke = Instance.new("UIStroke"); svKnobStroke.Color = Color3.fromRGB(20,20,20); svKnobStroke.Thickness = 1; svKnobStroke.Parent = svKnob

	-- Right column
	local side = Instance.new("Frame")
	side.BackgroundTransparency = 1
	side.Size = UDim2.new(1, -230, 1, 0)
	side.ZIndex = 1004
	side.Parent = main

	local sideList = Instance.new("UIListLayout")
	sideList.Padding = UDim.new(0,10)
	sideList.FillDirection = Enum.FillDirection.Vertical
	sideList.SortOrder = Enum.SortOrder.LayoutOrder
	sideList.Parent = side

	-- Hue bar
	local hue = Instance.new("Frame")
	hue.Size = UDim2.new(1, 0, 0, 20)
	hue.BackgroundColor3 = Color3.fromRGB(255,255,255)
	hue.BorderSizePixel = 0
	hue.Active = true
	hue.ZIndex = 1004
	hue.Parent = side
	local hueCorner = Instance.new("UICorner"); hueCorner.CornerRadius = UDim.new(0,6); hueCorner.Parent = hue
	local hueStroke = Instance.new("UIStroke"); hueStroke.Color = Color3.fromRGB(55,57,65); hueStroke.Thickness = 1; hueStroke.Parent = hue
	local hueGrad = Instance.new("UIGradient"); hueGrad.Rotation = 0; hueGrad.Color = hueSequence(); hueGrad.Parent = hue

	local hueKnob = Instance.new("Frame")
	hueKnob.Size = UDim2.new(0, 10, 1, 6)
	hueKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	hueKnob.Position = UDim2.fromScale(0, 0.5)
	hueKnob.BackgroundColor3 = Color3.fromRGB(240,240,240)
	hueKnob.BorderSizePixel = 0
	hueKnob.Active = true
	hueKnob.ZIndex = 1005
	hueKnob.Parent = hue
	local hueKnobCorner = Instance.new("UICorner"); hueKnobCorner.CornerRadius = UDim.new(0,4); hueKnobCorner.Parent = hueKnob
	local hueKnobStroke = Instance.new("UIStroke"); hueKnobStroke.Color = Color3.fromRGB(20,20,20); hueKnobStroke.Thickness = 1; hueKnobStroke.Parent = hueKnob

	-- Preview + Hex
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 64)
	row.ZIndex = 1004
	row.Parent = side
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.Padding = UDim.new(0,10)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = row

	local preview = Instance.new("Frame")
	preview.Size = UDim2.new(0, 64, 1, 0)
	preview.BackgroundColor3 = Color3.new(1,1,1)
	preview.BorderSizePixel = 0
	preview.ZIndex = 1004
	preview.Parent = row
	local prevCorner = Instance.new("UICorner"); prevCorner.CornerRadius = UDim.new(0,8); prevCorner.Parent = preview
	local prevStroke = Instance.new("UIStroke"); prevStroke.Color = Color3.fromRGB(55,57,65); prevStroke.Thickness = 1; prevStroke.Parent = preview

	local hex = Instance.new("TextBox")
	hex.Size = UDim2.new(1, -74, 0, 32)
	hex.BackgroundColor3 = Color3.fromRGB(44,46,53)
	hex.ClearTextOnFocus = false
	hex.BorderSizePixel = 0
	hex.PlaceholderText = "#RRGGBB"
	hex.TextXAlignment = Enum.TextXAlignment.Left
	hex.Text = "#FFFFFF"
	hex.Font = Enum.Font.Gotham
	hex.TextSize = 14
	hex.TextColor3 = Color3.fromRGB(225,227,234)
	hex.ZIndex = 1004
	hex.Parent = row
	local hexCorner = Instance.new("UICorner"); hexCorner.CornerRadius = UDim.new(0,6); hexCorner.Parent = hex
	local hexStroke = Instance.new("UIStroke"); hexStroke.Color = Color3.fromRGB(55,57,65); hexStroke.Thickness = 1; hexStroke.Parent = hex

	-- Fields (HSV / RGB)
	local fields = Instance.new("Frame")
	fields.BackgroundTransparency = 1
	fields.Size = UDim2.new(1, 0, 0, 120)
	fields.Parent = side
	fields.ZIndex = 1004

	local cols = Instance.new("UIListLayout")
	cols.FillDirection = Enum.FillDirection.Horizontal
	cols.Padding = UDim.new(0, 16)
	cols.Parent = fields

	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Size = UDim2.new(0.5, -8, 1, 0)
	left.Parent = fields
	left.ZIndex = 1004
	local leftList = Instance.new("UIListLayout"); leftList.Padding = UDim.new(0, 6); leftList.Parent = left

	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.Size = UDim2.new(0.5, -8, 1, 0)
	right.Parent = fields
	right.ZIndex = 1004
	local rightList = Instance.new("UIListLayout"); rightList.Padding = UDim.new(0, 6); rightList.Parent = right

	local fldH = makeNumberField(left,  "Hue:", 0, 360, 56)
	local fldS = makeNumberField(left,  "Sat:", 0, 255, 56)
	local fldV = makeNumberField(left,  "Val:", 0, 255, 56)

	local fldR = makeNumberField(right, "Red:",   0, 255, 56)
	local fldG = makeNumberField(right, "Green:", 0, 255, 56)
	local fldB = makeNumberField(right, "Blue:",  0, 255, 56)

	return {
		root = root,
		sv = sv, svKnob = svKnob, gradSat = gradSat, gradVal = gradVal,
		hue = hue, hueKnob = hueKnob,
		preview = preview, hex = hex,
		fldH = fldH, fldS = fldS, fldV = fldV,
		fldR = fldR, fldG = fldG, fldB = fldB,
	}
end

-- ------------------------------------------------------------------------------
-- Picker logic
-- ------------------------------------------------------------------------------
function ColorPicker.new(parent: Instance, opts: table)
	opts = opts or {}
	local self = setmetatable({}, ColorPicker)

	-- state
	self._cons = {}
	self._dragConn = nil
	self._dragEndConn = nil
	self._dragging = false
	self._onChanged = opts.onChanged
	self._onConfirmed = opts.onConfirmed

	-- build
	local ui = buildUI(parent, opts)
	self.Frame = ui.root
	self._ui = ui

	-- plugin space helper
	local pluginGui = self.Frame:FindFirstAncestorWhichIsA("PluginGui")

	local function getMouseInRootXY(): (number, number)
		if pluginGui and pluginGui.GetRelativeMousePosition then
			local v = pluginGui:GetRelativeMousePosition()
			local rootInPlugin = self._ui.root.AbsolutePosition - pluginGui.AbsolutePosition
			return v.X - rootInPlugin.X, v.Y - rootInPlugin.Y
		end
		local m = UIS:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local guiX, guiY = m.X - inset.X, m.Y - inset.Y
		local rAbs = self._ui.root.AbsolutePosition
		return guiX - rAbs.X, guiY - rAbs.Y
	end

	-- HSV state
	local initial = opts.color or Color3.new(1,1,1)
	local h, s, v = initial:ToHSV()
	self._h, self._s, self._v = h, s, v

	-- updaters
	function self:_applyHueGradient()
		self._ui.gradSat.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHSV(self._h, 0, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV(self._h, 1, 1)),
		})
	end
	function self:_applyKnobs()
		self._ui.svKnob.Position  = UDim2.fromScale(self._s, 1 - self._v)
		self._ui.hueKnob.Position = UDim2.fromScale(self._h % 1, 0.5)
	end
	function self:_applyPreviewHex()
		local c = Color3.fromHSV(self._h, self._s, self._v)
		self._ui.preview.BackgroundColor3 = c
		self._ui.hex.Text = colorToHex(c)
	end
	function self:_applyNumeric()
		local c = Color3.fromHSV(self._h, self._s, self._v)
		self._ui.fldR.set(math.floor(c.R * 255 + 0.5))
		self._ui.fldG.set(math.floor(c.G * 255 + 0.5))
		self._ui.fldB.set(math.floor(c.B * 255 + 0.5))
		self._ui.fldH.set(math.floor((self._h % 1) * 360 + 0.5))
		self._ui.fldS.set(math.floor(self._s * 255 + 0.5))
		self._ui.fldV.set(math.floor(self._v * 255 + 0.5))
	end
	function self:_applyAll()
		self:_applyHueGradient()
		self:_applyKnobs()
		self:_applyPreviewHex()
		self:_applyNumeric()
	end
	local function fireChanged()
		if self._onChanged then self._onChanged(Color3.fromHSV(self._h, self._s, self._v)) end
		if self.Changed then self.Changed:Fire(Color3.fromHSV(self._h, self._s, self._v)) end
	end
	local function fireConfirmed()
		if self._onConfirmed then self._onConfirmed(Color3.fromHSV(self._h, self._s, self._v)) end
		if self.Confirmed then self.Confirmed:Fire(Color3.fromHSV(self._h, self._s, self._v)) end
	end

	self.Changed = Instance.new("BindableEvent")
	self.Confirmed = Instance.new("BindableEvent")

	self:_applyAll()

	-- drag engine
	function self:_startDrag(updateFn: (number, number) -> (), label: string)
		if self._dragConn then self._dragConn:Disconnect() end
		if self._dragEndConn then self._dragEndConn:Disconnect(); self._dragEndConn = nil end
		self._dragging = true
		self._dragConn = RS.RenderStepped:Connect(function()
			if not self._ui then self:_stopDrag(); return end
			local rx, ry = getMouseInRootXY()
			updateFn(rx, ry)
		end)
	end
	function self:_stopDrag()
		if self._dragConn then self._dragConn:Disconnect(); self._dragConn = nil end
		if self._dragEndConn then self._dragEndConn:Disconnect(); self._dragEndConn = nil end
		self._dragging = false
	end

	-- SV dragging
	local function setSVFromRootXY(rx: number, ry: number)
		local svPos = self._ui.sv.AbsolutePosition - self._ui.root.AbsolutePosition
		local svSize = self._ui.sv.AbsoluteSize
		self._s = clamp01((rx - svPos.X) / math.max(1, svSize.X))
		self._v = 1 - clamp01((ry - svPos.Y) / math.max(1, svSize.Y))
		self:_applyKnobs(); self:_applyPreviewHex(); self:_applyNumeric(); fireChanged()
	end
	local function beginDragSV(input: InputObject)
		if self._dragging then return end
		local rx, ry = getMouseInRootXY()
		setSVFromRootXY(rx, ry)
		self:_startDrag(setSVFromRootXY, "SV")
		self._dragEndConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				self:_stopDrag(); fireConfirmed()
			end
		end)
	end
	table.insert(self._cons, self._ui.sv.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then beginDragSV(i) end
	end))
	table.insert(self._cons, self._ui.svKnob.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then beginDragSV(i) end
	end))

	-- Hue dragging
	local function setHueFromRootX(rx: number)
		local huePos = self._ui.hue.AbsolutePosition - self._ui.root.AbsolutePosition
		local hueSize = self._ui.hue.AbsoluteSize
		self._h = clamp01((rx - huePos.X) / math.max(1, hueSize.X))
		self:_applyHueGradient(); self:_applyKnobs(); self:_applyPreviewHex(); self:_applyNumeric(); fireChanged()
	end
	local function beginDragHue(input: InputObject)
		if self._dragging then return end
		local rx = select(1, getMouseInRootXY())
		setHueFromRootX(rx)
		self:_startDrag(function(x, _y) setHueFromRootX(x) end, "HUE")
		self._dragEndConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				self:_stopDrag(); fireConfirmed()
			end
		end)
	end
	table.insert(self._cons, self._ui.hue.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then beginDragHue(i) end
	end))
	table.insert(self._cons, self._ui.hueKnob.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then beginDragHue(i) end
	end))

	-- Hex input
	table.insert(self._cons, self._ui.hex.FocusLost:Connect(function(_enterPressed)
		local c = hexToColor(self._ui.hex.Text)
		if c then
			self._h, self._s, self._v = c:ToHSV()
			self:_applyAll(); fireChanged(); fireConfirmed()
		else
			self:_applyPreviewHex() -- revert text
		end
	end))

	-- Numeric fields
	table.insert(self._cons, self._ui.fldH.Changed:Connect(function(hDeg)
		self._h = (hDeg % 360) / 360
		self:_applyAll(); fireChanged(); fireConfirmed()
	end))
	table.insert(self._cons, self._ui.fldS.Changed:Connect(function(s255)
		self._s = math.clamp(s255, 0, 255) / 255
		self:_applyAll(); fireChanged(); fireConfirmed()
	end))
	table.insert(self._cons, self._ui.fldV.Changed:Connect(function(v255)
		self._v = math.clamp(v255, 0, 255) / 255
		self:_applyAll(); fireChanged(); fireConfirmed()
	end))

	local function applyRGB(r,g,b)
		local c = Color3.fromRGB(math.clamp(r,0,255), math.clamp(g,0,255), math.clamp(b,0,255))
		self._h, self._s, self._v = c:ToHSV()
		self:_applyAll(); fireChanged(); fireConfirmed()
	end
	table.insert(self._cons, self._ui.fldR.Changed:Connect(function(_)
		applyRGB(self._ui.fldR.get(), self._ui.fldG.get(), self._ui.fldB.get())
	end))
	table.insert(self._cons, self._ui.fldG.Changed:Connect(function(_)
		applyRGB(self._ui.fldR.get(), self._ui.fldG.get(), self._ui.fldB.get())
	end))
	table.insert(self._cons, self._ui.fldB.Changed:Connect(function(_)
		applyRGB(self._ui.fldR.get(), self._ui.fldG.get(), self._ui.fldB.get())
	end))

	return self
end

function ColorPicker:GetColor(): Color3
	return Color3.fromHSV(self._h, self._s, self._v)
end

function ColorPicker:SetColor(c: Color3)
	self._h, self._s, self._v = c:ToHSV()
	self:_applyAll()
	if self._onChanged then self._onChanged(c) end
	if self.Changed then self.Changed:Fire(c) end
end

function ColorPicker:Destroy()
	self:_stopDrag()
	for _, c in ipairs(self._cons) do pcall(function() c:Disconnect() end) end
	if self.Changed then self.Changed:Destroy() end
	if self.Confirmed then self.Confirmed:Destroy() end
	if self.Frame then self.Frame:Destroy() end
	for k in pairs(self) do self[k] = nil end
end

--------------------------------------------------------------------------------
-- Public Modal wrapper
--------------------------------------------------------------------------------
local Modal = {}
Modal.__index = Modal

local function makeButton(text: string, primary: boolean): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 90, 0, 30)
	btn.BackgroundColor3 = primary and Color3.fromRGB(38,138,255) or Color3.fromRGB(56,58,66)
	btn.AutoButtonColor = true
	btn.Text = text
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 14
	btn.TextColor3 = Color3.fromRGB(240,242,248)
	btn.BorderSizePixel = 0
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,6); corner.Parent = btn
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(45,47,54); stroke.Thickness = 1; stroke.Parent = btn
	return btn
end

function Modal.Show(parent: Instance, opts: table?)
	opts = opts or {}
	local self = setmetatable({}, Modal)

	-- overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "TLX_ColorModalOverlay"
	overlay.BackgroundColor3 = Color3.new(0,0,0)
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.Active = true
	overlay.Selectable = true
	overlay.ZIndex = 1000
	overlay.Size = UDim2.fromScale(1,1)
	overlay.Parent = parent
	self._overlay = overlay

	-- panel
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = opts.size or UDim2.fromOffset(520, 380)
	panel.BackgroundColor3 = Color3.fromRGB(30,31,36)
	panel.BorderSizePixel = 0
	panel.ZIndex = 1001
	panel.Parent = overlay
	self._panel = panel
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,10); corner.Parent = panel
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(55,57,65); stroke.Thickness = 1; stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -16, 0, 28)
	title.Position = UDim2.fromOffset(8, 6)
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(225,227,234)
	title.ZIndex = 1001
	title.Text = opts.title or "Material Color Picker"
	title.Parent = panel

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(10, 34)
	content.Size = UDim2.new(1, -20, 1, -84)
	content.ZIndex = 1001
	content.Parent = panel

	-- picker
	local picker = ColorPicker.new(content, {
		color = opts.color or Color3.new(1,1,1),
		size = UDim2.new(1, 0, 1, 0),
		onChanged = function(_) end, -- live preview optional
	})
	self._picker = picker

	-- buttons
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.ZIndex = 1001
	row.Size = UDim2.new(1, -20, 0, 36)
	row.Position = UDim2.new(0, 10, 1, -44)
	row.Parent = panel

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Padding = UDim.new(0, 10)
	list.Parent = row

	local btnCancel = makeButton(opts.cancelText or "Cancel", false); btnCancel.ZIndex = 1004; btnCancel.Parent = row
	local btnOK     = makeButton(opts.okText or "OK", true);          btnOK.ZIndex = 1004;     btnOK.Parent = row

	-- close helper
	local closed = false
	local function close(cancelled: boolean)
		if closed then return end
		closed = true
		if cancelled then
			if opts.onCancel then opts.onCancel() end
		else
			local c = picker:GetColor()
			if opts.onConfirm then opts.onConfirm(c) end
		end
		if picker._stopDrag then picker:_stopDrag() end
		picker:Destroy()
		overlay:Destroy()
	end
	self.Close = close

	btnCancel.MouseButton1Click:Connect(function() close(true) end)
	btnOK.MouseButton1Click:Connect(function() close(false) end)

	-- ESC cancels
	local escConn; escConn = UIS.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			if escConn then escConn:Disconnect() end
			close(true)
		end
	end)

	-- click outside cancels
	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local p = input.Position
			local abs = panel.AbsolutePosition
			local size = panel.AbsoluteSize
			local inside = p.X >= abs.X and p.X <= abs.X + size.X and p.Y >= abs.Y and p.Y <= abs.Y + size.Y
			if not inside then close(true) end
		end
	end)

	return self
end

return Modal
