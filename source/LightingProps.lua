-- Modules/LightingProps.lua
-- Properties UI for the "Lighting" edit mode (Day/Night System + Atmosphere)
-- Matches the spec + comps:
--  • Two cards: "Day / Night System" and "Atmosphere"
--  • Day/Night fields: DayStartHour, NightStartHour, DayLengthMinutes, NightLengthMinutes
--  • Atmosphere fields: Density, Offset, Color, Decay, Glare, Haze
-- Reuses existing UI helpers when available (self.UI / Corners / Strokes / ModalColorPicker).
-- Falls back to native Instances if a helper is missing.
--
-- Public API:
--   LightingProps.new(ctx): LightingProps
--     ctx = {
--       plugin: Plugin,
--       propsFrame: Frame,           -- parent container for cards
--       UI: table?,                  -- optional UI helper module (self.UI)
--       DataManager: table,          -- required data layer
--       ModalColorPicker: table?,    -- optional modal color picker (ModalColorPicker.Show)
--     }
--   :Mount()    -- build UI
--   :Unmount()  -- clean up
--   :Refresh()  -- re-read DM and update fields (if changed externally)

local LightingProps = {}
LightingProps.__index = LightingProps

-- ========= Utilities =========

local function clampInt(v, minV, maxV)
	if v == nil then return minV end
	v = tonumber(v) or minV
	if v < minV then v = minV end
	if v > maxV then v = maxV end
	return math.floor(v + 0.5)
end

local function toNumber(v, default)
	v = tonumber(v)
	return (v == nil) and default or v
end

local function colorToText(c)
	-- "[R, G, B]" like the comp
	local r = math.floor(c.R * 255 + 0.5)
	local g = math.floor(c.G * 255 + 0.5)
	local b = math.floor(c.B * 255 + 0.5)
	return string.format("[%d, %d, %d]", r, g, b)
end

local function applyUICosmetics(UI, instance)
	if UI and UI.Corners and typeof(UI.Corners.make) == "function" then
		UI.Corners.make(instance, 6)
	end
	if UI and UI.Strokes and typeof(UI.Strokes.make) == "function" then
		UI.Strokes.make(instance, Color3.fromRGB(0,0,0), 0.8)
	end
end

-- Small helper to make a labeled row with right-aligned field container
local function makeRow(parent, UI, labelText)
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 28)
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.6, -10, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.Font = Enum.Font.SourceSans
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(220, 224, 230)
	label.Text = labelText
	label.Parent = row

	local fieldHolder = Instance.new("Frame")
	fieldHolder.Name = "Field"
	fieldHolder.BackgroundTransparency = 1
	fieldHolder.Size = UDim2.new(0.4, -10, 1, 0)
	fieldHolder.Position = UDim2.new(0.6, 0, 0, 0)
	fieldHolder.Parent = row

	return row, label, fieldHolder
end

-- Make a numeric TextBox that looks like Studio property fields
local function makeNumberBox(parent, initialText)
	local box = Instance.new("TextBox")
	box.Name = "NumberBox"
	box.BackgroundColor3 = Color3.fromRGB(58, 61, 69)
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, 0, 0, 22)
	box.Position = UDim2.new(0, 0, 0.5, -11)
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.SourceSans
	box.TextSize = 16
	box.TextColor3 = Color3.fromRGB(240, 242, 247)
	box.TextXAlignment = Enum.TextXAlignment.Right
	box.Text = tostring(initialText or "")
	box.Parent = parent
	applyUICosmetics(nil, box)
	return box
end

-- Make a color field (button + readout); clicking opens ModalColorPicker if provided
local function makeColorField(parent, initialColor, initialText)
	local holder = Instance.new("Frame")
	holder.Name = "ColorField"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 1, 0)
	holder.Parent = parent

	local swatch = Instance.new("TextButton")
	swatch.Name = "Swatch"
	swatch.AutoButtonColor = true
	swatch.Size = UDim2.new(0, 24, 0, 22)
	swatch.Position = UDim2.new(0, 0, 0.5, -11)
	swatch.Text = ""
	swatch.BorderSizePixel = 0
	swatch.BackgroundColor3 = initialColor or Color3.fromRGB(111, 126, 62)
	swatch.Parent = holder
	applyUICosmetics(nil, swatch)

	local readout = Instance.new("TextButton")
	readout.Name = "Readout"
	readout.AutoButtonColor = true
	readout.Size = UDim2.new(1, -28, 0, 22)
	readout.Position = UDim2.new(0, 28, 0.5, -11)
	readout.BackgroundColor3 = Color3.fromRGB(58, 61, 69)
	readout.BorderSizePixel = 0
	readout.TextXAlignment = Enum.TextXAlignment.Center
	readout.TextColor3 = Color3.fromRGB(240, 242, 247)
	readout.Font = Enum.Font.SourceSans
	readout.TextSize = 16
	readout.Text = initialText or colorToText(swatch.BackgroundColor3)
	readout.Parent = holder
	applyUICosmetics(nil, readout)

	return holder, swatch, readout
end

-- Card scaffold
local function makeCard(parent, title)
	local card = Instance.new("Frame")
	card.Name = title:gsub("%s+", "") .. "Card"
	card.BackgroundColor3 = Color3.fromRGB(36, 39, 46)
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 0) -- height auto via UIList + content
	card.Parent = parent
	applyUICosmetics(nil, card)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = Color3.fromRGB(45, 48, 56)
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, -8, 0, 28)
	header.Position = UDim2.new(0, 4, 0, 4)
	header.Parent = card

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -32, 1, 0)
	titleLabel.Position = UDim2.new(0, 8, 0, 0)
	titleLabel.Font = Enum.Font.SourceSansBold
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = Color3.fromRGB(220, 224, 230)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = title
	titleLabel.Parent = header

	local chevron = Instance.new("TextButton")
	chevron.Name = "Chevron"
	chevron.BackgroundTransparency = 1
	chevron.Size = UDim2.new(0, 24, 1, 0)
	chevron.Position = UDim2.new(1, -24, 0, 0)
	chevron.Text = "?"
	chevron.TextSize = 16
	chevron.Font = Enum.Font.SourceSansBold
	chevron.TextColor3 = Color3.fromRGB(220, 224, 230)
	chevron.Parent = header

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 8, 0, 36)
	body.Size = UDim2.new(1, -16, 0, 0)
	body.Parent = card

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = body

	local function resize()
		local bodyH = body.UIListLayout and body.UIListLayout.AbsoluteContentSize.Y or list.AbsoluteContentSize.Y
		body.Size = UDim2.new(1, -16, 0, bodyH)
		card.Size = UDim2.new(1, 0, 0, 36 + 8 + bodyH)
	end

	body.UIListLayout = list
	body.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
	task.defer(resize)

	local expanded = true
	chevron.MouseButton1Click:Connect(function()
		expanded = not expanded
		chevron.Text = expanded and "?" or "?"
		body.Visible = expanded
		task.defer(resize)
	end)

	return card, body, resize
end

-- ========= Class =========

function LightingProps.new(ctx)
	assert(ctx and ctx.propsFrame and ctx.DataManager, "LightingProps.new(ctx) requires propsFrame and DataManager")
	local self = setmetatable({}, LightingProps)
	self.plugin = ctx.plugin
	self.propsFrame = ctx.propsFrame
	self.UI = ctx.UI
	self.DM = ctx.DataManager
	self.ModalColorPicker = ctx.ModalColorPicker
	self._conns = {}
	self._built = false
	return self
end

function LightingProps:Unmount()
	for _,c in ipairs(self._conns) do
		if typeof(c) == "RBXScriptConnection" then
			c:Disconnect()
		end
	end
	self._conns = {}
	if self.container and self.container.Parent then
		self.container:Destroy()
	end
	self._built = false
end

-- Build UI according to comps/spec
function LightingProps:Mount()
	self:Unmount()

	local dm = self.DM
	local lighting = dm.LightingGet and dm.LightingGet() or {
		DayNight = {
			dayStartHour = 12,
			nightStartHour = 18,
			dayLengthMinutes = 25,
			nightLengthMinutes = 10,
		},
		Atmosphere = {
			density = 0.45,
			offset = 0,
			color = Color3.fromRGB(111,126,62),
			decay = Color3.fromRGB(111,126,62),
			glare = 0,
			haze = 0,
		}
	}

	-- Container
	local container = Instance.new("Frame")
	container.Name = "LightingProps"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.Parent = self.propsFrame

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = container

	self.container = container

	----------------------------------------------------------------
	-- Card 1: Day / Night System
	----------------------------------------------------------------
	local dayCard, dayBody, dayResize = makeCard(container, "Day / Night System")

	-- Day Start Hour (1..24)
	do
		local row, _, field = makeRow(dayBody, self.UI, "Day Start Hour")
		local box = makeNumberBox(field, lighting.DayNight.dayStartHour)
		table.insert(self._conns, box.FocusLost:Connect(function(enterPressed)
			local v = clampInt(box.Text, 1, 24)
			box.Text = tostring(v)
			if self.DM.LightingSetPath then
				self.DM.LightingSetPath({"DayNight","dayStartHour"}, v)
			end
		end))
	end

	-- Night Start Hour (1..24)
	do
		local row, _, field = makeRow(dayBody, self.UI, "Night Start Hour")
		local box = makeNumberBox(field, lighting.DayNight.nightStartHour)
		table.insert(self._conns, box.FocusLost:Connect(function()
			local v = clampInt(box.Text, 1, 24)
			box.Text = tostring(v)
			if self.DM.LightingSetPath then
				self.DM.LightingSetPath({"DayNight","nightStartHour"}, v)
			end
		end))
	end

	-- Day Length (Minutes)
	do
		local row, _, field = makeRow(dayBody, self.UI, "Day Length (Minutes)")
		local box = makeNumberBox(field, lighting.DayNight.dayLengthMinutes)
		table.insert(self._conns, box.FocusLost:Connect(function()
			local v = clampInt(box.Text, 1, 24*60)
			box.Text = tostring(v)
			if self.DM.LightingSetPath then
				self.DM.LightingSetPath({"DayNight","dayLengthMinutes"}, v)
			end
		end))
	end

	-- Night Length (Minutes)
	do
		local row, _, field = makeRow(dayBody, self.UI, "Night Length (Minutes)")
		local box = makeNumberBox(field, lighting.DayNight.nightLengthMinutes)
		table.insert(self._conns, box.FocusLost:Connect(function()
			local v = clampInt(box.Text, 1, 24*60)
			box.Text = tostring(v)
			if self.DM.LightingSetPath then
				self.DM.LightingSetPath({"DayNight","nightLengthMinutes"}, v)
			end
		end))
	end

	----------------------------------------------------------------
	-- Card 2: Atmosphere
	----------------------------------------------------------------
	local atmCard, atmBody, atmResize = makeCard(container, "Atmosphere")

	-- Density (float)
	do
		local row, _, field = makeRow(atmBody, self.UI, "Density")
		local box = makeNumberBox(field, lighting.Atmosphere.density)
		table.insert(self._conns, box.FocusLost:Connect(function()
			local v = toNumber(box.Text, 0.45)
			box.Text = tostring(v)
			if self.DM.LightingSetPath then
				self.DM.LightingSetPath({"Atmosphere","density"}, v)
			end
		end))
	end

	-- Offset (number)
	do
		local row, _, field = makeRow(atmBody, self.UI, "Offset")
		local box = makeNumberBox(field, lighting.Atmosphere.offset)
		table.insert(self._conns, box.FocusLost:Connect(function()
			local v = toNumber(box.Text, 0)
			box.Text = tostring(v)
			if self.DM.LightingSetPath then
				self.DM.LightingSetPath({"Atmosphere","offset"}, v)
			end
		end))
	end

	-- Color (Color3 picker)
	do
		local row, _, field = makeRow(atmBody, self.UI, "Color")
		local holder, swatch, readout = makeColorField(field, lighting.Atmosphere.color)
		local function setColor(c)
			swatch.BackgroundColor3 = c
			readout.Text = colorToText(c)
			if self.DM.LightingSetPath then
				self.DM.LightingSetPath({"Atmosphere","color"}, c)
			end
		end
		local function openPicker()
			if self.ModalColorPicker and self.ModalColorPicker.Show then
				self.ModalColorPicker.Show(self.propsFrame, {
					title = "Atmosphere Color",
					color = swatch.BackgroundColor3,
					onConfirm = function(c) setColor(c) end,
				})
			end
		end
		table.insert(self._conns, swatch.MouseButton1Click:Connect(openPicker))
		table.insert(self._conns, readout.MouseButton1Click:Connect(openPicker))
	end

	-- Decay (Color3 picker)
	do
		local row, _, field = makeRow(atmBody, self.UI, "Decay")
		local holder, swatch, readout = makeColorField(field, lighting.Atmosphere.decay)
		local function setColor(c)
			swatch.BackgroundColor3 = c
			readout.Text = colorToText(c)
			if self.DM.LightingSetPath then
				self.DM.LightingSetPath({"Atmosphere","decay"}, c)
			end
		end
		local function openPicker()
			if self.ModalColorPicker and self.ModalColorPicker.Show then
				self.ModalColorPicker.Show(self.propsFrame, {
					title = "Atmosphere Decay",
					color = swatch.BackgroundColor3,
					onConfirm = function(c) setColor(c) end,
				})
			end
		end
		table.insert(self._conns, swatch.MouseButton1Click:Connect(openPicker))
		table.insert(self._conns, readout.MouseButton1Click:Connect(openPicker))
	end

	-- Glare (number)
	do
		local row, _, field = makeRow(atmBody, self.UI, "Glare")
		local box = makeNumberBox(field, lighting.Atmosphere.glare)
		table.insert(self._conns, box.FocusLost:Connect(function()
			local v = toNumber(box.Text, 0)
			box.Text = tostring(v)
			if self.DM.LightingSetPath then
				self.DM.LightingSetPath({"Atmosphere","glare"}, v)
			end
		end))
	end

	-- Haze (number)
	do
		local row, _, field = makeRow(atmBody, self.UI, "Haze")
		local box = makeNumberBox(field, lighting.Atmosphere.haze)
		table.insert(self._conns, box.FocusLost:Connect(function()
			local v = toNumber(box.Text, 0)
			box.Text = tostring(v)
			if self.DM.LightingSetPath then
				self.DM.LightingSetPath({"Atmosphere","haze"}, v)
			end
		end))
	end

	self._built = true
end

function LightingProps:Refresh()
	if not self._built then return end
	if not (self.DM and self.DM.LightingGet) then return end
	local L = self.DM.LightingGet()

	-- Day/Night refresh
	local dayCard = self.container:FindFirstChild("Day/NightSystemCard")
	if dayCard and dayCard.Body then
		local rows = dayCard.Body:GetChildren()
		local function setBox(rIdx, value)
			local row = rows[rIdx]
			if row and row:FindFirstChild("Field") then
				local box = row.Field:FindFirstChild("NumberBox")
				if box then box.Text = tostring(value) end
			end
		end
		setBox(1, L.DayNight.dayStartHour)
		setBox(2, L.DayNight.nightStartHour)
		setBox(3, L.DayNight.dayLengthMinutes)
		setBox(4, L.DayNight.nightLengthMinutes)
	end

	-- Atmosphere refresh
	local atmCard = self.container:FindFirstChild("AtmosphereCard")
	if atmCard and atmCard.Body then
		local rows = atmCard.Body:GetChildren()
		local function setBox(rIdx, value)
			local row = rows[rIdx]
			if row and row:FindFirstChild("Field") then
				local box = row.Field:FindFirstChild("NumberBox")
				if box then box.Text = tostring(value) end
			end
		end
		local function setColorRow(rIdx, color)
			local row = rows[rIdx]
			if row and row:FindFirstChild("Field") then
				local fld = row.Field:FindFirstChild("ColorField")
				if fld then
					local sw = fld:FindFirstChild("Swatch")
					local rd = fld:FindFirstChild("Readout")
					if sw then sw.BackgroundColor3 = color end
					if rd then rd.Text = colorToText(color) end
				end
			end
		end

		setBox(1, L.Atmosphere.density)
		setBox(2, L.Atmosphere.offset)
		setColorRow(3, L.Atmosphere.color)
		setColorRow(4, L.Atmosphere.decay)
		setBox(5, L.Atmosphere.glare)
		setBox(6, L.Atmosphere.haze)
	end
end

return LightingProps
