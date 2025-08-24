-- TerraLux.main.plugin.lua
-- Layout + toolbar + DataManager + Biome/Material edit modes (comp-accurate Materials UI)

if not plugin then error("Run as a Roblox Studio Plugin.") end

-- ========= CONSTANTS =========
local TOOLBAR_H, TOOLBAR_PAD_Y, CTRL_H = 56, 8, 27
local CORNER_RADIUS = 8
local PROPERTIES_W, MIN_PREVIEW_W = 280, 320
local MIN_WIDGET_W, MIN_WIDGET_H = PROPERTIES_W + MIN_PREVIEW_W, 320

-- ========= DOCK WIDGET =========
local DockInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, true, false,
	1200, 800, MIN_WIDGET_W, MIN_WIDGET_H
)
local widget = plugin:CreateDockWidgetPluginGui("TerraLux_Dock", DockInfo)
widget.Title, widget.Name = "TerraLux", "TerraLux_Dock"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Global

local studioToolbar = plugin:CreateToolbar("TerraLux")
local toggleButton  = studioToolbar:CreateButton("", "", "rbxassetid://120243856670994")
toggleButton.Click:Connect(function() widget.Enabled = true end)

local propsScroll = Instance.new("ScrollingFrame")

-- ========= REQUIRE MODULES =========
local UI  = require(script:WaitForChild("UI"))
local DM  = require(script:WaitForChild("DataManager"))
local BiomeProps = require(script:WaitForChild("BiomeProps"))
local MaterialProps = require(script:WaitForChild("MaterialProps"))
local ModalConfirm = require(script.UI:WaitForChild("ModalConfirm"))
local EnvironProps = require(script:WaitForChild("EnvironProps")) 
local StampsProps  = require(script:WaitForChild("StampProps"))
local Theme = require(script:WaitForChild("UI").Theme)

UI.setCornerRadius(CORNER_RADIUS)

local biomeUI = BiomeProps.new(UI, DM, propsScroll)
local materialUI = MaterialProps.new(UI, DM, propsScroll)
local environUI = EnvironProps.new(UI, DM, propsScroll)
local stampsUI  = StampsProps.new(UI, DM, propsScroll)

-- ========= ROOT =========
local currentMode = "Biome" -- default once a biome is selected
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundColor3 = Theme.WindowBg
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1,1)
root.Parent = widget

-- Click-off shield (closes dropdowns when visible)
local Overlay = Instance.new("TextButton")
Overlay.Name = "Overlay"
Overlay.BackgroundTransparency = 1
Overlay.AutoButtonColor = false
Overlay.Text = ""
Overlay.Visible = false
Overlay.ZIndex = 500
Overlay.Size = UDim2.fromScale(1,1)
Overlay.Parent = root

-- ========= TOOLBAR =========
local toolbar = Instance.new("Frame")
toolbar.Name = "MainToolbar"
toolbar.BackgroundColor3 = Theme.ToolbarBg
toolbar.Size = UDim2.new(1, 0, 1, 0)
toolbar.BorderSizePixel = 0
toolbar.Parent = root
toolbar.ClipsDescendants = false

local toolbarLine = Instance.new("Frame")
toolbarLine.Name = "ToolbarBottomLine"
toolbarLine.BorderSizePixel = 0
toolbarLine.BackgroundColor3 = Theme.ToolbarLine
toolbarLine.Parent = toolbar

-- Left
local leftFrame = Instance.new("Frame")
leftFrame.Name = "leftFrame"
leftFrame.BackgroundTransparency = 1
leftFrame.AnchorPoint = Vector2.new(0, 0.5)
leftFrame.Position = UDim2.new(0, 0, 0.5, 0)
leftFrame.Size = UDim2.new(0, PROPERTIES_W, 1, -(TOOLBAR_PAD_Y*2))
leftFrame.Parent = toolbar
leftFrame.ClipsDescendants = false

local leftPad = Instance.new("UIPadding")
leftPad.PaddingLeft, leftPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
leftPad.Parent = leftFrame

local leftList = Instance.new("UIListLayout")
leftList.FillDirection = Enum.FillDirection.Horizontal
leftList.HorizontalAlignment = Enum.HorizontalAlignment.Left
leftList.VerticalAlignment = Enum.VerticalAlignment.Center
leftList.Padding = UDim.new(0, 8)
leftList.SortOrder = Enum.SortOrder.LayoutOrder
leftList.Parent = leftFrame

-- Right
local rightFrame = Instance.new("Frame")
rightFrame.Name = "RightFrame"
rightFrame.BackgroundTransparency = 1
rightFrame.AnchorPoint = Vector2.new(0, 0.5)
rightFrame.Position = UDim2.new(0, PROPERTIES_W, 0.5, 0)
rightFrame.Size = UDim2.new(1, -PROPERTIES_W, 1, 0)
rightFrame.Parent = toolbar

local rightList = Instance.new("UIListLayout")
rightList.FillDirection = Enum.FillDirection.Horizontal
rightList.HorizontalAlignment = Enum.HorizontalAlignment.Center
rightList.VerticalAlignment = Enum.VerticalAlignment.Center
rightList.Padding = UDim.new(0, 8)
rightList.SortOrder = Enum.SortOrder.LayoutOrder
rightList.Parent = rightFrame

-- Divider
local midSep = Instance.new("Frame")
midSep.Name = "MidSeparator"
midSep.BorderSizePixel = 0
midSep.BackgroundColor3 = Theme.ToolbarLine
midSep.Parent = leftFrame

-- ===== LEFT: Biome dropdown then + icon
local DROPDOWN_W = PROPERTIES_W - (35 * 2) - 40
local BiomeDropdown = UI.ToolbarDropdown({
	Name   = "BiomeDropdown",
	Width  = DROPDOWN_W,
	Height = CTRL_H,
	Position = UDim2.new(0, 40, 0, 0),
	Text   = "No Biomes",
	Disabled = true,
})
BiomeDropdown.LayoutOrder = 1
BiomeDropdown.Parent = leftFrame

local AddBiomeBtn = UI.ToolbarButton({
	Name   = "AddBiomeButton",
	BackgroundColor = Color3.new(0, 0.670588, 1),
	Width  = 32, Height = CTRL_H,
	Icon   = "rbxassetid://115837812053156",
	Disabled = false,
})
AddBiomeBtn.LayoutOrder = 2
AddBiomeBtn.Parent = leftFrame
UI.SetDropdownEnabled(BiomeDropdown, false)

-- ===== RIGHT: mode buttons
local BtnWorld         = UI.ToolbarButton({ Name="BtnWorld",         Width=32, Height=CTRL_H, Icon="rbxassetid://99307674544588",   Disabled=false })
local BtnBiome         = UI.ToolbarButton({ Name="BtnBiome",         Width=51, Height=CTRL_H, Icon="rbxassetid://116289659968801",  Disabled=true  })
local BtnMaterials     = UI.ToolbarButton({ Name="BtnMaterials",     Width=51, Height=CTRL_H, Icon="rbxassetid://139531969002992",  Disabled=true  })
local BtnEnvironmental = UI.ToolbarButton({ Name="BtnEnvironmental", Width=51, Height=CTRL_H, Icon="rbxassetid://123608178065610",  Disabled=true  })
local BtnStamps        = UI.ToolbarButton({ Name="BtnStamps",        Width=51, Height=CTRL_H, Icon="rbxassetid://97603543316227",   Disabled=true  })
local BtnLighting      = UI.ToolbarButton({ Name="BtnLighting",      Width=51, Height=CTRL_H, Icon="rbxassetid://133213440281341",  Disabled=true  })
local BtnCaves         = UI.ToolbarButton({ Name="BtnCaves",         Width=51, Height=CTRL_H, Icon="rbxassetid://89571371677122",   Disabled=true  })

BtnWorld.LayoutOrder, midSep.LayoutOrder = 2, 2
BtnBiome.LayoutOrder, BtnMaterials.LayoutOrder, BtnEnvironmental.LayoutOrder = 3, 4, 5
BtnStamps.LayoutOrder, BtnLighting.LayoutOrder, BtnCaves.LayoutOrder = 6, 7, 8

BtnWorld.Parent = leftFrame
BtnBiome.Parent = rightFrame
BtnMaterials.Parent = rightFrame
BtnEnvironmental.Parent = rightFrame
BtnStamps.Parent = rightFrame
BtnLighting.Parent = rightFrame
BtnCaves.Parent = rightFrame
UI.SetButtonSelected(BtnWorld, true)

-- ========= BODY =========
local body = Instance.new("Frame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.Parent = root

local props = Instance.new("Frame")
props.Name = "PropertiesWindow"
props.BackgroundColor3 = Theme.PropsBg
props.Parent = body
props.ZIndex = 1

local propsLine = Instance.new("Frame")
propsLine.Name = "PropsRightLine"
propsLine.BackgroundColor3 = Theme.PropsLine
propsLine.Parent = props

propsScroll.Name = "PropsScroll"
propsScroll.BackgroundTransparency = 1
propsScroll.ScrollBarThickness = 3
propsScroll.ScrollBarImageColor3 = Color3.fromRGB(190,196,206)
propsScroll.CanvasSize = UDim2.new(0,0,0,0)
propsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
propsScroll.ScrollBarImageColor3 = Theme.ToolbarLine
propsScroll.Parent = props
propsScroll.ZIndex = 5

local propsPadding = Instance.new("UIPadding")
propsPadding.PaddingTop = UDim.new(0, 10)
propsPadding.PaddingLeft = UDim.new(0, 10)
propsPadding.PaddingBottom = UDim.new(0, 10)
propsPadding.Parent = propsScroll

local scrollTrack = Instance.new("Frame")
scrollTrack.Name = "PropsScrollTrack"
scrollTrack.AnchorPoint = Vector2.new(0,0)
scrollTrack.BackgroundColor3 = Color3.fromRGB(22,24,29)
scrollTrack.BorderSizePixel = 0
scrollTrack.ZIndex = 5
scrollTrack.Parent = props

-- make the properties list behave like the comps
local propsList = Instance.new("UIListLayout")
propsList.FillDirection = Enum.FillDirection.Vertical
propsList.HorizontalAlignment = Enum.HorizontalAlignment.Left
propsList.VerticalAlignment = Enum.VerticalAlignment.Top
propsList.Padding = UDim.new(0, 10)
propsList.SortOrder = Enum.SortOrder.LayoutOrder
propsList.Parent = propsScroll

local propsPad = Instance.new("UIPadding")
propsPad.PaddingTop = UDim.new(0, 10)
propsPad.PaddingLeft = UDim.new(0, 8)
propsPad.PaddingRight = UDim.new(0, 6)
propsPad.Parent = propsScroll

local preview = Instance.new("Frame")
preview.Name = "PreviewWindow"
preview.BackgroundColor3 = Theme.PreviewBg
preview.ClipsDescendants = true
preview.Parent = body

local previewBg = Instance.new("ImageLabel")
previewBg.Name = "BackgroundLogo"
previewBg.AnchorPoint = Vector2.new(0.5, 0.5)
previewBg.Position = UDim2.new(0.5, 0, 0.5, 0)
previewBg.BackgroundTransparency = 1
previewBg.ScaleType = Enum.ScaleType.Stretch
previewBg.Image = 'rbxassetid://120243856670994'
previewBg.Size = UDim2.new(0, 500, 0, 275)
previewBg.Parent = preview

local previewBgSizeConstraint = Instance.new("UISizeConstraint")
previewBgSizeConstraint.MaxSize = Vector2.new(500, 275)
previewBgSizeConstraint.MinSize = Vector2.new(50, 28)
previewBgSizeConstraint.Parent = previewBg

-- ========= INLINE "NEW BIOME" BAR =========
local NewBiomeBar = Instance.new("Frame")
NewBiomeBar.Name = "NewBiomeBar"
NewBiomeBar.BackgroundTransparency = 1
NewBiomeBar.Size = UDim2.fromOffset(DROPDOWN_W + 32 + 8, CTRL_H)
NewBiomeBar.Visible = false
NewBiomeBar.LayoutOrder = 1
NewBiomeBar.Parent = leftFrame

local nbLayout = Instance.new("UIListLayout")
nbLayout.FillDirection = Enum.FillDirection.Horizontal
nbLayout.Padding = UDim.new(0, 8)
nbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
nbLayout.SortOrder = Enum.SortOrder.LayoutOrder
nbLayout.Parent = NewBiomeBar

local NewBiomeInput = UI.ToolbarTextInput({
	Name = "NewBiomeInput", Width = DROPDOWN_W, Height = CTRL_H, Placeholder = "Biome name...",
})
NewBiomeInput.LayoutOrder = 1
NewBiomeInput.Parent = NewBiomeBar

local NewBiomeOK = UI.ToolbarButton({
	Name = "NewBiomeOK", Width = 42, Height = CTRL_H, Text = "OK", Disabled = false, TextAlign = "Center"
})
NewBiomeOK.LayoutOrder = 2
NewBiomeOK.Parent = NewBiomeBar

local NewBiomeCancel = UI.ToolbarButton({
	Name = "NewBiomeCancel", Width = 72, Height = CTRL_H, Text = "Cancel", Disabled = false, TextAlign = "Center"
})
NewBiomeCancel.LayoutOrder = 3
NewBiomeCancel.Parent = NewBiomeBar

-- build empty shells (they'll populate after DM.Init)
biomeUI:build()
materialUI:build()
environUI:build()

-- ========= HELPERS =========
local function showMode(mode)
	currentMode = mode
	UI.SetButtonSelected(BtnBiome,          mode == "Biome")
	UI.SetButtonSelected(BtnMaterials,      mode == "Materials")
	UI.SetButtonSelected(BtnWorld,          mode == "World")
	UI.SetButtonSelected(BtnEnvironmental,  mode == "Environmental")
	UI.SetButtonSelected(BtnStamps,         mode == "Stamps") -- NEW

	for _, ch in ipairs(propsScroll:GetChildren()) do
		if ch:IsA("Frame") then
			local tag = ch:GetAttribute("CardMode")
			if tag then
				ch.Visible = (tag == mode)
			end
		end
	end

	-- NEW: lazy init/refresh when entering Stamps
	if mode == "Stamps" then
		stampsUI:build()
		stampsUI:loadFromDM()
	end
end


-- hide all properties (true “no biomes” state)
local function hideAllPropertyCards()
	for _, ch in ipairs(propsScroll:GetChildren()) do
		if ch:IsA("Frame") then
			local tag = ch:GetAttribute("CardMode")
			if tag then ch.Visible = false end
		end
	end
end

-- ========= LAYOUT =========
local function relayout()
	local wSize = root.AbsoluteSize
	toolbar.Position = UDim2.fromOffset(0, 0)
	toolbar.Size     = UDim2.fromOffset(wSize.X, TOOLBAR_H)
	toolbarLine.Position = UDim2.fromOffset(0, TOOLBAR_H-1)
	toolbarLine.Size     = UDim2.fromOffset(wSize.X, 1)

	local sepH = TOOLBAR_H - ((TOOLBAR_PAD_Y / 2) * 6)
	midSep.Size     = UDim2.fromOffset(2, sepH)
	midSep.Position = UDim2.fromOffset(0, TOOLBAR_PAD_Y)

	local bodyH = math.max(0, wSize.Y - TOOLBAR_H)
	body.Position = UDim2.fromOffset(0, TOOLBAR_H)
	body.Size     = UDim2.fromOffset(wSize.X, bodyH)

	local propsW = PROPERTIES_W
	props.Position = UDim2.fromOffset(0, 0)
	props.Size     = UDim2.fromOffset(propsW, bodyH)
	propsLine.Position = UDim2.fromOffset(propsW-1, 0)
	propsLine.Size     = UDim2.fromOffset(1, bodyH)
	propsScroll.Position = UDim2.fromOffset(0, 0)
	propsScroll.Size     = UDim2.fromOffset(propsW-1, bodyH)

	local previewX = math.max(MIN_PREVIEW_W, wSize.X - propsW)
	preview.Position = UDim2.fromOffset(propsW, 0)
	preview.Size     = UDim2.fromOffset(previewX, bodyH)

	Overlay.Position = UDim2.fromOffset(0, 0)
	Overlay.Size     = UDim2.fromOffset(wSize.X, wSize.Y)
	Overlay.ZIndex = 1

	scrollTrack.Position = UDim2.new(1, 0, 0, 0)
	scrollTrack.Size = UDim2.new(0, propsScroll.ScrollBarThickness, 1, 0)
end
leftFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
rightFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
widget:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

-- ========= DATA & UI SYNC =========
local function setModeButtonsEnabled(enabled)
	UI.SetButtonEnabled(BtnWorld,         enabled) -- disable World too when no biome
	UI.SetButtonEnabled(BtnBiome,         enabled)
	UI.SetButtonEnabled(BtnMaterials,     enabled)
	UI.SetButtonEnabled(BtnEnvironmental, enabled)
	UI.SetButtonEnabled(BtnStamps,        enabled)
	UI.SetButtonEnabled(BtnLighting,      enabled)
	UI.SetButtonEnabled(BtnCaves,         enabled)
end

local function postDeleteSelectFallback()
	local names = DM.ListBiomes()
	if #names > 0 then
		DM.SelectBiome(names[1])
	end
end

local function applySelectionStateAfterChange()
	local selected = DM.GetSelectedBiome()
	if selected then
		UI.SetDropdownEnabled(BiomeDropdown, true)
		UI.SetDropdownText(BiomeDropdown, selected)
		setModeButtonsEnabled(true)
		biomeUI:loadFromDM()
		materialUI:loadFromDM()
		environUI:loadFromDM()
		showMode("Biome")
	else
		UI.SetDropdownEnabled(BiomeDropdown, false)
		UI.SetDropdownText(BiomeDropdown, "No Biomes")
		setModeButtonsEnabled(false)
		hideAllPropertyCards()
	end
end

local function rebuildBiomeDropdown()
	local names = DM.ListBiomes()
	UI.BuildDropdownListWithDelete(BiomeDropdown, names,
		-- onSelect
		function(name)
			DM.SelectBiome(name)
			UI.SetDropdownText(BiomeDropdown, name)
			UI.SetDropdownOpen(BiomeDropdown, false)
			Overlay.Visible = false
			setModeButtonsEnabled(true)
			biomeUI:loadFromDM()
			materialUI:loadFromDM()
			environUI:loadFromDM()
			showMode("Biome")
		end,
		-- onDelete
		function(name)
			ModalConfirm.Show(root, {
				title = "Delete Biome",
				message = ("Are you sure you want to delete “%s”? This cannot be undone."):format(name),
				okText = "Delete",
				cancelText = "Cancel",
				primaryIsDestructive = true,
				onConfirm = function()
					DM.DeleteBiome(name)
					postDeleteSelectFallback()
					rebuildBiomeDropdown()
					applySelectionStateAfterChange()
					UI.SetDropdownOpen(BiomeDropdown, false)
					Overlay.Visible = false
				end,
				onCancel = function() end,
			})
		end
	)
end

local function refreshBiomeUIFromData()
	local ok, state = DM.Init(plugin)
	if not ok then
		warn("DataManager init failed:", state)
		UI.SetDropdownEnabled(BiomeDropdown, false)
		setModeButtonsEnabled(false)
		return
	end

	rebuildBiomeDropdown()
	applySelectionStateAfterChange()
end

-- ========= ADD BIOME UX =========
local function showNewBiomeBar(show)
	NewBiomeBar.Visible = show
	BiomeDropdown.Visible = not show
	AddBiomeBtn.Visible = not show

	-- Hide mid divider & World button while inline create UI is up
	midSep.Visible = not show
	BtnWorld.Visible = not show

	if show then UI.FocusInput(NewBiomeInput) end
end

local function trim(s)
	if not s then return "" end
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

local function flashInvalid(frame)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if not stroke then return end
	local old = stroke.Color
	stroke.Color = Color3.fromRGB(200, 70, 70)
	task.delay(0.15, function() stroke.Color = old end)
end

local function tryCreateBiome()
	local name = trim(UI.GetInputText(NewBiomeInput))
	if name == "" or name:lower() == "biome name..." then
		flashInvalid(NewBiomeInput) ; return
	end
	if DM.BiomeExists(name) then
		flashInvalid(NewBiomeInput) ; return
	end

	local ok, err = DM.CreateBiome(name)
	if not ok then warn("CreateBiome failed:", err) ; flashInvalid(NewBiomeInput) ; return end

	DM.SelectBiome(name)
	rebuildBiomeDropdown()
	UI.SetDropdownEnabled(BiomeDropdown, true)
	UI.SetDropdownText(BiomeDropdown, name)
	setModeButtonsEnabled(true)
	showNewBiomeBar(false)
	-- Clear input so the next time it's empty
	local inputBox = NewBiomeInput:FindFirstChild("Input")
	if inputBox and inputBox:IsA("TextBox") then
		inputBox.Text = ""
	end

	biomeUI:loadFromDM()
	materialUI:loadFromDM()
	environUI:loadFromDM()
	showMode("Biome")
end

-- Hookups
do
	local addClick = AddBiomeBtn:FindFirstChild("ClickArea")
	if addClick and addClick:IsA("TextButton") then
		addClick.MouseButton1Click:Connect(function() showNewBiomeBar(true) end)
	end

	local okClick = NewBiomeOK:FindFirstChild("ClickArea")
	if okClick and okClick:IsA("TextButton") then
		okClick.MouseButton1Click:Connect(tryCreateBiome)
	end

	local cancelClick = NewBiomeCancel:FindFirstChild("ClickArea")
	if cancelClick and cancelClick:IsA("TextButton") then
		cancelClick.MouseButton1Click:Connect(function()
			showNewBiomeBar(false)
			-- Clear any previously typed name on cancel as well
			local inputBox = NewBiomeInput:FindFirstChild("Input")
			if inputBox and inputBox:IsA("TextBox") then
				inputBox.Text = ""
			end
		end)
	end

	local inputBox = NewBiomeInput:FindFirstChild("Input")
	if inputBox and inputBox:IsA("TextBox") then
		inputBox.FocusLost:Connect(function(enterPressed)
			if enterPressed then tryCreateBiome() end
		end)
	end

	-- Dropdown open/close
	local ddClick = BiomeDropdown:FindFirstChild("ClickArea")
	if ddClick and ddClick:IsA("TextButton") then
		ddClick.MouseButton1Click:Connect(function()
			if not BiomeDropdown:GetAttribute("Enabled") then return end
			rebuildBiomeDropdown()
			local holder = BiomeDropdown:FindFirstChild("ListHolder")
			local willOpen = not (holder and holder.Visible)
			UI.SetDropdownOpen(BiomeDropdown, willOpen)
			Overlay.Visible = willOpen
		end)
	end

	local biomeClick = BtnBiome:FindFirstChild("ClickArea")
	if biomeClick and biomeClick:IsA("TextButton") then
		biomeClick.MouseButton1Click:Connect(function()
			if DM.GetSelectedBiome() then showMode("Biome") end
		end)
	end

	local matClick = BtnMaterials:FindFirstChild("ClickArea")
	if matClick and matClick:IsA("TextButton") then
		matClick.MouseButton1Click:Connect(function()
			if DM.GetSelectedBiome() then showMode("Materials") end
		end)
	end

	Overlay.MouseButton1Click:Connect(function()
		UI.SetDropdownOpen(BiomeDropdown, false)
		Overlay.Visible = false
	end)
	
	local envClick = BtnEnvironmental:FindFirstChild("ClickArea")
	if envClick and envClick:IsA("TextButton") then
		envClick.MouseButton1Click:Connect(function()
			if DM.GetSelectedBiome() then showMode("Environmental") end
		end)
	end
	
	local stampsClick = BtnStamps:FindFirstChild("ClickArea")
	if stampsClick and stampsClick:IsA("TextButton") then
		stampsClick.MouseButton1Click:Connect(function()
			if DM.GetSelectedBiome() then showMode("Stamps") end
		end)
	end
end

-- ========= FIRST LAYOUT + DATA LOAD =========
relayout()
refreshBiomeUIFromData()

-- ========= EXPORT =========
return {
	Widget   = widget,
	Root     = root,
	Toolbar  = toolbar,
	Props    = props,
	PropsScroll = propsScroll,
	Preview  = preview,
	Theme    = Theme,
	Elements = {
		BiomeDropdown   = BiomeDropdown,
		AddBiomeButton  = AddBiomeBtn,
		NewBiomeBar     = NewBiomeBar,
		Buttons = {
			World = BtnWorld, Biome = BtnBiome, Materials = BtnMaterials,
			Environmental = BtnEnvironmental, Stamps = BtnStamps,
			Lighting = BtnLighting, Caves = BtnCaves,
		},
	},
	Constants = { TOOLBAR_H = TOOLBAR_H, PROPERTIES_W = PROPERTIES_W }
}
