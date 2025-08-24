-- BiomeProps (ModuleScript)
-- Builds Biome property cards, binds fields to DataManager paths, loads/saves on change.

local BiomeProps = {}
BiomeProps.__index = BiomeProps

-- descriptor maps fields to schema paths for DM
local SPEC = {
	{ card="Altitude", key="altitude", rows = {
		{ label="Elevation Trend", minis=nil, width=30, path={{"biome","altitude","elevationTrend"}} },
		{ label="Max Altitude",    minis=nil, width=30, path={{"biome","altitude","maxAltitude"}} },
	}},
	{ card="Crevasses", key="crevasses", rows = {
		{ label="Depth Amplitude", minis=nil,    width=30, path={{"biome","crevasses","depthAmplitude"}} },
		{ label="Direction",       minis={"X","Y"}, width={30,30}, path={
			{"biome","crevasses","direction","X"},
			{"biome","crevasses","direction","Y"},
		}},
		{ label="Sharp Exponent",  minis=nil,    width=30, path={{"biome","crevasses","sharpExponent"}} },
		{ label="Space Frequency", minis=nil,    width=30, path={{"biome","crevasses","spaceFrequency"}} },
	}},
	{ card="Fractals", key="fractals", rows = {
		{ label="Amplitude", minis={"L","M","S"}, width={30,30,30}, path={
			{"biome","fractals","amplitude","L"},
			{"biome","fractals","amplitude","M"},
			{"biome","fractals","amplitude","S"},
		}},
		{ label="Frequency", minis={"L","M","S"}, width={30,30,30}, path={
			{"biome","fractals","frequency","L"},
			{"biome","fractals","frequency","M"},
			{"biome","fractals","frequency","S"},
		}},
	}},
	{ card="Ridges", key="ridges", rows = {
		{ label="Amplitude", minis={"L","M","S"}, width={30,30,30}, path={
			{"biome","ridges","amplitude","L"},
			{"biome","ridges","amplitude","M"},
			{"biome","ridges","amplitude","S"},
		}},
		{ label="Frequency", minis={"L","M","S"}, width={30,30,30}, path={
			{"biome","ridges","frequency","L"},
			{"biome","ridges","frequency","M"},
			{"biome","ridges","frequency","S"},
		}},
	}},
	{ card="Terraces", key="terraces", rows = {
		{ label="Blending", minis=nil, width=30, path={{"biome","terraces","blending"}} },
		{ label="Size",     minis=nil, width=30, path={{"biome","terraces","size"}} },
	}},
	{ card="Warping", key="warping", rows = {
		{ label="Amplitude", minis={"L","S"}, width={30,30}, path={
			{"biome","warping","amplitude","L"},
			{"biome","warping","amplitude","S"},
		}},
		{ label="Frequency", minis={"L","S"}, width={30,30}, path={
			{"biome","warping","frequency","L"},
			{"biome","warping","frequency","S"},
		}},
	}},
}

local function toNumberOr(old, s)
	local n = tonumber(s)
	if n == nil then return old end
	return n
end

function BiomeProps.new(uiModule, dmModule, parentScroll)
	local self = setmetatable({}, BiomeProps)
	self.UI = uiModule
	self.DM = dmModule
	self.Parent = parentScroll
	self.fieldMap = {} -- [TextBox] = pathArray
	return self
end

function BiomeProps:clear()
	self.UI.ClearChildrenExcept(self.Parent)
	self.fieldMap = {}
end

function BiomeProps:build()
	-- Build Biome cards (visible when mode == "Biome")
	for _, cardSpec in ipairs(SPEC) do
		local saved = self.DM.GetCardExpanded("BIOME_"..cardSpec.key)
		local card, content = self.UI.PropertyCard({
			Title=cardSpec.card, CardKey="BIOME_"..cardSpec.key, ModeTag="Biome",
			Expanded = (saved == true), -- default collapsed when nil/false
			OnToggle = function(_, expanded) self.DM.SetCardExpanded("BIOME_"..cardSpec.key, expanded) end
		})
		card.ZIndex = 0
		card.Parent = self.Parent
		for _, row in ipairs(cardSpec.rows) do
			local _, area = self.UI.PropertyRow(content, row.label)
			local boxes = self.UI.AddNumberFields(area, row.minis, row.width)
			for i, tb in ipairs(boxes) do
				local path = row.path[i]
				if path then
					self.fieldMap[tb] = path
					tb.FocusLost:Connect(function()
						local current = self.DM.GetSelectedPath(path)
						local newVal = toNumberOr(current or 0, tb.Text)
						if newVal ~= current then
							self.DM.SetSelectedPath(path, newVal)
						end
						tb.Text = tostring(self.DM.GetSelectedPath(path) or "")
					end)
				end
			end
		end
	end
end

function BiomeProps:loadFromDM()
	for tb, path in pairs(self.fieldMap) do
		local v = self.DM.GetSelectedPath(path)
		tb.Text = (v ~= nil) and tostring(v) or ""
	end
end

return BiomeProps
