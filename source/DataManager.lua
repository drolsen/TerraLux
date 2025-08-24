-- DataManager (ModuleScript)
-- Hidden persistence for TerraLux using plugin:GetSetting/SetSetting.

local DataManager = {}
DataManager.__index = DataManager

local KEY = "TerraLux_Data_v1"

local DEFAULT_SCHEMA = {
	_schema = { version = 1 },
	ui = { selectedBiome = nil },
	biomes = {}
}

-- ===== Biome defaults =====
local function DEFAULT_BIOME_SETTINGS()
	return {
		altitude = { maxAltitude = 0.1, elevationTrend = 0.1 },
		fractals = {
			amplitude = { L = 0.1, M = 0.1, S = 0.1 },
			frequency = { L = 0.1, M = 0.1, S = 0.1 },
		},
		ridges = {
			amplitude = { L = 0.1, M = 0.1, S = 0.1 },
			frequency = { L = 0.1, M = 0.1, S = 0.1 },
		},
		warping = {
			amplitude = { L = 0.1, S = 0.1 },
			frequency = { L = 0.1, S = 0.1 },
		},
		crevasses = {
			depthAmplitude = 0.1,
			direction = { X = 0.1, Y = 0.1 },
			sharpExponent = 0.1,
			spaceFrequency = 0.1,
		},
		terraces = { blending = 0.1, size = 0.1 },
	}
end

-- ===== Materials defaults (comp-accurate card list) =====
local MATERIAL_ORDER = {
	"Ground","Mud","Sand","Salt","Grass","Leafy Grass","Rock","Basalt",
	"Limestone","Sandstone","Slate","Snow","Ice","Glacier","Cracked Lava",
	"Asphalt","Pavement","Concrete","Cobblestone","Brick","Wood Planks"
}
local function DEFAULT_MATERIAL_ENTRY(layer, name)
	local matColor = workspace.Terrain:GetMaterialColor(Enum.Material[string.gsub(name, "%s", "")])
	return {
		apply = false,
		layer = layer,
		color = {
			matColor.R*255,
			matColor.G*255,
			matColor.B*255,
		},
		filters = {}
	}
end

local function DEFAULT_MATERIALS()
	local data = {}
	for i, name in ipairs(MATERIAL_ORDER) do
		data[name] = DEFAULT_MATERIAL_ENTRY(i, name)
	end
	
	return { order = MATERIAL_ORDER, data = data }
end

-- ===== Environmental defaults per category =====
local function DEFAULT_ENV_CATEGORY()
	return {
		color = {200,120,80},
		scaleMin = 1.0, scaleMax = 1.0,
		altitude = 0.0, slope = 0.0, spacing = 0,
		rotAxis = { X=false, Y=true, Z=false },
		maxDeg = { X=0, Y=180, Z=0 },
		alignToNormal = false,
		avoidFootprint = 0,
		selfOverlap = false,
		avoid = {},            -- array of category names
		allowed = {},          -- map materialName -> boolean
		models = {},           -- array of { name, ref }
	}
end
local function DEFAULT_ENVIRONMENTAL()
	return { order = {}, data = {}, ui = { cardExpanded = {} } }
end

-- ===== Stamps defaults (clone of Environmental) =====
local function DEFAULT_STAMP_CATEGORY()
	-- clone + add StampFillType default
	local t = DEFAULT_ENV_CATEGORY()
	t.StampFillType = "solid" -- "solid" (Protruding) or "air" (Receding)
	return t
end
local function DEFAULT_STAMPS()
	return { order = {}, data = {}, ui = { cardExpanded = {} } }
end

-- ===== Internals =====
local _plugin: Plugin? = nil
local _state = nil

local function deepClone(tbl)
	local t = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then t[k] = deepClone(v) else t[k] = v end
	end
	return t
end

local function save()
	if not _plugin then return false, "plugin nil" end
	_plugin:SetSetting(KEY, _state)
	return true
end

local function mergeDefaults(dst, def)
	for k, v in pairs(def) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = deepClone(v) else mergeDefaults(dst[k], v) end
		else
			if dst[k] == nil then dst[k] = v end
		end
	end
end

-- ===== Public API =====
function DataManager.Init(plugin: Plugin)
	_plugin = plugin
	local loaded = _plugin:GetSetting(KEY)

	if type(loaded) ~= "table" or type(loaded._schema) ~= "table" then
		_state = deepClone(DEFAULT_SCHEMA)
		local ok, err = save()
		if not ok then return false, err end
	else
		_state = loaded
		-- Backfill defaults for older saves
		for _, biome in pairs(_state.biomes or {}) do
			biome.biome = biome.biome or {}
			mergeDefaults(biome.biome, DEFAULT_BIOME_SETTINGS())

			-- Materials migration/backfill
			if type(biome.materials) ~= "table" or not biome.materials.order or not biome.materials.data then
				biome.materials = DEFAULT_MATERIALS()
			else
				for _, name in ipairs(biome.materials.order) do
					local m = biome.materials.data[name]
					if not m then
						biome.materials.data[name] = DEFAULT_MATERIAL_ENTRY(1)
					else
						if m.apply == nil then m.apply = false end
						if m.layer == nil then m.layer = 1 end
						if type(m.color) ~= "table" then m.color = {111,126,62} end
						if type(m.filters) ~= "table" then m.filters = {} end
					end
				end
			end

			-- Environmental migration/backfill
			if type(biome.environmental) ~= "table" or not biome.environmental.order or not biome.environmental.data then
				biome.environmental = DEFAULT_ENVIRONMENTAL()
			else
				biome.environmental.ui = biome.environmental.ui or { cardExpanded = {} }
				biome.environmental.ui.cardExpanded = biome.environmental.ui.cardExpanded or {}
				for _, name in ipairs(biome.environmental.order) do
					local e = biome.environmental.data[name]
					if not e then
						biome.environmental.data[name] = DEFAULT_ENV_CATEGORY()
					else
						mergeDefaults(e, DEFAULT_ENV_CATEGORY())
					end
				end
			end

			-- Stamps migration/backfill (new)
			if type(biome.stamps) ~= "table" or not biome.stamps.order or not biome.stamps.data then
				biome.stamps = DEFAULT_STAMPS()
			else
				biome.stamps.ui = biome.stamps.ui or { cardExpanded = {} }
				biome.stamps.ui.cardExpanded = biome.stamps.ui.cardExpanded or {}
				for _, name in ipairs(biome.stamps.order) do
					local s = biome.stamps.data[name]
					if not s then
						biome.stamps.data[name] = DEFAULT_STAMP_CATEGORY()
					else
						mergeDefaults(s, DEFAULT_STAMP_CATEGORY())
					end
				end
			end

			-- Per-biome UI memory for card expansion
			biome.ui = biome.ui or {}
			biome.ui.cardExpanded = biome.ui.cardExpanded or {} -- [cardKey]=boolean
		end
	end

	return true, _state
end

function DataManager.GetState()
	return _state
end

function DataManager.GetSelectedBiome(): string?
	return _state and _state.ui and _state.ui.selectedBiome or nil
end

function DataManager.SelectBiome(name: string)
	if not _state then return false, "uninitialized" end
	if not _state.biomes[name] then return false, "not found" end
	_state.ui.selectedBiome = name
	return save()
end

function DataManager.BiomeExists(name: string): boolean
	return _state and _state.biomes and _state.biomes[name] ~= nil
end

function DataManager.ListBiomes(): {string}
	local names = {}
	if not _state then return names end
	for n in pairs(_state.biomes) do table.insert(names, n) end
	table.sort(names, function(a,b) return a:lower() < b:lower() end)
	return names
end

local function getAtPath(t, path)
	local node = t
	for _, key in ipairs(path) do
		if type(node) ~= "table" then return nil end
		node = node[key]
		if node == nil then return nil end
	end
	return node
end

local function setAtPath(t, path, value)
	local node = t
	for i = 1, (#path - 1) do
		local k = path[i]
		if type(node[k]) ~= "table" then node[k] = {} end
		node = node[k]
	end
	node[path[#path]] = value
end

function DataManager.GetSelectedBiomeSettings()
	if not _state or not _state.ui.selectedBiome then return nil end
	local b = _state.biomes[_state.ui.selectedBiome]
	return b and b.biome or nil
end

function DataManager.GetSelectedPath(path)
	if not _state or not _state.ui.selectedBiome then return nil end
	local b = _state.biomes[_state.ui.selectedBiome]
	if not b then return nil end
	return getAtPath(b, path)
end

function DataManager.SetSelectedPath(path, value)
	if not _state or not _state.ui.selectedBiome then return false, "no selection" end
	local b = _state.biomes[_state.ui.selectedBiome]
	if not b then return false, "not found" end
	setAtPath(b, path, value)
	return save()
end

function DataManager.CreateBiome(name: string)
	if not _state then return false, "uninitialized" end
	if name == nil or name == "" then return false, "empty" end
	if _state.biomes[name] then return false, "duplicate" end

	_state.biomes[name] = {
		world         = {},
		biome         = DEFAULT_BIOME_SETTINGS(),
		materials     = DEFAULT_MATERIALS(),
		environmental = DEFAULT_ENVIRONMENTAL(),
		stamps        = DEFAULT_STAMPS(),  -- NEW default
		lighting      = {},
		caves         = {},
		ui            = { cardExpanded = {} }, -- per-biome UI memory
		createdAt     = os.time(),
	}

	_state.ui.selectedBiome = name
	return save()
end

function DataManager.DeleteBiome(name: string)
	if not _state or not _state.biomes[name] then return false end
	_state.biomes[name] = nil
	if _state.ui.selectedBiome == name then
		_state.ui.selectedBiome = nil
	end
	return save()
end

-- ===== Materials API (selected biome scope) =====
function DataManager.ListMaterials()
	if not _state or not _state.ui.selectedBiome then return {} end
	local b = _state.biomes[_state.ui.selectedBiome]
	if not b or not b.materials or not b.materials.order then return {} end
	return b.materials.order
end

function DataManager.GetMaterial(name)
	if not _state or not _state.ui.selectedBiome then return nil end
	local b = _state.biomes[_state.ui.selectedBiome]
	if not b or not b.materials or not b.materials.data then return nil end
	return b.materials.data[name]
end

function DataManager.SetMaterialPath(name, path, value)
	if not _state or not _state.ui.selectedBiome then return false, "no selection" end
	local b = _state.biomes[_state.ui.selectedBiome]; if not b then return false, "no biome" end
	local m = (((b.materials or {}).data) or {})[name]; if not m then return false, "no material" end

	local node = m
	for i = 1, (#path - 1) do
		local k = path[i]
		if type(k) == "number" then
			if type(node) ~= "table" then return false, "invalid path" end
		else
			if type(node[k]) ~= "table" then node[k] = {} end
		end
		node = node[k]
	end
	node[path[#path]] = value
	return save()
end

function DataManager.AddMaterialFilter(name)
	if not _state or not _state.ui.selectedBiome then return false end
	local m = DataManager.GetMaterial(name); if not m then return false end
	m.filters = m.filters or {}
	table.insert(m.filters, { name = "Custom Filter Name", altitude=0.0, slope=0.0, curve=0.0 })
	return save()
end

function DataManager.RemoveMaterialFilter(name, index)
	if not _state or not _state.ui.selectedBiome then return false end
	local m = DataManager.GetMaterial(name); if not m then return false end
	if index < 0 or index > #(m.filters or {}) then return false end
	table.remove(m.filters, index)
	return save()
end

-- ====== Card expansion memory (biome-scoped generic) ======
local function _cardKeyKey(cardKey: string) return tostring(cardKey) end
function DataManager.GetCardExpanded(cardKey: string): boolean?
	if not _state or not _state.ui.selectedBiome then return nil end
	local b = _state.biomes[_state.ui.selectedBiome]
	if not b then return nil end
	b.ui = b.ui or {}; b.ui.cardExpanded = b.ui.cardExpanded or {}
	local v = b.ui.cardExpanded[_cardKeyKey(cardKey)]
	if v == nil then return nil end
	return v and true or false
end
function DataManager.SetCardExpanded(cardKey: string, expanded: boolean)
	if not _state or not _state.ui.selectedBiome then return false end
	local b = _state.biomes[_state.ui.selectedBiome]
	if not b then return false end
	b.ui = b.ui or {}; b.ui.cardExpanded = b.ui.cardExpanded or {}
	b.ui.cardExpanded[_cardKeyKey(cardKey)] = expanded and true or false
	return save()
end

-- ===== Environmental API (selected biome scope) =====
local function _envRoot()
	if not _state or not _state.ui.selectedBiome then return nil end
	local b = _state.biomes[_state.ui.selectedBiome]
	if not b then return nil end
	b.environmental = b.environmental or DEFAULT_ENVIRONMENTAL()
	b.environmental.order = b.environmental.order or {}
	b.environmental.data  = b.environmental.data  or {}
	b.environmental.ui    = b.environmental.ui    or { cardExpanded = {} }
	b.environmental.ui.cardExpanded = b.environmental.ui.cardExpanded or {}
	return b.environmental
end

function DataManager.EnvListCategories()
	local env = _envRoot(); if not env then return {} end
	return env.order
end

function DataManager.EnvCategoryExists(name: string)
	local env = _envRoot(); if not env then return false end
	return env.data[name] ~= nil
end

function DataManager.EnvCreateCategory(name: string)
	local env = _envRoot(); if not env then return false, "no selection" end
	if name == nil or name == "" then return false, "empty" end
	if env.data[name] then return false, "duplicate" end
	env.data[name] = DEFAULT_ENV_CATEGORY()
	table.insert(env.order, name)
	return save()
end

function DataManager.EnvDeleteCategory(name: string)
	local env = _envRoot(); if not env then return false end
	if not env.data[name] then return false end
	env.data[name] = nil
	for i, n in ipairs(env.order) do
		if n == name then table.remove(env.order, i) break end
	end
	for _, n in ipairs(env.order) do
		local cat = env.data[n]
		if cat and type(cat.avoid) == "table" then
			local j = 1
			while j <= #cat.avoid do
				if cat.avoid[j] == name then table.remove(cat.avoid, j) else j += 1 end
			end
		end
	end
	return save()
end

function DataManager.EnvRenameCategory(oldName: string, newName: string)
	local env = _envRoot(); if not env then return false end
	if not env.data[oldName] then return false, "missing" end
	if env.data[newName] then return false, "duplicate" end
	env.data[newName] = env.data[oldName]
	env.data[oldName] = nil
	for i, n in ipairs(env.order) do
		if n == oldName then env.order[i] = newName break end
	end
	for _, n in ipairs(env.order) do
		local cat = env.data[n]
		if cat and type(cat.avoid) == "table" then
			for i=1,#cat.avoid do
				if cat.avoid[i] == oldName then cat.avoid[i] = newName end
			end
		end
	end
	return save()
end

function DataManager.EnvGetCategory(name: string)
	local env = _envRoot(); if not env then return nil end
	local c = env.data[name]
	if not c then return nil end
	mergeDefaults(c, DEFAULT_ENV_CATEGORY())
	return c
end

function DataManager.EnvSetCategoryPath(name: string, path, value)
	local env = _envRoot(); if not env then return false, "no selection" end
	local c = env.data[name]; if not c then return false, "no category" end
	local node = c
	for i=1,(#path-1) do
		local k = path[i]
		if type(node[k]) ~= "table" then node[k] = {} end
		node = node[k]
	end
	node[path[#path]] = value
	return save()
end

function DataManager.EnvRemoveAvoid(name: string, index: number)
	local c = DataManager.EnvGetCategory(name); if not c then return false end
	if index < 1 or index > #(c.avoid or {}) then return false end
	table.remove(c.avoid, index)
	return save()
end

function DataManager.EnvRemoveModel(name: string, index: number)
	local c = DataManager.EnvGetCategory(name); if not c then return false end
	if index < 1 or index > #(c.models or {}) then return false end
	table.remove(c.models, index)
	return save()
end

-- ===== Stamps API (selected biome scope) =====
local function _stampsRoot()
	if not _state or not _state.ui.selectedBiome then return nil end
	local b = _state.biomes[_state.ui.selectedBiome]
	if not b then return nil end
	b.stamps = b.stamps or DEFAULT_STAMPS()
	b.stamps.order = b.stamps.order or {}
	b.stamps.data  = b.stamps.data  or {}
	b.stamps.ui    = b.stamps.ui    or { cardExpanded = {} }
	b.stamps.ui.cardExpanded = b.stamps.ui.cardExpanded or {}
	return b.stamps
end

function DataManager.StampsListCategories()
	local s = _stampsRoot(); if not s then return {} end
	return s.order
end

function DataManager.StampsCategoryExists(name: string)
	local s = _stampsRoot(); if not s then return false end
	return s.data[name] ~= nil
end

function DataManager.StampsCreateCategory(name: string)
	local s = _stampsRoot(); if not s then return false, "no selection" end
	if name == nil or name == "" then return false, "empty" end
	if s.data[name] then return false, "duplicate" end
	s.data[name] = DEFAULT_STAMP_CATEGORY()
	table.insert(s.order, name)
	return save()
end

function DataManager.StampsDeleteCategory(name: string)
	local s = _stampsRoot(); if not s then return false end
	if not s.data[name] then return false end
	s.data[name] = nil
	for i, n in ipairs(s.order) do
		if n == name then table.remove(s.order, i) break end
	end
	for _, n in ipairs(s.order) do
		local cat = s.data[n]
		if cat and type(cat.avoid) == "table" then
			local j = 1
			while j <= #cat.avoid do
				if cat.avoid[j] == name then table.remove(cat.avoid, j) else j += 1 end
			end
		end
	end
	return save()
end

function DataManager.StampsRenameCategory(oldName: string, newName: string)
	local s = _stampsRoot(); if not s then return false end
	if not s.data[oldName] then return false, "missing" end
	if s.data[newName] then return false, "duplicate" end
	s.data[newName] = s.data[oldName]
	s.data[oldName] = nil
	for i, n in ipairs(s.order) do
		if n == oldName then s.order[i] = newName break end
	end
	for _, n in ipairs(s.order) do
		local cat = s.data[n]
		if cat and type(cat.avoid) == "table" then
			for i=1,#cat.avoid do
				if cat.avoid[i] == oldName then cat.avoid[i] = newName end
			end
		end
	end
	return save()
end

function DataManager.StampsGetCategory(name: string)
	local s = _stampsRoot(); if not s then return nil end
	local c = s.data[name]
	if not c then return nil end
	mergeDefaults(c, DEFAULT_STAMP_CATEGORY())
	return c
end

function DataManager.StampsSetCategoryPath(name: string, path, value)
	local s = _stampsRoot(); if not s then return false, "no selection" end
	local c = s.data[name]; if not c then return false, "no category" end
	local node = c
	for i=1,(#path-1) do
		local k = path[i]
		if type(node[k]) ~= "table" then node[k] = {} end
		node = node[k]
	end
	node[path[#path]] = value
	return save()
end

function DataManager.StampsRemoveAvoid(name: string, index: number)
	local c = DataManager.StampsGetCategory(name); if not c then return false end
	if index < 1 or index > #(c.avoid or {}) then return false end
	table.remove(c.avoid, index)
	return save()
end

function DataManager.StampsRemoveModel(name: string, index: number)
	local c = DataManager.StampsGetCategory(name); if not c then return false end
	if index < 1 or index > #(c.models or {}) then return false end
	table.remove(c.models, index)
	return save()
end

return DataManager
