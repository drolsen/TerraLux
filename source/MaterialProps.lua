-- MaterialProps (ModuleScript)
-- Comp-accurate Material edit-mode UI. Persists to DataManager per-biome.
local ColorPicker = require(script.Parent.UI.ColorPicker)
local MaterialPreview = require(script.Parent.UI.MaterialPreview)
local Theme = require(script.Parent:WaitForChild("UI").Theme)
local Corners = require(script.Parent.UI.Corners)
local Strokes = require(script.Parent.UI.Strokes)
local Inputs = require(script.Parent.UI.Inputs)

local MaterialProps = {}
MaterialProps.__index = MaterialProps

-- Small UI helpers local to this module
local function label(text, w)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = Theme.TextSecondary
	l.Size = UDim2.new(0, w or 80, 1, 0)
	return l
end

-- High-contrast header text for applied materials (blue header)
local function _setHeaderAppliedStyle(card: Frame, applied: boolean)
	local header = card:FindFirstChild("Header")
	if not header then return end
	local title  = header:FindFirstChild("Title")
	local chev   = header:FindFirstChild("Chevron")

	-- Dark text for contrast on blue; fallback to theme.ControlText when not applied
	local darkOnAccent = Color3.fromRGB(25, 27, 32) -- matches INPUT_TEXT used elsewhere
	local normal       = Theme.ControlText

	if title and title:IsA("TextLabel") then
		title.TextColor3 = applied and darkOnAccent or normal
	end
	if chev and chev:IsA("TextButton") then
		chev.TextColor3  = applied and darkOnAccent or normal
	end
end

-- Clear only the Material cards in the shared scroll area
function MaterialProps:_clearMaterialCards()
	for _, ch in ipairs(self.Parent:GetChildren()) do
		if ch:IsA("Frame") and ch:GetAttribute("CardMode") == "Materials" then
			ch:Destroy()
		end
	end
end

function MaterialProps.new(UI, DM, parentScroll)
	return setmetatable({
		UI = UI,
		DM = DM,
		Parent = parentScroll,
		_lastBiomeName = nil, -- track which biome these cards were built for
	}, MaterialProps)
end

-- Build whole Materials panel (cards per material). Cards carry CardMode="Materials".
function MaterialProps:build()
	if not Theme then return end

	-- if already built once, avoid duplicate cards
	for _, ch in ipairs(self.Parent:GetChildren()) do
		if ch:IsA("Frame") and ch:GetAttribute("CardMode") == "Materials" then ch:Destroy() end
	end

	for _, matName in ipairs(self.DM.ListMaterials()) do
		self:_buildOneMaterialCard(matName, Theme)
	end
end

-- Keep cards and controls in sync with DM (rebuild groups if counts differ)
function MaterialProps:loadFromDM()
	if not Theme then return end

	local currBiome = self.DM.GetSelectedBiome and self.DM.GetSelectedBiome() or nil

	-- True “no biome” state: remove any lingering Material cards
	if not currBiome then
		self:_clearMaterialCards()
		self._lastBiomeName = nil
		return
	end

	-- If the biome changed, rebuild fresh to avoid UI state bleed (expansion, checkmarks)
	if self._lastBiomeName ~= currBiome then
		self:_clearMaterialCards()
		self._lastBiomeName = currBiome
		self:build() -- uses DM state for this biome; cards start collapsed (Expanded=false)
		return
	end

	-- Same biome: just refresh
	for _, matName in ipairs(self.DM.ListMaterials()) do
		local card = self.Parent:FindFirstChild("Card_MAT_"..matName)
		if not card then
			self:_buildOneMaterialCard(matName)
		else
			self:_refreshMaterialCard(card, matName)
		end
	end
end


-- ===== internals =====
function MaterialProps:_buildOneMaterialCard(matName)
	local UI = self.UI
	local DM = self.DM

	local cardKey = "MAT_"..matName
	local savedExpanded = DM.GetCardExpanded(cardKey)

	local card, content = UI.PropertyCard({
		Title = matName, CardKey = "MAT_"..matName, ModeTag = "Materials", Expanded = false
	})
	card.Parent = self.Parent
	card.ZIndex = 0
	card.Name = "Card_MAT_"..matName
	card.Content.UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local header = card:FindFirstChild("Header")

	local function setHeaderAppliedVisual(isApplied: boolean)
		if not header then return end
		if isApplied then
			header.BackgroundColor3 = Theme.ControlBgBlueActive
		else
			header.BackgroundColor3 = Theme.ControlBgHover
		end
	end

	local function setAddEnabled(btn: TextButton, enabled: boolean)
		btn.AutoButtonColor = enabled
		btn.Active = enabled
		if enabled then
			btn.BackgroundColor3 = Color3.fromRGB(0, 169, 248)
			btn.TextColor3 = Color3.fromRGB(20,20,20)
		else
			btn.BackgroundColor3 = Color3.fromRGB(60,65,72)
			btn.TextColor3 = Color3.fromRGB(140,140,140)
		end
	end

	local mat = DM.GetMaterial(matName) or {}
	_setHeaderAppliedStyle(card, mat.apply == true)  -- set initial header text/chevron color

	-- Top composite (thumb + Apply + Layer + color row)
	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, -8, 0, 90)
	top.LayoutOrder = 1
	top.Parent = content

	local thumb = Instance.new("Frame")
	thumb.Size = UDim2.fromOffset(50,50)
	thumb.Position = UDim2.fromOffset(6, 2)
	thumb.BackgroundTransparency = 1
	Corners.make(thumb, 6)
	Strokes.make(thumb, Theme.ControlBorder, 1)
	thumb.Parent = top
	MaterialPreview.attach(thumb, matName)

	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromOffset(64, 2)
	right.Size = UDim2.new(1, -72, 1, 0)
	right.Parent = top

	-- Apply checkbox
	do
		local r = Instance.new("Frame"); r.BackgroundTransparency = 1; r.Size = UDim2.new(1,0,0,22); r.Parent = right
		local lab = label("Apply", 60); lab.Parent = r

		local box = Instance.new("Frame")
		box.Size = UDim2.fromOffset(20,20)
		box.AnchorPoint = Vector2.new(1,0)
		box.Position = UDim2.new(1, 0, 0, 0)
		box.BackgroundColor3 = Color3.fromRGB(255,255,255)
		box.BorderSizePixel = 0
		Corners.make(box, 4)
		box.Parent = r

		local mark = Instance.new("TextLabel")
		mark.BackgroundTransparency = 1
		mark.Size = UDim2.fromScale(1,1)
		mark.TextXAlignment = Enum.TextXAlignment.Center
		mark.TextYAlignment = Enum.TextYAlignment.Center
		mark.Font = Enum.Font.Gotham
		mark.TextSize = 16
		mark.TextColor3 = Color3.fromRGB(30,30,30)
		mark.Text = (mat.apply and "?") or ""
		mark.Parent = box

		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1,1)
		hit.AutoButtonColor = false
		hit.Text = ""
		hit.Parent = box

		local function applyChanged(nextVal)
			DM.SetMaterialPath(matName, {"apply"}, nextVal)
			mat = DM.GetMaterial(matName)
			mark.Text = (mat.apply and "?") or ""
			setHeaderAppliedVisual(mat.apply)
			-- gate add-button availability
			local bar = card.Content:FindFirstChild("MaterialFiltersBar")
			if bar then
				local addBtn = bar:FindFirstChild("AddFilterButton")
				if addBtn and addBtn:IsA("TextButton") then
					setAddEnabled(addBtn, mat.apply)
				end
			end
		end

		hit.MouseButton1Click:Connect(function()
			local nextVal = not mat.apply
			applyChanged(nextVal)
			_setHeaderAppliedStyle(card, mat.apply == true) 
		end)

		-- initial header visual
		setHeaderAppliedVisual(mat.apply)
	end

	-- Layer stepper
	do
		local r = Instance.new("Frame"); 
		r.BackgroundTransparency = 1; 
		r.Size = UDim2.new(1,0,0,22); 
		r.Parent = right

		local lab = label("Layer", 60); 
		lab.Position = UDim2.new(0, 0, 0, 30); 
		lab.Parent = r

		local step, pill = Inputs.stepper.make(Theme, 65, 1, 0, 99)
		step.AnchorPoint = Vector2.new(1,0); 
		step.Position = UDim2.new(1, 0, 0, 30); 
		step.Parent = r

		pill.Text = tostring(mat.layer or 1)
		pill.Size = UDim2.fromOffset(45, 20)
		pill.FocusLost:Connect(function()
			local n = tonumber(pill.Text) or 1
			DM.SetMaterialPath(matName, {"layer"}, n)
			pill.Text = tostring(DM.GetMaterial(matName).layer or 1)
			mat = DM.GetMaterial(matName)
		end)
	end

	-- Color swatch + [r,g,b]
	do
		local r = Instance.new("Frame"); r.BackgroundTransparency = 1; r.Size = UDim2.new(1,0,0,22); r.Parent = right
		local col = Instance.new("ImageButton")
		col.Size = UDim2.fromOffset(18,18)
		col.Position = UDim2.fromOffset(0, 60)
		col.BorderSizePixel = 0
		Corners.make(col, 3)
		col.Parent = r
		local cval = mat.color or {111,126,62}
		col.ImageTransparency = 1
		col.BackgroundColor3 = Color3.fromRGB(cval[1], cval[2], cval[3])

		col.MouseButton1Click:Connect(function()
			ColorPicker.Show(r:FindFirstAncestor("Root"), {
				title = "Material Color Picker",
				color = col.BackgroundColor3,
				onConfirm = function(c: Color3)
					col.BackgroundColor3 = c
					
					-- persist
					local matNameTrimmed = string.gsub(matName, "%s", "")
					DM.SetMaterialPath(matName, {"color"}, { math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5) })
					workspace.Terrain:SetMaterialColor(string.gsub(matNameTrimmed, "%s", ""), c)	
				end,
			})
		end)

		local txt = Instance.new("TextLabel")
		txt.BackgroundTransparency = 1
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.TextYAlignment = Enum.TextYAlignment.Center
		txt.Font = Enum.Font.Gotham
		txt.TextSize = 13
		txt.TextColor3 = Theme.TextSecondary
		txt.Text = string.format("  [%d, %d, %d]", cval[1], cval[2], cval[3])
		txt.Position = UDim2.fromOffset(35, 60)
		txt.Size = UDim2.new(1, -24, 1, 0)
		txt.Parent = r
	end

	-- "Material Filters" bar + [+]
	local bar = Instance.new("TextButton")
	bar.Name = "MaterialFiltersBar"
	bar.BackgroundColor3 = Theme.ControlBgHover
	bar.BorderSizePixel = 0
	bar.Text = ""
	bar.Size = UDim2.new(1, -8, 0, 32)
	bar.LayoutOrder = 2
	bar.Parent = content
	Corners.make(bar, 6)

	local barLab = Instance.new("TextLabel")
	barLab.BackgroundTransparency = 1
	barLab.Text = "Material Filters"
	barLab.Font = Enum.Font.GothamMedium
	barLab.TextSize = 13
	barLab.TextColor3 = Theme.ControlText
	barLab.TextXAlignment = Enum.TextXAlignment.Left
	barLab.Position = UDim2.fromOffset(35, 0)
	barLab.Size = UDim2.new(1, -36, 1, 0)
	barLab.Parent = bar

	local addBtn = Instance.new("TextButton")
	addBtn.Name = "AddFilterButton"
	addBtn.Size = UDim2.fromOffset(20,20)
	addBtn.AnchorPoint = Vector2.new(0,0.5)
	addBtn.Position = UDim2.new(0, 8, 0.5, 0)
	addBtn.BackgroundColor3 = Color3.fromRGB(0, 169, 248)
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

	-- Holder for filter groups
	local groupsHolder = Instance.new("Frame")
	groupsHolder.Name = "GroupsHolder"
	groupsHolder.BackgroundTransparency = 1
	groupsHolder.AutomaticSize = Enum.AutomaticSize.Y
	groupsHolder.Size = UDim2.new(1, 0, 0, 0)
	groupsHolder.LayoutOrder = 3
	groupsHolder.Visible = false
	groupsHolder.Parent = content

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.Parent = groupsHolder

	local function rebuildGroups()
		for _, ch in ipairs(groupsHolder:GetChildren()) do
			if ch:IsA("Frame") then ch:Destroy() end
		end
		local m = DM.GetMaterial(matName) or { filters = {} }
		for i, g in ipairs(m.filters or {}) do
			self:_buildOneFilterGroup(groupsHolder, matName, i, g)
		end
	end
	rebuildGroups()

	-- Gate add button by material.apply
	local function refreshAddGate()
		local applied = (DM.GetMaterial(matName) or {}).apply and true or false
		setAddEnabled(addBtn, applied)
	end
	refreshAddGate()

	addBtn.MouseButton1Click:Connect(function()
		if not ((DM.GetMaterial(matName) or {}).apply) then return end
		DM.AddMaterialFilter(matName)
		rebuildGroups()
	end)
	
	bar.MouseButton1Click:Connect(function() 
		if groupsHolder.Visible == true then
			groupsHolder.Visible = false
			chevron.Text = "?"
		else
			groupsHolder.Visible = true
			chevron.Text = "?"
		end
	end)

	chevron.MouseButton1Click:Connect(function() 
		if groupsHolder.Visible == true then
			groupsHolder.Visible = false
			chevron.Text = "?"
		else
			groupsHolder.Visible = true
			chevron.Text = "?"
		end
	end)	
end

function MaterialProps:_refreshMaterialCard(card, matName)
	local DM = self.DM
	local mat = DM.GetMaterial(matName) or {}
	_setHeaderAppliedStyle(card, mat.apply == true)  -- keep header text/chevron in sync

	-- Header applied color + Apply gate for Add button
	local header = card:FindFirstChild("Header")
	if header then header.BackgroundColor3 = mat.apply and Theme.ControlBgBlueActive or Theme.ControlBgHover end
	local bar = card.Content and card.Content:FindFirstChild("MaterialFiltersBar")
	if bar then
		local addBtn = bar:FindFirstChild("AddFilterButton")
		if addBtn and addBtn:IsA("TextButton") then
			addBtn.Active = mat.apply; addBtn.AutoButtonColor = mat.apply
			if mat.apply then
				addBtn.BackgroundColor3 = Color3.fromRGB(0,169,248); addBtn.TextColor3 = Color3.fromRGB(20,20,20)
			else
				addBtn.BackgroundColor3 = Color3.fromRGB(60,65,72); addBtn.TextColor3 = Color3.fromRGB(140,140,140)
			end
		end
	end

	-- Apply checkbox mark
	local top = card.Content and card.Content:FindFirstChildOfClass("Frame")
	if top then
		local right = top:FindFirstChildWhichIsA("Frame")
		if right then
			local applyRow = right:GetChildren()[1]
			if applyRow then
				local chk = applyRow:FindFirstChildWhichIsA("Frame")
				if chk then
					local mark = chk:FindFirstChildOfClass("TextLabel")
					if mark then mark.Text = (mat.apply and "?") or "" end
				end
			end
			local layerRow = right:GetChildren()[2]
			if layerRow then
				local step = layerRow:FindFirstChildWhichIsA("Frame")
				if step and step:FindFirstChildOfClass("TextBox") then
					step:FindFirstChildOfClass("TextBox").Text = tostring(mat.layer or 1)
				end
			end
			local colorRow = right:GetChildren()[3]
			if colorRow then
				local col = colorRow:FindFirstChildOfClass("ImageButton")
				local txt = colorRow:FindFirstChildOfClass("TextLabel")
				local cval = mat.color or {111,126,62}
				if col then col.BackgroundColor3 = Color3.fromRGB(cval[1],cval[2],cval[3]) end
				if txt then txt.Text = string.format("  [%d, %d, %d]", cval[1], cval[2], cval[3]) end
			end
		end
	end

	-- Rebuild groups to match DM
	local groupsHolder = card.Content and card.Content:FindFirstChild("GroupsHolder")
	if groupsHolder then
		for _, ch in ipairs(groupsHolder:GetChildren()) do
			if ch:IsA("Frame") then ch:Destroy() end
		end
		local list = groupsHolder:FindFirstChildOfClass("UIListLayout")
		if not list then list = Instance.new("UIListLayout"); list.Padding = UDim.new(0, 6); list.Parent = groupsHolder end
		local m = DM.GetMaterial(matName) or { filters = {} }
		for i, g in ipairs(m.filters or {}) do
			self:_buildOneFilterGroup(groupsHolder, matName, i, g)
		end
	end
end

-- Single filter group with working expand/collapse
function MaterialProps:_buildOneFilterGroup(parent, matName, idx, g)
	local DM = self.DM

	local wrap = Instance.new("Frame")
	wrap.Name = "FilterGroup_"..idx
	wrap.BackgroundColor3 = Theme.ControlBg
	wrap.BorderSizePixel = 0
	wrap.AutomaticSize = Enum.AutomaticSize.Y
	wrap.Size = UDim2.new(1, -8, 0, 0)
	wrap.Position = UDim2.fromOffset(4,0)
	wrap.Parent = parent
	
	local Padding = Instance.new("UIPadding")
	-- Padding.PaddingTop = UDim.new(0, 10)
	Padding.PaddingBottom = UDim.new(0, 5)
	Padding.Parent = wrap
	
	Corners.make(wrap, 6); 
	Strokes.make(wrap, Theme.ControlBorder, 1)

	-- Group header: red minus + name + caret
	local header = Instance.new("Frame")
	header.BackgroundColor3 = Theme.ControlBgActive
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, -8, 0, 26)
	header.Position = UDim2.fromOffset(4,4)
	header.Parent = wrap
	Corners.make(header, 6)

	local minus = Instance.new("TextButton")
	minus.Size = UDim2.fromOffset(20,20)
	minus.Position = UDim2.fromOffset(6,3)
	minus.BackgroundColor3 = Color3.fromRGB(232, 58, 68)
	minus.AutoButtonColor = false
	minus.Text = "–"
	minus.Font = Enum.Font.GothamBold
	minus.TextSize = 14
	minus.TextColor3 = Color3.fromRGB(255, 255, 255)
	minus.ZIndex = 20
	minus.Parent = header
	Corners.make(minus, 4)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Font = Enum.Font.GothamMedium
	nameLbl.TextSize = 13
	nameLbl.TextColor3 = Theme.ControlText
	nameLbl.Text = g.name or "Custom Filter Name"
	nameLbl.Position = UDim2.fromOffset(32, 0)
	nameLbl.Size = UDim2.new(1, -60, 1, 0)
	nameLbl.Parent = header

	local caret = Instance.new("TextLabel")
	caret.BackgroundTransparency = 1
	caret.Text = "?"
	caret.Font = Enum.Font.Gotham
	caret.TextSize = 14
	caret.TextColor3 = Theme.ControlText
	caret.AnchorPoint = Vector2.new(1,0.5)
	caret.Position = UDim2.new(1, -8, 0.5, 0)
	caret.Size = UDim2.fromOffset(16,16)
	caret.Parent = header

	local headerHit = Instance.new("TextButton")
	headerHit.BackgroundTransparency = 1
	headerHit.Text = ""
	headerHit.AutoButtonColor = false
	headerHit.Size = UDim2.fromScale(1,1)
	headerHit.Parent = header

	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.AutomaticSize = Enum.AutomaticSize.Y
	inner.Position = UDim2.fromOffset(4, 34)
	inner.Size = UDim2.new(1, -8, 0, 0)
	inner.Parent = wrap

	local innerList = Instance.new("UIListLayout")
	innerList.Padding = UDim.new(0, 6)
	innerList.Parent = inner

	-- default expanded true for existing UI (feels natural), but you can flip here if needed
	local expanded = true
	local function setExpanded(on)
		expanded = on
		inner.Visible = on
		caret.Text = on and "?" or "?"
	end
	setExpanded(true)

	local function addRow(labelText, key, value, iconId)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 24)
		row.Parent = inner

		local left = Instance.new("Frame")
		left.BackgroundTransparency = 1
		left.Size = UDim2.new(1, -110, 1, 0)
		left.Parent = row
		
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Image = iconId
		icon.Size = UDim2.new(0, 20, 0, 20)
		icon.Position = UDim2.fromOffset(8, 0)
		icon.Parent = left

		local lab = Instance.new("TextLabel")
		lab.BackgroundTransparency = 1
		lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.TextYAlignment = Enum.TextYAlignment.Center
		lab.Font = Enum.Font.Gotham
		lab.TextSize = 13
		lab.TextColor3 = Theme.TextSecondary
		lab.Text = labelText
		lab.Position = UDim2.fromOffset(36, 0)
		lab.Size = UDim2.new(1, -8, 1, 0)
		lab.Parent = left

		local right = Instance.new("Frame")
		right.BackgroundTransparency = 1
		right.Size = UDim2.new(0, 110, 1, 0)
		right.AnchorPoint = Vector2.new(1,0)
		right.Position = UDim2.new(1, 0, 0, 0)
		right.Parent = row

		local step, pill = Inputs.stepper.make(Theme, 70, 0.1, 0.0, 100)
		step.AnchorPoint = Vector2.new(1,0)
		step.Position = UDim2.new(1, -8, 0, 1)
		step.Parent = right
		pill.Text = tostring(value or 0.0)
		pill.Size = UDim2.fromOffset(55, 20)
		pill.FocusLost:Connect(function()
			local v = tonumber(pill.Text) or value or 0.0
			DM.SetMaterialPath(matName, {"filters", idx, key}, v)
			local nv = DM.GetMaterial(matName).filters[idx][key]
			pill.Text = tostring(nv)
		end)
	end

	addRow("Altitude", "altitude", g.altitude, 'rbxassetid://122279177826154')
	addRow("Slope",    "slope",    g.slope, 'rbxassetid://106371549544932')
	addRow("Curve",    "curve",    g.curve, 'rbxassetid://127081563127956')

	minus.MouseButton1Click:Connect(function()
		print("THINGS WERE CLICKED!")
		DM.RemoveMaterialFilter(matName, idx)
		wrap:Destroy()
	end)

	-- working expand/collapse
	headerHit.MouseButton1Click:Connect(function() setExpanded(not inner.Visible) end)
end

return MaterialProps
