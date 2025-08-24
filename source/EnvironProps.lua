-- EnvironProps (ModuleScript)
-- Environmental Edit Mode UI per specs: category system + per-category cards
-- Uses DM environmental API and UI helpers; CardMode="Environmental"

local HttpService = game:GetService("HttpService")
local ModalConfirm = require(script.Parent.UI:WaitForChild("ModalConfirm"))
local MaterialPreview = require(script.Parent.UI:WaitForChild("MaterialPreview"))
local Corners = require(script.Parent.UI.Corners)
local Strokes = require(script.Parent.UI.Strokes)
local Checkbox = require(script.Parent.UI.Checkboxes)
local ObjectPicker = require(script.Parent.UI.ObjectPicker)
local Inputs = require(script.Parent.UI.Inputs)
local Theme = require(script.Parent:WaitForChild("UI").Theme)

local EnvironProps = {}
EnvironProps.__index = EnvironProps

local CATEGORY_CARD_PREFIX = "ENV_"

function EnvironProps.new(UI, DM, parentScroll)
	return setmetatable({
		UI = UI,
		DM = DM,
		Parent = parentScroll,
		_lastBiome = nil,
	}, EnvironProps)
end

-- Clear only Environmental cards
function EnvironProps:_clearEnvCards()
	for _, ch in ipairs(self.Parent:GetChildren()) do
		if ch:IsA("Frame") and ch:GetAttribute("CardMode") == "Environmental" then
			ch:Destroy()
		end
	end
	local top = self.Parent:FindFirstChild("EnvTopBar")
	if top then top:Destroy() end
end

-- Top inline "New Category" bar
function EnvironProps:_buildTopBar(theme)
	local top = Instance.new("Frame")
	top.Name = "EnvTopBar"
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, -12, 0, 30)
	top.LayoutOrder = 1
	top.Parent = self.Parent
	top:SetAttribute("CardMode", "Environmental")

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = top

	local input = self.UI.ToolbarTextInput({
		Name = "NewEnvInput", Width = math.max(160, self.Parent.AbsoluteSize.X - 260), Height = 27, Placeholder = "New category name…",
	})
	input.Parent = top

	local add = self.UI.ToolbarButton({
		Name = "NewEnvAdd", Width = 80, Height = 27, Text = "Add", Disabled = false, TextAlign = "Center",
	})
	add.Parent = top

	local addClick = add:FindFirstChild("ClickArea")
	local tb = input:FindFirstChild("Input")
	local function tryAdd()
		if not tb then return end
		local name = (tb.Text or ""):gsub("^%s+",""):gsub("%s+$","")
		if name == "" then return end
		if self.DM.EnvCategoryExists(name) then
			-- shake: brief red stroke on input
			local st = input:FindFirstChildOfClass("UIStroke")
			if st then
				local old = st.Color; st.Color = Color3.fromRGB(200,70,70)
				task.delay(0.18, function() st.Color = old end)
			end
			return
		end
		self.DM.EnvCreateCategory(name)
		tb.Text = ""
		self:loadFromDM() -- rebuild list
	end
	if addClick and addClick:IsA("TextButton") then
		addClick.MouseButton1Click:Connect(tryAdd)
	end
	if tb and tb:IsA("TextBox") then
		tb.FocusLost:Connect(function(enter) if enter then tryAdd() end end)
	end
end

function EnvironProps:build()
	if not Theme then return end
	-- start fresh
	self:_clearEnvCards()
	self:_buildTopBar(Theme)

	-- build cards for existing categories (current biome)
	for _, cat in ipairs(self.DM.EnvListCategories()) do
		self:_buildCategoryCard(cat, Theme)
	end
end

function EnvironProps:loadFromDM()
	if not Theme then return end
	local biome = self.DM.GetSelectedBiome()
	if not biome then
		self:_clearEnvCards()
		self._lastBiome = nil
		return
	end
	if biome ~= self._lastBiome then
		self._lastBiome = biome
		self:build()
		return
	end

	-- Same biome: refresh or add any missing cards
	local existing = {}
	for _, cat in ipairs(self.DM.EnvListCategories()) do
		existing[cat] = true
		local card = self.Parent:FindFirstChild("Card_ENV_"..cat)
		if not card then
			self:_buildCategoryCard(cat, Theme)
		else
			self:_refreshCategoryCard(card, cat, Theme)
		end
	end
	-- remove cards for deleted categories
	for _, ch in ipairs(self.Parent:GetChildren()) do
		if ch:IsA("Frame") and ch:GetAttribute("CardMode") == "Environmental" then
			local key = ch:GetAttribute("CardKey")
			local name = key and tostring(key):gsub("^ENV_","") or nil
			if name and not existing[name] then ch:Destroy() end
		end
	end
end

-- Build one category card
function EnvironProps:_buildCategoryCard(catName, theme)
	local UI, DM = self.UI, self.DM
	local cardKey = CATEGORY_CARD_PREFIX..catName
	local expanded = (DM.GetCardExpanded(cardKey) == true)

	local card, content = UI.PropertyCard({
		Title = catName, CardKey = cardKey, ModeTag = "Environmental",
		Expanded = expanded,
		OnToggle = function(_, exp) DM.SetCardExpanded(cardKey, exp) end
	})
	card.Name = "Card_"..cardKey
	card.Parent = self.Parent
	card.ZIndex = 0
	card.LayoutOrder = 5
	card.Header.Title.AnchorPoint = Vector2.new(0,0.5)
	card.Header.Title.Position = UDim2.new(0, 25, 0.5, 0)
	print(card:GetChildren())

	-- Header adornments: color pick + delete
	do
		local header = card:FindFirstChild("Header")
		if header then
			-- Color swatch (preview color)
			local sw = Instance.new("ImageButton")
			sw.Size = UDim2.fromOffset(18,18)
			sw.Position = UDim2.new(1, -50, 0, 8)
			sw.BackgroundColor3 = Color3.fromRGB(200, 120, 80)
			sw.BorderSizePixel = 0
			sw.ZIndex = 5
			-- card:SetAttribute("EnvColorRGB", DM.EnvGetCategory(catName).color or {200,120,80})
			card:SetAttribute("EnvColorRGB", HttpService:JSONEncode(DM.EnvGetCategory(catName).color) or HttpService:JSONEncode({200,120,80}))
			local c = card:GetAttribute("EnvColorRGB")
			if typeof(c) == "table" then
				sw.BackgroundColor3 = Color3.fromRGB(c[1], c[2], c[3])
			end
			Corners.make(sw, 3); sw.ImageTransparency = 1; sw.Parent = header

			sw.MouseButton1Click:Connect(function()
				local ModalColor = require(script.Parent.UI:WaitForChild("ColorPicker")) -- your modal color picker module
				ModalColor.Show(card:FindFirstAncestor("Root"), {
					title = "Category Color",
					color = sw.BackgroundColor3,
					onConfirm = function(col)
						sw.BackgroundColor3 = col
						DM.EnvSetCategoryPath(catName, {"color"}, {math.floor(col.R*255+0.5), math.floor(col.G*255+0.5), math.floor(col.B*255+0.5)})
					end
				})
			end)

			-- Delete button
			local del = Instance.new("TextButton")
			del.Size = UDim2.fromOffset(20, 20)
			del.AnchorPoint = Vector2.new(0,0.5)
			del.Position = UDim2.new(0, 0, 0.5, 0)
			del.BackgroundColor3 = Color3.fromRGB(232, 58, 68)
			del.AutoButtonColor = false
			del.Text = "–"
			del.Font = Enum.Font.GothamBold
			del.TextSize = 14
			del.TextColor3 = Color3.fromRGB(255, 255, 255)
			del.ZIndex = 5
			del.Parent = header
			Corners.make(del, 4)

			del.MouseButton1Click:Connect(function()
				ModalConfirm.Show(card:FindFirstAncestor("Root"), {
					title = "Delete Category",
					message = ("Delete “%s”? This can’t be undone."):format(catName),
					okText = "Delete",
					primaryIsDestructive = true,
					onConfirm = function()
						DM.EnvDeleteCategory(catName)
						card:Destroy()
					end
				})
			end)

			-- Rename on double-click title
			local title = header:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.InputBegan:Connect(function(inp)
					if inp.UserInputType == Enum.UserInputType.MouseButton1 and inp.UserInputState == Enum.UserInputState.Begin and inp.ClickCount == 2 then
						-- turn into textbox
						local tb = Instance.new("TextBox")
						tb.Size = title.Size
						tb.Position = title.Position
						tb.BackgroundTransparency = 1
						tb.TextXAlignment = title.TextXAlignment
						tb.TextYAlignment = title.TextYAlignment
						tb.Font = title.Font; tb.TextSize = title.TextSize
						tb.TextColor3 = title.TextColor3
						tb.Text = catName
						tb.Parent = header
						title.Visible = false
						tb:CaptureFocus()
						local function cleanup(commit)
							if commit then
								local newName = (tb.Text or ""):gsub("^%s+",""):gsub("%s+$","")
								if newName ~= "" and not DM.EnvCategoryExists(newName) then
									DM.EnvRenameCategory(catName, newName)
									card.Name = "Card_"..CATEGORY_CARD_PREFIX..newName
									card:SetAttribute("CardKey", CATEGORY_CARD_PREFIX..newName)
									title.Text = newName
									catName = newName
								end
							end
							title.Visible = true; tb:Destroy()
						end
						tb.FocusLost:Connect(function(enter) cleanup(enter) end)
						tb.InputBegan:Connect(function(i)
							if i.KeyCode == Enum.KeyCode.Escape then cleanup(false) end
						end)
					end
				end)
			end
		end
	end


	-- Allowed Materials (auto list)
	do
		local bar = Instance.new("TextButton")
		bar.BackgroundColor3 = theme.ControlBgHover
		bar.BorderSizePixel = 0
		bar.Size = UDim2.new(1, -8, 0, 32)
		bar.LayoutOrder = 0
		bar.AutoButtonColor = false
		bar.Text = ""	
		bar.Parent = content

		Corners.make(bar, 6)
		local barLab = Instance.new("TextLabel")
		barLab.BackgroundTransparency = 1
		barLab.Text = "Allowed Materials"
		barLab.Font = Enum.Font.GothamMedium
		barLab.TextSize = 13
		barLab.TextColor3 = theme.ControlText
		barLab.TextXAlignment = Enum.TextXAlignment.Left
		barLab.Position = UDim2.fromOffset(10, 0)
		barLab.Size = UDim2.new(1, -36, 1, 0)
		barLab.Parent = bar

		local chevron = Instance.new("TextButton")
		chevron.Name = "Chevron"
		chevron.BackgroundTransparency = 1
		chevron.AutoButtonColor = false
		chevron.Text = "?"
		chevron.Font = Enum.Font.Gotham
		chevron.TextSize = 18
		chevron.TextColor3 = Color3.new(0.909804, 0.909804, 0.909804)
		chevron.AnchorPoint = Vector2.new(1, 0.5)
		chevron.Position = UDim2.new(1, -8, 0.5, 0)
		chevron.Size = UDim2.fromOffset(20, 20)
		chevron.ZIndex = 3
		chevron.Parent = bar

		local listWrap = Instance.new("ScrollingFrame")
		listWrap.Name = "AllowedMaterialsScroll"
		listWrap.BackgroundTransparency = 1
		--listWrap.AutomaticSize = Enum.AutomaticSize.Y
		listWrap.Size = UDim2.new(1, 0, 0, 150)
		listWrap.ClipsDescendants = true
		listWrap.BackgroundTransparency = 1
		listWrap.ScrollBarThickness = 3
		listWrap.ScrollBarImageColor3 = Color3.fromRGB(190,196,206)
		listWrap.CanvasSize = UDim2.new(0,0,0,0)
		listWrap.AutomaticCanvasSize = Enum.AutomaticSize.Y
		listWrap.ScrollBarImageColor3 = Color3.fromRGB(57, 62, 72)
		listWrap.ZIndex = 1010
		listWrap.Visible = false
		listWrap.Parent = content	

		bar.MouseButton1Click:Connect(function() 
			if listWrap.Visible == true then
				listWrap.Visible = false
				chevron.Text = "?"
			else
				listWrap.Visible = true
				chevron.Text = "?"
			end
		end)

		chevron.MouseButton1Click:Connect(function() 
			if listWrap.Visible == true then
				listWrap.Visible = false
				chevron.Text = "?"
			else
				listWrap.Visible = true
				chevron.Text = "?"
			end
		end)		

		local list = Instance.new("UIListLayout"); 
		list.Padding = UDim.new(0,6); 
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Left
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		list.Padding = UDim.new(0, 10)
		list.Parent = listWrap

		local matNames = DM.ListMaterials()
		local cat = DM.EnvGetCategory(catName)
		cat.allowed = cat.allowed or {}
		for _, m in ipairs(matNames) do
			local row = Instance.new("Frame")
			row.BackgroundColor3 = theme.ControlBg
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1,-8,0,36)
			row.Parent = listWrap
			Corners.make(row,6); 
			Strokes.make(row, theme.ControlBorder, 1)

			local thumb = Instance.new("Frame")
			thumb.Size = UDim2.fromOffset(30,30)
			thumb.Position = UDim2.fromOffset(6, 3)
			thumb.BackgroundTransparency = 1
			Corners.make(thumb, 4); 
			Strokes.make(thumb, theme.ControlBorder, 1)
			thumb.Parent = row
			MaterialPreview.attach(thumb, m)

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Font = Enum.Font.Gotham
			title.TextSize = 13
			title.TextColor3 = theme.ControlText
			title.Text = m
			title.Position = UDim2.fromOffset(44, 0)
			title.Size = UDim2.new(1, -120, 1, 0)
			title.Parent = row

			local box, set = Checkbox.make(theme, cat.allowed[m]==true, function(v)
				DM.EnvSetCategoryPath(catName, {"allowed", m}, v and true or false)
			end)
			box.AnchorPoint = Vector2.new(1,0.5); box.Position = UDim2.new(1,-8,0.5,0); box.Parent = row
		end
	end

	-- Rows: ScaleMin / ScaleMax
	do
		local _, area = UI.PropertyRow(content, "Scale")
		local a, tbA = Inputs.stepper.make(theme, 65, 0.1, 0, 999, true, 'Min')
		local b, tbB = Inputs.stepper.make(theme, 65, 0.1, 0, 999, true, 'Max')
		
		a.Parent = area 
		b.Parent = area
		
		tbA.Size = UDim2.new(0, 45, 1, 0)	
		tbB.Size = UDim2.new(0, 45, 1, 0)		
		
		local data = DM.EnvGetCategory(catName)
		tbA.Text = tostring(data.scaleMin or 1.0)
		tbB.Text = tostring(data.scaleMax or 1.0)
		tbA.FocusLost:Connect(function()
			local v = tonumber(tbA.Text) or data.scaleMin or 1
			DM.EnvSetCategoryPath(catName, {"scaleMin"}, v)
			tbA.Text = tostring(DM.EnvGetCategory(catName).scaleMin or 1)
		end)
		tbB.FocusLost:Connect(function()
			local v = tonumber(tbB.Text) or data.scaleMax or 1
			DM.EnvSetCategoryPath(catName, {"scaleMax"}, v)
			tbB.Text = tostring(DM.EnvGetCategory(catName).scaleMax or 1)
		end)
	end

	-- Altitude / Slope / Spacing
	local function rowNumber(labelTxt, key, step, min, max, layoutOrder, iconId)
		local container, area = UI.PropertyRow(content, labelTxt, true, 2)
		
		if iconId ~= nil then
			local icon = Instance.new("ImageLabel")
			icon.BackgroundTransparency = 1
			icon.Image = iconId
			icon.Name = "AAIcon"
			icon.AnchorPoint = Vector2.new(0,0.5)
			icon.Size = UDim2.new(0, 20, 0, 14)
			icon.Position = UDim2.new(0, 8, 0.5, 0)
			icon.LayoutOrder = 1
			icon.Parent = container	
			container:GetChildren()[1].Position = UDim2.fromOffset(35, 0)
		end
		
		local holder, pill = Inputs.stepper.make(theme, 35, step or 0.1, min or -1e9, max or 1e9, true)
		holder.Parent = area
		local data = DM.EnvGetCategory(catName)
		pill.Text = tostring(data[key] or 0)
		pill.Size = UDim2.new(0, 45, 1, 0)
		pill.Position = UDim2.new(0, 10, 0, 0)
		pill.LayoutOrder = layoutOrder or 3
		pill.FocusLost:Connect(function()
			local v = tonumber(pill.Text) or data[key] or 0
			DM.EnvSetCategoryPath(catName, {key}, v)
			pill.Text = tostring(DM.EnvGetCategory(catName)[key] or 0)
		end)
	end
	rowNumber("Altitude", "altitude", 0.1, 100, 3, 1,'rbxassetid://122279177826154')
	rowNumber("Slope",    "slope",    0.1, 100, 4, 1,'rbxassetid://106371549544932')
	rowNumber("Spacing",  "spacing",  1, 0, 999999, 1, 'rbxassetid://137270254765801')

	-- Rot Axis (X/Y/Z) + Max Deg (X/Y/Z)
	do
		local _, area = UI.PropertyRow(content, "Rot Axis", false)
		local d = DM.EnvGetCategory(catName)
		local rx = (d.rotAxis and d.rotAxis.X) and true or false
		local ry = (d.rotAxis and d.rotAxis.Y) and true or false
		local rz = (d.rotAxis and d.rotAxis.Z) and true or false
		local bx, setX = Checkbox.make(theme, rx, function(v) DM.EnvSetCategoryPath(catName, {"rotAxis","X"}, v) end)
		local by, setY = Checkbox.make(theme, ry, function(v) DM.EnvSetCategoryPath(catName, {"rotAxis","Y"}, v) end)
		local bz, setZ = Checkbox.make(theme, rz, function(v) DM.EnvSetCategoryPath(catName, {"rotAxis","Z"}, v) end)
		for _, t in ipairs({{"X", bx}, {"Y", by}, {"Z", bz}}) do
			local lab = Instance.new("TextLabel"); 
			lab.BackgroundTransparency=1; 
			lab.Text=t[1]; 
			lab.Font=Enum.Font.Gotham; 
			lab.TextSize=13; 
			lab.TextColor3=theme.TextSecondary; 
			lab.Size=UDim2.fromOffset(10,22)
			lab.Parent = area; 
			t[2].Parent = area
		end
	end
	do
		local _, area = UI.PropertyRow(content, "Max Deg")
		local d = DM.EnvGetCategory(catName)
		for _, ax in ipairs({"X","Y","Z"}) do
			local holder, tb = Inputs.stepper.make(theme, 35, 1, 0, 359)
			holder.Parent = area
			tb.Size = UDim2.new(0, 45, 1, 0)
			tb.Position = UDim2.new(0, 10, 0, 0)
			tb.Text = tostring(((d.maxDeg or {})[ax]) or 0)
			tb.FocusLost:Connect(function()
				local v = tonumber(tb.Text) or 0
				DM.EnvSetCategoryPath(catName, {"maxDeg", ax}, v)
				tb.Text = tostring((DM.EnvGetCategory(catName).maxDeg or {})[ax] or 0)
			end)
		end
	end

	-- Align to normal
	do
		local row = Instance.new("Frame"); row.Name="Row_Align"; row.BackgroundTransparency=1; row.Size=UDim2.new(1,0,0,30); row.Parent=content
		local lab = Inputs.label.make(theme, "Align to normal", 132); lab.Parent = row
		local fields = Instance.new("Frame"); fields.BackgroundTransparency=1; fields.Position=UDim2.new(0,140,0,0); fields.Size=UDim2.new(1,-148,1,0); fields.Parent=row
		local chk, set = Checkbox.make(theme, (DM.EnvGetCategory(catName).alignToNormal==true), function(v)
			DM.EnvSetCategoryPath(catName, {"alignToNormal"}, v)
		end)
		chk.AnchorPoint = Vector2.new(1,0); chk.Position = UDim2.new(1,0,0,0); chk.Parent = fields
	end
	-- Self Overlap
	do
		local row = Instance.new("Frame"); 
		row.Name="Row_SelfOverlap"; 
		row.BackgroundTransparency=1; 
		row.Size=UDim2.new(1,0,0,30); 
		row.Parent=content

		local lab = Inputs.label.make(theme, "Self Overlap", 132); 
		lab.Parent = row

		local fields = Instance.new("Frame")
		fields.BackgroundTransparency=1
		fields.Position=UDim2.new(0,140,0,0)
		fields.Size=UDim2.new(1,-148,1,0)
		fields.Parent=row

		local chk = (DM.EnvGetCategory(catName).selfOverlap==true)
		local box, set = Checkbox.make(theme, chk, function(v) DM.EnvSetCategoryPath(catName, {"selfOverlap"}, v) end)
		box.AnchorPoint = Vector2.new(1,0)
		box.Position = UDim2.new(1,0,0,0) 
		box.Parent = fields
	end

	-- Avoid footprint
	rowNumber("Avoid footprint", "avoidFootprint", 1, 0, 999999, 1, nil)

	-- Avoid Categories (sublist with +)
	do
		local bar = Instance.new("TextButton")
		bar.BackgroundColor3 = theme.ControlBgHover
		bar.BorderSizePixel = 0
		bar.Text = ""
		bar.Size = UDim2.new(1, -8, 0, 32)
		bar.Parent = content
		bar.LayoutOrder = 0
		Corners.make(bar, 6)

		local barLab = Instance.new("TextLabel")
		barLab.BackgroundTransparency = 1
		barLab.Text = "Avoid Categories"
		barLab.Font = Enum.Font.GothamMedium
		barLab.TextSize = 13
		barLab.TextColor3 = theme.ControlText
		barLab.TextXAlignment = Enum.TextXAlignment.Left
		barLab.Position = UDim2.fromOffset(35, 0)
		barLab.Size = UDim2.new(1, -36, 1, 0)
		barLab.Parent = bar

		local addBtn = Instance.new("TextButton")
		addBtn.Size = UDim2.fromOffset(20,20)
		addBtn.AnchorPoint = Vector2.new(0,0.5)
		addBtn.Position = UDim2.new(0, 8, 0.5, 0)
		addBtn.BackgroundColor3 = Color3.fromRGB(0,169,248)
		addBtn.AutoButtonColor = true
		addBtn.Text = "+"
		addBtn.Font = Enum.Font.GothamBold
		addBtn.TextSize = 16
		addBtn.TextColor3 = Color3.fromRGB(20,20,20)
		addBtn.Parent = bar
		Corners.make(addBtn, 5)

		local chevron = Instance.new("TextButton")
		chevron.Name = "Chevron"
		chevron.BackgroundTransparency = 1
		chevron.AutoButtonColor = false
		chevron.Text = "?"
		chevron.Font = Enum.Font.Gotham
		chevron.TextSize = 18
		chevron.TextColor3 = Color3.new(0.909804, 0.909804, 0.909804)
		chevron.AnchorPoint = Vector2.new(1, 0.5)
		chevron.Position = UDim2.new(1, -8, 0.5, 0)
		chevron.Size = UDim2.fromOffset(20, 20)
		chevron.ZIndex = 3
		chevron.Parent = bar

		local holder = Instance.new("ScrollingFrame")
		holder.Name = "AvoidCategoriesScroll"
		holder.BackgroundTransparency = 1
		holder.ScrollBarThickness = 3
		holder.Size = UDim2.new(1, 0, 0, 150)
		holder.ScrollBarImageColor3 = Color3.fromRGB(190,196,206)
		holder.CanvasSize = UDim2.new(0,0,0,0)
		holder.AutomaticCanvasSize = Enum.AutomaticSize.Y
		holder.ScrollBarImageColor3 = Color3.fromRGB(57, 62, 72)
		holder.ZIndex = 1010
		holder.Visible = false
		holder.Parent = content
		
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 6)
		list.Parent = holder

		-- NEW: grow up to 150px, collapse to 0 when empty
		local function resizeAvoid()
			local contentH = list.AbsoluteContentSize.Y
			local h = math.min(150, contentH)
			holder.Size = UDim2.new(1, 0, 0, h)
			holder.Visible = h > 0 
			
			chevron.Text = if h > 0 then '?' else '?'
		end
		list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resizeAvoid)
		task.defer(resizeAvoid)

		local function rowFor(i, name)
			local row = Instance.new("Frame")
			row.BackgroundColor3 = theme.ControlBg
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1,-8,0,30)
			row.Parent = holder
			Corners.make(row,6); 
			Strokes.make(row, theme.ControlBorder, 1)

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Font = Enum.Font.Gotham
			title.TextSize = 13
			title.TextColor3 = theme.ControlText
			title.Text = name ~= "" and name or "Pick category…"
			title.Position = UDim2.fromOffset(10,0)
			title.Size = UDim2.new(1, -80, 1, 0)
			title.Parent = row

			local del = Instance.new("TextButton")
			del.Size = UDim2.fromOffset(20,20)
			del.AnchorPoint = Vector2.new(1,0.5); del.Position = UDim2.new(1,-6,0.5,0)
			del.BackgroundColor3 = Color3.fromRGB(232,58,68)
			del.AutoButtonColor = false
			del.Text = "–"; del.Font = Enum.Font.GothamBold; del.TextSize = 14; del.TextColor3 = Color3.new(1,1,1)
			del.Parent = row; 
			Corners.make(del,4)

			-- double-click title to pick from dropdown
			title.InputBegan:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 and inp.UserInputState == Enum.UserInputState.Begin and inp.ClickCount == 2 then
					local dd = self.UI.ToolbarDropdown({ Width = 220, Height = 26, Text = title.Text })
					dd.Position = UDim2.fromOffset(8, 2); dd.Parent = row
					local others = {}
					for _, n in ipairs(DM.EnvListCategories()) do if n ~= catName then table.insert(others, n) end end
					self.UI.BuildDropdownList(dd, others, function(pick)
						-- guard duplicates
						local exists = false
						for _, old in ipairs(DM.EnvGetCategory(catName).avoid or {}) do
							if old == pick then exists = true break end
						end
						if not exists then
							DM.EnvSetCategoryPath(catName, {"avoid", i}, pick)
							title.Text = pick
						end
						self.UI.SetDropdownOpen(dd, false); dd:Destroy()
					end)
					self.UI.SetDropdownOpen(dd, true)
				end
			end)
			
			del.MouseButton1Click:Connect(function()
				ModalConfirm.Show(row:FindFirstAncestor("Root"), {
					title = "Remove Avoid",
					message = "Remove this avoid category?",
					okText = "Remove",
					primaryIsDestructive = true,
					onConfirm = function()
						DM.EnvRemoveAvoid(catName, i)
						row:Destroy()
						chevron.Text = if #holder:GetChildren() > 0 then '?' else '?'
					end
				})
			end)
		end

		local d = DM.EnvGetCategory(catName)
		for i, nm in ipairs(d.avoid or {}) do rowFor(i, nm) end

		addBtn.MouseButton1Click:Connect(function()
			local idx = ( #(DM.EnvGetCategory(catName).avoid or {}) ) + 1
			DM.EnvSetCategoryPath(catName, {"avoid", idx}, "")
			rowFor(idx, "")
		end)
		
		bar.MouseButton1Click:Connect(function() 
			if holder.Visible == true then
				holder.Visible = false
				chevron.Text = "?"
			else
				holder.Visible = true
				chevron.Text = "?"
			end
		end)

		chevron.MouseButton1Click:Connect(function() 
			if holder.Visible == true then
				holder.Visible = false
				chevron.Text = "?"
			else
				holder.Visible = true
				chevron.Text = "?"
			end
		end)		
	end

	-- Models list
	do
		local bar = Instance.new("TextButton")
		bar.BackgroundColor3 = theme.ControlBgHover
		bar.BorderSizePixel = 0
		bar.Text = ""
		bar.Size = UDim2.new(1, -8, 0, 32)
		bar.Parent = content
		Corners.make(bar, 6)

		local barLab = Instance.new("TextLabel")
		barLab.BackgroundTransparency = 1
		barLab.Text = "Models"
		barLab.Font = Enum.Font.GothamMedium
		barLab.TextSize = 13
		barLab.TextColor3 = theme.ControlText
		barLab.TextXAlignment = Enum.TextXAlignment.Left
		barLab.Position = UDim2.fromOffset(35, 0)
		barLab.Size = UDim2.new(1, -36, 1, 0)
		barLab.Parent = bar

		local addBtn = Instance.new("TextButton")
		addBtn.Size = UDim2.fromOffset(20,20)
		addBtn.AnchorPoint = Vector2.new(0,0.5)
		addBtn.Position = UDim2.new(0, 8, 0.5, 0)
		addBtn.BackgroundColor3 = Color3.fromRGB(0,169,248)
		addBtn.AutoButtonColor = true
		addBtn.Text = "+"
		addBtn.Font = Enum.Font.GothamBold
		addBtn.TextSize = 16
		addBtn.TextColor3 = Color3.fromRGB(20,20,20)
		addBtn.Parent = bar
		Corners.make(addBtn, 5)

		local chevron = Instance.new("TextButton")
		chevron.Name = "Chevron"
		chevron.BackgroundTransparency = 1
		chevron.AutoButtonColor = false
		chevron.Text = "?"
		chevron.Font = Enum.Font.Gotham
		chevron.TextSize = 18
		chevron.TextColor3 = Color3.new(0.909804, 0.909804, 0.909804)
		chevron.AnchorPoint = Vector2.new(1, 0.5)
		chevron.Position = UDim2.new(1, -8, 0.5, 0)
		chevron.Size = UDim2.fromOffset(20, 20)
		chevron.ZIndex = 3
		chevron.Parent = bar

		local wrap = Instance.new("ScrollingFrame")
		wrap.Name = "ModelsScroll"
		wrap.BackgroundTransparency = 1
		wrap.ScrollBarThickness = 3
		wrap.ScrollBarImageColor3 = Color3.fromRGB(190,196,206)
		wrap.CanvasSize = UDim2.new(0,0,0,0)
		wrap.AutomaticCanvasSize = Enum.AutomaticSize.Y
		wrap.ScrollBarImageColor3 = Color3.fromRGB(57, 62, 72)
		wrap.Size = UDim2.new(1, 0, 0, 150)
		wrap.ZIndex = 1010
		wrap.Visible = false
		wrap.Parent = content
		
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 6)
		list.Parent = wrap

		-- NEW: grow up to 150px, collapse to 0 when empty
		local function resizeModels()
			local contentH = list.AbsoluteContentSize.Y
			local h = math.min(150, contentH)
			wrap.Size = UDim2.new(1, 0, 0, h)
			wrap.Visible = h > 0
			chevron.Text = if h > 0 then '?' else '?'
		end
		list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resizeModels)
		task.defer(resizeModels)

		
		local Selection = game:GetService("Selection")
		local function addModelRow(idx, entry)
			entry = entry or { name = "Please pick model", ref = "" }
			local row = Instance.new("Frame")
			row.BackgroundColor3 = theme.ControlBg
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, -8, 0, 36)
			row.Parent = wrap
			Corners.make(row, 6); 
			Strokes.make(row, theme.ControlBorder, 1)

			local del = Instance.new("TextButton")
			del.Size = UDim2.fromOffset(20,20)
			del.Position = UDim2.fromOffset(6,8)
			del.BackgroundColor3 = Color3.fromRGB(232,58,68)
			del.AutoButtonColor = false
			del.Text = "–"; del.Font = Enum.Font.GothamBold; del.TextSize = 14; del.TextColor3 = Color3.new(1,1,1)
			del.Parent = row; 
			Corners.make(del,4)

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Font = Enum.Font.Gotham
			title.TextSize = 13
			title.TextColor3 = theme.ControlText
			title.Text = entry.name or "Please pick model"
			title.Position = UDim2.fromOffset(36, 0)
			title.Size = UDim2.new(1, -220, 1, 0)
			title.Parent = row

			local pick = Instance.new("TextButton")
			pick.Size = UDim2.new(0, 25, 0, 24)
			pick.AnchorPoint = Vector2.new(1,0.5); pick.Position = UDim2.new(1, -10, 0.5, 0)
			pick.BackgroundColor3 = theme.ControlBgActive
			pick.AutoButtonColor = true
			pick.Text = "..."
			pick.Font = Enum.Font.Gotham; pick.TextSize = 12; pick.TextColor3 = theme.ControlText
			pick.Parent = row
			Corners.make(pick, 6); 
			Strokes.make(pick, theme.ControlBorder, 1)

			local pickObjectValue = Instance.new("ObjectValue")
			pickObjectValue.Parent = pick


			pick.MouseButton1Click:Connect(function()
				ObjectPicker.Show(pick, pickObjectValue, {"Model"})
			end)

			del.MouseButton1Click:Connect(function()
				ModalConfirm.Show(row:FindFirstAncestor("Root"), {
					title = "Remove Model",
					message = "Remove this model entry?",
					okText = "Remove",
					primaryIsDestructive = true,
					onConfirm = function()
						DM.EnvRemoveModel(catName, idx)
						row:Destroy()					
					end
				})
			end)
		end

		local d = DM.EnvGetCategory(catName)
		for i, m in ipairs(d.models or {}) do addModelRow(i, m) end

		addBtn.MouseButton1Click:Connect(function()
			local idx = #(DM.EnvGetCategory(catName).models or {}) + 1
			DM.EnvSetCategoryPath(catName, {"models", idx}, { name = "Please pick model", ref = "" })
			addModelRow(idx, { name = "Please pick model", ref = "" })
		end)
		
		bar.MouseButton1Click:Connect(function() 
			if wrap.Visible == true then
				wrap.Visible = false
				chevron.Text = "?"
			else
				wrap.Visible = true
				chevron.Text = "?"
			end
		end)

		chevron.MouseButton1Click:Connect(function() 
			if wrap.Visible == true then
				wrap.Visible = false
				chevron.Text = "?"
			else
				wrap.Visible = true
				chevron.Text = "?"
			end
		end)		
	end
end

function EnvironProps:_refreshCategoryCard(card, catName, theme)
	-- For now we rebuild sublists entirely on DM changes (keeps code lean)
	-- You can add fine-grained field syncing later if desired.
	for _, ch in ipairs(card.Content:GetChildren()) do
		if ch:IsA("Frame") and ch.Name ~= "Header" then
			-- keep; we covered in _buildCategoryCard approach (simple path)
		end
	end
end

return EnvironProps
