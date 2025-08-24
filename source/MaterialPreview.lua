-- MaterialPreview.lua
-- Usage:
--   local Preview = require(MaterialPreview)
--   local p = Preview.attach(someFrame, "Diamond Plate") -- or Enum.Material.DiamondPlate
--   p:SetMaterial("Brick")
--   p:Destroy()

local MaterialPreview = {}
MaterialPreview.__index = MaterialPreview

local MaterialService = game:GetService("MaterialService")

-- Normalize strings like "Diamond Plate" -> "diamondplate", "ClayRoofTiles" -> "clayrooftiles"
local function norm(s)
	if typeof(s) ~= "string" then return s end
	return s:lower():gsub("[%s%p_]", "")
end

-- Build a lookup for Enum.Material by normalized name
local enumByKey = (function()
	local map = {}
	for _, item in ipairs(Enum.Material:GetEnumItems()) do
		map[norm(item.Name)] = item
	end
	return map
end)()

-- Optional: map common friendly names -> Enum names (covers a few gotchas)
local alias = {
	["diamond plate"] = "DiamondPlate",
	["clay roof tiles"] = "ClayRoofTiles",
	["ceramic tiles"] = "CeramicTiles",
	["corroded metal"] = "CorrodedMetal",
	["cracked lava"] = "CrackedLava",
}
for k, v in pairs(alias) do enumByKey[norm(k)] = Enum.Material[v] end

-- Try to find a MaterialVariant by name (case/space-insensitive)
local function findVariant(name)
	if typeof(name) ~= "string" then return nil end
	local key = norm(name)
	for _, v in ipairs(MaterialService:GetDescendants()) do
		if v:IsA("MaterialVariant") and norm(v.Name) == key then
			return v
		end
	end
	return nil
end

-- Compute a camera distance so a sphere (radius r) fits inside the viewport (w x h)
local function fitDistanceForSphere(r, w, h, vfovDeg)
	w = math.max(1, w); h = math.max(1, h)
	local ar = w / h
	local vfov = math.rad(vfovDeg)
	local hfov = 2 * math.atan(math.tan(vfov/2) * ar)
	local distV = r / math.tan(vfov/2)
	local distH = r / math.tan(hfov/2)
	return math.max(distV, distH)
end

-- Build the 3D contents inside a ViewportFrame
local function buildScene(vpf: ViewportFrame)
	-- Camera
	local cam = Instance.new("Camera")
	cam.FieldOfView = 35 -- nice, tight product look
	cam.Parent = vpf
	vpf.CurrentCamera = cam

	-- Sphere
	local sphere = Instance.new("Part")
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(5, 5, 5)
	sphere.Anchored = true
	sphere.CastShadow = false
	sphere.Color = Color3.fromRGB(240, 240, 240) -- neutral base; materials tint it
	sphere.CFrame = CFrame.new(0, 0, 0)
	sphere.Parent = vpf

	-- Simple environment via ViewportFrame lighting
	vpf.Ambient = Color3.fromRGB(70, 70, 70)
	vpf.LightColor = Color3.fromRGB(255, 255, 255)
	vpf.LightDirection = Vector3.new(-1, -1, -0.5).Unit

	return cam, sphere
end

-- Reframe camera to fit sphere nicely (called on size changes)
local function updateCamera(cam: Camera, sphere: BasePart, vpf: ViewportFrame)
	local r = sphere.Size.X * 0.5
	local w = vpf.AbsoluteSize.X
	local h = vpf.AbsoluteSize.Y
	if w < 2 or h < 2 then return end

	local dist = fitDistanceForSphere(r, w, h, cam.FieldOfView) * 1.08 -- small margin
	local dir = Vector3.new(1, 0.45, 1).Unit
	local center = sphere.Position
	cam.CFrame = CFrame.new(center + dir * dist, center)
end

-- Resolve and apply a material or variant onto the sphere
local function applyMaterialToPart(part: BasePart, mat)
	part.MaterialVariant = "" -- clear any previous variant
	if typeof(mat) == "EnumItem" and mat.EnumType == Enum.Material then
		part.Material = mat
		return true
	elseif typeof(mat) == "string" then
		-- Enum first
		local em = enumByKey[norm(mat)]
		if em then part.Material = em; return true end
		-- Then Variant (if present in MaterialService)
		local variant = findVariant(mat)
		if variant then
			-- If the MaterialVariant has a BaseMaterial property, try to set it (pcall guards older engines)
			pcall(function()
				if variant.BaseMaterial then part.Material = variant.BaseMaterial end
			end)
			part.MaterialVariant = variant.Name
			return true
		end
	end
	-- Fallback
	part.Material = Enum.Material.SmoothPlastic
	return false
end

-- Public API ---------------------------------------------------------------

function MaterialPreview.attach(containerFrame: Frame, material, opts)
	assert(containerFrame and containerFrame:IsA("GuiObject"), "Expected a GuiObject container")

	opts = opts or {}

	local self = setmetatable({}, MaterialPreview)
	self.Container = containerFrame

	-- Create/own a ViewportFrame that fills the container
	local vpf = Instance.new("ViewportFrame")
	vpf.Name = "MaterialPreview"
	vpf.BackgroundTransparency = 1
	vpf.Size = UDim2.fromScale(1, 1)
	vpf.Position = UDim2.fromScale(0, 0)
	vpf.BorderSizePixel = 0
	vpf.CurrentCamera = nil
	vpf.Parent = containerFrame
	self.Viewport = vpf

	-- 3D contents
	local cam, sphere = buildScene(vpf)
	self.Camera = cam
	self.Sphere = sphere

	-- Optional bg/lighting customizations
	if opts.BackgroundColor3 then
		vpf.BackgroundTransparency = 0
		vpf.BackgroundColor3 = opts.BackgroundColor3
	end
	if opts.Ambient then vpf.Ambient = opts.Ambient end
	if opts.LightColor then vpf.LightColor = opts.LightColor end
	if opts.LightDirection then vpf.LightDirection = opts.LightDirection.Unit end

	-- Apply initial material
	applyMaterialToPart(self.Sphere, material)

	-- Keep camera fitted on size changes
	self._sizeConn = vpf:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		updateCamera(self.Camera, self.Sphere, self.Viewport)
	end)
	updateCamera(self.Camera, self.Sphere, self.Viewport)

	return self
end

function MaterialPreview:SetMaterial(material)
	if not self.Sphere then return end
	applyMaterialToPart(self.Sphere, material)
	-- Refit in case a different material uses a different visual (e.g., transparency)
	updateCamera(self.Camera, self.Sphere, self.Viewport)
end

function MaterialPreview:Destroy()
	if self._sizeConn then self._sizeConn:Disconnect() end
	if self.Viewport then self.Viewport:Destroy() end
	for k in pairs(self) do self[k] = nil end
end

return MaterialPreview
