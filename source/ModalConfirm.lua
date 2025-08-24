-- ModalConfirm.lua
-- Simple reusable confirmation dialog with OK/Cancel.
-- API:
-- ModalConfirm.Show(parent, {
--   title: string?,
--   message: string?,
--   okText: string? = "OK",
--   cancelText: string? = "Cancel",
--   primaryIsDestructive: boolean? = false,
--   onConfirm: (()->())?,
--   onCancel: (()->())?
-- })

local UIS = game:GetService("UserInputService")

local ModalConfirm = {}
ModalConfirm.__index = ModalConfirm

local function corner(p, r) local c=Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent=p; return c end
local function stroke(p, c, t) local s=Instance.new("UIStroke"); s.Color=c or Color3.fromRGB(55,57,65); s.Thickness=t or 1; s.Parent=p; return s end

function ModalConfirm.Show(parent: Instance, opts: table?)
	opts = opts or {}
	local title   = opts.title or "Confirm"
	local message = opts.message or "Are you sure?"
	local okText  = opts.okText or "OK"
	local cancelText = opts.cancelText or "Cancel"
	local destructive = opts.primaryIsDestructive == true

	local overlay = Instance.new("Frame")
	overlay.Name = "TLX_ConfirmOverlay"
	overlay.BackgroundColor3 = Color3.new(0,0,0)
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.Active = true
	overlay.Selectable = true
	overlay.ZIndex = 9000
	overlay.Size = UDim2.fromScale(1,1)
	overlay.Parent = parent

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 180)
	panel.BackgroundColor3 = Color3.fromRGB(30,31,36)
	panel.BorderSizePixel = 0
	panel.ZIndex = 9001
	panel.Parent = overlay
	corner(panel, 10); stroke(panel, Color3.fromRGB(55,57,65), 1)

	local titleLbl = Instance.new("TextLabel")
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamMedium
	titleLbl.TextSize = 16
	titleLbl.TextColor3 = Color3.fromRGB(225,227,234)
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Text = title
	titleLbl.Position = UDim2.fromOffset(12, 10)
	titleLbl.Size = UDim2.new(1, -24, 0, 24)
	titleLbl.ZIndex = 9001
	titleLbl.Parent = panel

	local msg = Instance.new("TextLabel")
	msg.BackgroundTransparency = 1
	msg.Font = Enum.Font.Gotham
	msg.TextWrapped = true
	msg.TextSize = 14
	msg.TextColor3 = Color3.fromRGB(210,212,220)
	msg.TextXAlignment = Enum.TextXAlignment.Left
	msg.TextYAlignment = Enum.TextYAlignment.Top
	msg.Text = message
	msg.Position = UDim2.fromOffset(12, 40)
	msg.Size = UDim2.new(1, -24, 1, -100)
	msg.ZIndex = 9001
	msg.Parent = panel

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Position = UDim2.new(0, 12, 1, -46)
	buttons.Size = UDim2.new(1, -24, 0, 34)
	buttons.ZIndex = 9001
	buttons.Parent = panel
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 10)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Parent = buttons

	local function makeBtn(text, primary, red)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(96, 34)
		b.Text = text
		b.AutoButtonColor = true
		b.Font = Enum.Font.GothamMedium
		b.TextSize = 14
		b.TextColor3 = Color3.fromRGB(240,242,248)
		b.BackgroundColor3 = primary and (red and Color3.fromRGB(200, 58, 67) or Color3.fromRGB(38,138,255)) or Color3.fromRGB(56,58,66)
		b.BorderSizePixel = 0
		b.ZIndex = 9002
		corner(b, 6); stroke(b, Color3.fromRGB(45,47,54), 1)
		return b
	end

	local btnCancel = makeBtn(cancelText, false, false)
	btnCancel.Parent = buttons
	local btnOK = makeBtn(okText, true, destructive)
	btnOK.Parent = buttons

	local closed = false
	local function close(confirm)
		if closed then return end
		closed = true
		if confirm then
			if opts.onConfirm then pcall(opts.onConfirm) end
		else
			if opts.onCancel then pcall(opts.onCancel) end
		end
		overlay:Destroy()
	end

	btnCancel.MouseButton1Click:Connect(function() close(false) end)
	btnOK.MouseButton1Click:Connect(function() close(true) end)

	-- ESC cancels
	local escConn; escConn = UIS.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			if escConn then escConn:Disconnect() end
			close(false)
		end
	end)

	-- Click outside cancels
	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local p = input.Position
			local abs = panel.AbsolutePosition
			local size = panel.AbsoluteSize
			local inside = p.X >= abs.X and p.X <= abs.X + size.X and p.Y >= abs.Y and p.Y <= abs.Y + size.Y
			if not inside then close(false) end
		end
	end)
end

return ModalConfirm
