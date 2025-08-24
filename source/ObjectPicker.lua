-- Modules/ModalObjectPicker.lua
-- Modal overlay + Explorer-like picker with clean expand/collapse & scoped roots.
-- API:
--   ModalObjectPicker.Show(triggerButton: TextButton, targetValue: ObjectValue, classFilter: {string}? , opts?: {
--     title: string?, size: UDim2?, okText: string?, cancelText: string?,
--     roots: {string}? -- optional override, default = { "Workspace","ReplicatedStorage","ServerStorage","ServerScriptService" }
--   })
-- Behavior:
--   - Overlays nearest PluginGui (DockWidget).
--   - Only lists under roots (default 4 services).
--   - If classFilter nil => any instance selectable; else only those classes selectable (others dimmed but browsable).
--   - OK enabled only when a selectable item is chosen.
--   - On OK: targetValue.Value = chosen; triggerButton.Text = chosen.Name.

local UIS = game:GetService("UserInputService")

local ModalObjectPicker = {}
ModalObjectPicker.__index = ModalObjectPicker

-- ------------------------------------------------------------------------------
-- Theme / helpers
-- ------------------------------------------------------------------------------
local Theme = {
	OverlayAlpha = 0.35,
	PanelBg      = Color3.fromRGB(30,31,36),
	PanelStroke  = Color3.fromRGB(55,57,65),
	Text         = Color3.fromRGB(225,227,234),
	TextDim      = Color3.fromRGB(150,156,166),
	Line         = Color3.fromRGB(55,57,65),
	SelectBg     = Color3.fromRGB(48,90,140),
	ButtonPri    = Color3.fromRGB(38,138,255),
	ButtonSec    = Color3.fromRGB(56,58,66),
	ButtonText   = Color3.fromRGB(240,242,248),
}

local DEFAULT_ROOTS = { "Workspace","ReplicatedStorage","ServerStorage","ServerScriptService" }

local function arrayToSet(arr: {string}?): {[string]: true}|nil
	if not arr then return nil end
	local t = {}
	for _, v in ipairs(arr) do
		if typeof(v) == "string" then t[v] = true end
	end
	return next(t) and t or nil
end

local function create(typ: string, props: table?, children: {Instance}?): Instance
	local o = Instance.new(typ)
	if props then for k, v in pairs(props) do o[k] = v end end
	if children then for _, c in ipairs(children) do c.Parent = o end end
	return o
end

local function getPluginGuiAncestor(inst: Instance): PluginGui?
	return inst:FindFirstAncestorWhichIsA("PluginGui")
end

local function safeGetService(name: string): Instance?
	-- Workspace is special-cased; GetService works for the others.
	if name == "Workspace" then return workspace end
	local ok, svc = pcall(function() return game:GetService(name) end)
	if ok then return svc end
	return nil
end

local function getInstancePath(inst: Instance): string
	if inst == game then return "game" end
	local segs = {}
	local cur = inst
	while cur and cur ~= game do
		table.insert(segs, 1, cur.Name)
		cur = cur.Parent
	end
	table.insert(segs, 1, "game")
	return table.concat(segs, ".")
end

local function chevron(expanded: boolean): string
	return expanded and "?" or "?"
end

local function makeButton(text: string, primary: boolean): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 96, 0, 30)
	btn.BackgroundColor3 = primary and Theme.ButtonPri or Theme.ButtonSec
	btn.AutoButtonColor = true
	btn.Text = text
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 14
	btn.TextColor3 = Theme.ButtonText
	btn.BorderSizePixel = 0
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,6); corner.Parent = btn
	local stroke = Instance.new("UIStroke"); stroke.Color = Theme.PanelStroke; stroke.Thickness = 1; stroke.Parent = btn
	return btn
end

-- ------------------------------------------------------------------------------
-- Main
-- ------------------------------------------------------------------------------
function ModalObjectPicker.Show(triggerButton: TextButton, targetValue: ObjectValue, classFilter: {string}?, opts: table?)
	assert(triggerButton and triggerButton:IsA("TextButton"), "Show: first param must be a TextButton")
	assert(targetValue and targetValue:IsA("ObjectValue"), "Show: second param must be an ObjectValue")
	opts = opts or {}

	local allowedSet = arrayToSet(classFilter) -- nil => unrestricted
	local pluginGui = getPluginGuiAncestor(triggerButton)
	local parent: Instance = pluginGui or triggerButton

	-- Overlay
	local overlay = create("Frame", {
		Name = "TLX_ObjectPickerOverlay",
		BackgroundColor3 = Color3.new(0,0,0),
		BackgroundTransparency = Theme.OverlayAlpha,
		BorderSizePixel = 0,
		Active = true,
		Selectable = true,
		ZIndex = 1000,
		Size = UDim2.fromScale(1,1),
	})
	overlay.Parent = parent

	-- Panel
	local panel = create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = opts.size or UDim2.fromOffset(580, 480),
		BackgroundColor3 = Theme.PanelBg,
		BorderSizePixel = 0,
		ZIndex = 1001,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0,10) }),
		create("UIStroke", { Color = Theme.PanelStroke, Thickness = 1 }),
	})
	panel.Parent = overlay

	-- Title
	local title = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 0, 28),
		Position = UDim2.fromOffset(8, 6),
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Text,
		Text = opts.title or "Select Object",
		ZIndex = 1001,
	})
	title.Parent = panel

	-- Path bar
	local pathBar = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 36),
		Font = Enum.Font.Code,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		Text = "",
		ZIndex = 1001,
	})
	pathBar.Parent = panel

	-- Content
	local content = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 60),
		Size = UDim2.new(1, -20, 1, -60 - 48),
		ZIndex = 1001,
	})
	content.Parent = panel

	-- Tree container
	local treeHolder = create("Frame", {
		BackgroundColor3 = Theme.PanelBg,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1,1),
		ZIndex = 1001,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0,8) }),
		create("UIStroke", { Color = Theme.Line, Thickness = 1 }),
	})
	treeHolder.Parent = content

	local list = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1,1),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0,0,0,0),
		ScrollBarThickness = 8,
		ZIndex = 1001,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0,0),
		})
	})
	list.Parent = treeHolder

	-- Buttons
	local btnRow = create("Frame", {
		BackgroundTransparency = 1,
		ZIndex = 1001,
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.new(0, 10, 1, -44),
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 10),
		})
	})
	btnRow.Parent = panel

	local btnCancel = makeButton(opts.cancelText or "Cancel", false); btnCancel.Parent = btnRow; btnCancel.ZIndex = 1004
	local btnOK     = makeButton(opts.okText     or "OK",     true ); btnOK.Parent     = btnRow; btnOK.ZIndex = 1004

	local function setOKEnabled(on: boolean)
		btnOK.Active = on
		btnOK.AutoButtonColor = on
		btnOK.BackgroundColor3 = on and Theme.ButtonPri or Color3.fromRGB(70,80,96)
	end
	setOKEnabled(false)

	-- Selection state
	local chosen: Instance? = nil
	local nodesByInstance: {[Instance]: Frame} = {}

	local function clearAllSelections()
		for inst, node in pairs(nodesByInstance) do
			local row = node:FindFirstChild("Row")
			if row then
				local nameLabel: TextLabel? = row:FindFirstChild("NameLabel") :: TextLabel
				if nameLabel then
					nameLabel.BackgroundTransparency = 1
					nameLabel.TextColor3 = (not allowedSet or allowedSet[inst.ClassName]) and Theme.Text or Theme.TextDim
				end
			end
		end
		pathBar.Text = ""
	end

	local function isExpandable(inst: Instance): boolean
		return #inst:GetChildren() > 0
	end

	-- Node factory (AutomaticSize-enabled)
	local function newNode(inst: Instance, depth: number): Frame
		local selectable = (allowedSet == nil) or (allowedSet[inst.ClassName] == true)

		local Node = create("Frame", {
			Name = "Node",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 1002,
		})

		local Row = create("TextButton", {
			Name = "Row",
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 22),
			Text = "",
			ZIndex = 1002,
		})
		Row.Parent = Node

		local Indent = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 12 * depth, 1, 0),
			ZIndex = 1002,
		})
		Indent.Parent = Row

		local ChevronBtn = create("TextButton", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 18, 1, 0),
			Position = UDim2.new(0, 12 * depth, 0, 0),
			Text = isExpandable(inst) and chevron(false) or "",
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextColor3 = Theme.TextDim,
			AutoButtonColor = false,
			ZIndex = 1002,
		})
		ChevronBtn.Parent = Row

		local NameLabel = create("TextLabel", {
			Name = "NameLabel",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -(12 * depth + 18 + 8), 1, 0),
			Position = UDim2.new(0, 12 * depth + 18 + 4, 0, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.Gotham,
			TextSize = 14,
			Text = string.format("%s  (%s)", inst.Name, inst.ClassName),
			TextColor3 = selectable and Theme.Text or Theme.TextDim,
			ZIndex = 1002,
		})
		NameLabel.Parent = Row

		local ChildrenHolder = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.new(0, 0, 0, 22),
			Visible = false,
			ZIndex = 1002,
		}, {
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0,0),
			})
		})
		ChildrenHolder.Parent = Node

		nodesByInstance[inst] = Node

		local expanded = false
		local built = false

		local function buildChildren()
			if built then return end
			built = true
			local kids = inst:GetChildren()
			table.sort(kids, function(a,b) return a.Name:lower() < b.Name:lower() end)
			for _, ch in ipairs(kids) do
				newNode(ch, depth + 1).Parent = ChildrenHolder
			end
		end

		local function toggleExpand()
			if not isExpandable(inst) then return end
			expanded = not expanded
			ChevronBtn.Text = chevron(expanded)
			ChildrenHolder.Visible = expanded
			if expanded then buildChildren() end
		end

		local function selectRow()
			clearAllSelections()
			NameLabel.BackgroundTransparency = 0
			NameLabel.BackgroundColor3 = Theme.SelectBg
			NameLabel.TextColor3 = Theme.Text
			pathBar.Text = getInstancePath(inst)
			if selectable then
				chosen = inst
				setOKEnabled(true)
			else
				chosen = nil
				setOKEnabled(false)
			end
		end

		-- Events
		ChevronBtn.MouseButton1Click:Connect(toggleExpand)
		Row.MouseButton1Click:Connect(selectRow)
		Row.MouseButton2Click:Connect(toggleExpand) -- right-click toggles
		--Row.MouseButton1DoubleClick:Connect(toggleExpand) -- double-click toggles

		return Node
	end

	-- Build limited roots
	local rootNames: {string} = opts.roots or DEFAULT_ROOTS
	for _, name in ipairs(rootNames) do
		local svc = safeGetService(name)
		if svc then
			newNode(svc, 0).Parent = list
		end
	end

	-- Close helper
	local closed = false
	local function close(cancelled: boolean)
		if closed then return end
		closed = true
		if not cancelled and chosen then
			targetValue.Value = chosen
			triggerButton.Text = chosen.Name
		end
		overlay:Destroy()
	end

	-- Buttons
	btnCancel.MouseButton1Click:Connect(function() close(true) end)
	btnOK.MouseButton1Click:Connect(function() if btnOK.Active and chosen then close(false) end end)

	-- ESC cancels
	local escConn; escConn = UIS.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			if escConn then escConn:Disconnect() end
			close(true)
		end
	end)

	-- Click-outside cancels
	overlay.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local p = input.Position
			local abs = panel.AbsolutePosition
			local size = panel.AbsoluteSize
			local inside = p.X >= abs.X and p.X <= abs.X + size.X and p.Y >= abs.Y and p.Y <= abs.Y + size.Y
			if not inside then close(true) end
		end
	end)

	-- Handle for external close if needed
	local modal = setmetatable({}, ModalObjectPicker)
	function modal:Close(cancelled: boolean?)
		close(cancelled == nil and true or cancelled)
	end
	return modal
end

return ModalObjectPicker
