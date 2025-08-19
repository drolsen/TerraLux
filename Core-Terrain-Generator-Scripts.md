-- TerrainGeneratorScript (Core server script, streamlined; feature parity preserved)
-- Purpose:
--   World bootstrap + streaming controller:
--     • Clears Terrain and precomputes Height offsets
--     • Keeps tiles around the player by distance-ordered prefetch
--     • Budgeted build/unbuild job caps (Config.MAX_GEN_JOBS / MAX_AIR_JOBS)
--     • Atmosphere change per-biome along Z
--
-- Notes:
--   • Avoids excess allocations in tilesInRadius and sort comparator.
--   • Retains 1-request-per-heartbeat build pacing to keep frame times steady.

local Terrain     = workspace.Terrain                                       -- Roblox voxel terrain object
local Players     = game:GetService("Players")                               -- Player service (stream focus)
local RunService  = game:GetService("RunService")                            -- Heartbeat pacing
local Lighting    = game:GetService("Lighting")                              -- Atmosphere parent

-- child modules
local Modules     = script:WaitForChild("Modules")                           -- container for module scripts
local Config      = require(Modules.WorldConfig)                             -- config: sizes, budgets, radii
local Biomes      = require(Modules.Biomes)                                  -- biome params/materials/atmosphere
local Height 	  = require(Modules.Height)                                   -- heightfield logic (morphing + offsets)
local TileBuilder = require(Modules.TileBuilder)                             -- tile construction/destruction

-- boot
Terrain:Clear()                                                              -- hard reset terrain
Height.computeOffsets()                                                      -- precompute per-biome vertical Offsets[]

-- streaming state
local active, generating, unloading = {}, {}, {}                             -- active: built tiles; generating/unloading: job guards
local genJobs, airJobs = 0, 0                                               -- current job counters

-- world→tile helpers
local function worldToTile(x,z) return math.floor(x/Config.TILE_SIZE), math.floor(z/Config.TILE_SIZE) end -- world→tile index
local function tileKey(i,k) return i..":"..k end                            -- string key for dictionaries
local function tileCenter(i,k) return (i+0.5)*Config.TILE_SIZE, (k+0.5)*Config.TILE_SIZE end -- tile center (X,Z)

-- getFocus:
--   Returns position of the first player's HumanoidRootPart (or origin if none).
local function getFocus()
	local p = Players:GetPlayers()[1]
	if p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
		return p.Character.HumanoidRootPart.Position
	end
	return Vector3.new(0,0,0)
end

-- tilesInRadius:
--   Returns a list of tile coords {i,k} covering axis-aligned square around 'center' with radius 'radius',
--   sorted by squared distance to 'center' (closest-first).
local function tilesInRadius(center, radius)
	local out = {}
	local minX,maxX = center.X - radius, center.X + radius
	local minZ,maxZ = center.Z - radius, center.Z + radius
	local i0,k0 = worldToTile(minX, minZ)
	local i1,k1 = worldToTile(maxX, maxZ)
	local worldStartZ = Config.WORLD_START_Z
	local worldEndZ   = worldStartZ + Config.BIOME_LENGTH*Config.BIOME_COUNT

	local n = 0
	for i=i0,i1 do
		for k=k0,k1 do
			local z0 = k*Config.TILE_SIZE
			local z1 = z0 + Config.TILE_SIZE
			if (z1 >= worldStartZ) and (z0 <= worldEndZ) then
				n += 1
				out[n] = {i=i,k=k}
			end
		end
	end

	table.sort(out, function(a,b)
		local ax,az = tileCenter(a.i,a.k); ax -= center.X; az -= center.Z
		local bx,bz = tileCenter(b.i,b.k); bx -= center.X; bz -= center.Z
		return (ax*ax+az*az) < (bx*bx+bz*bz)
	end)
	return out
end

-- ensureTile:
--   Enqueue a build if not active/generating and within job budget.
local function ensureTile(i,k)
	local key = tileKey(i,k)
	if active[key] or generating[key] then return end
	if genJobs >= Config.MAX_GEN_JOBS then return end
	generating[key] = true; genJobs += 1
	task.spawn(function()
		local ok,err = pcall(TileBuilder.build, i,k)
		if not ok then warn("Tile build error:", err) end
		active[key] = true
		generating[key] = nil
		genJobs -= 1
	end)
end

-- retireTile:
--   Enqueue a budgeted unbuild pass if active and not already unloading.
local function retireTile(i,k)
	local key = tileKey(i,k)
	if not active[key] or unloading[key] then return end
	if airJobs >= Config.MAX_AIR_JOBS then return end
	unloading[key] = true; airJobs += 1

	task.spawn(function()
		local ok, err
		if TileBuilder and typeof(TileBuilder) == "table" and typeof(TileBuilder.unbuild) == "function" then
			ok, err = pcall(TileBuilder.unbuild, i, k)
		else
			ok, err = false, "TileBuilder.unbuild is nil (module export mismatch)"
		end

		if not ok then warn("Tile unload error:", err) end
		active[key] = nil
		unloading[key] = nil
		airJobs -= 1
	end)
end

-- updateAtmosphereForZ:
--   Applies per-biome atmosphere preset for current Z (soft changes while streaming forward).
local function updateAtmosphereForZ(z)
	local idx = Biomes.indexForZ(z)
	local spec = Biomes.Atmosphere[idx]; if not spec then return end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Parent = Lighting
	atmo.Color = spec[1]
	atmo.Density = spec[2]
end

-- ===== main streamer loop =====
task.spawn(function()
	while true do
		local focus = getFocus()
		local genR  = Config.VIEW_RADIUS_STUDS + Config.PREFETCH_MARGIN
		local killR = genR + Config.DESPAWN_MARGIN

		-- distance-ordered wanted list
		local want = tilesInRadius(focus, genR)

		-- issue at most 1 build request per tick (keeps spikes low)
		local requested = 0
		for idx=1, #want do
			if requested >= 1 then break end
			local t = want[idx]
			local key = tileKey(t.i,t.k)
			if not active[key] and not generating[key] then
				ensureTile(t.i, t.k); requested += 1
			end
		end

		-- scan active for retire
		--for key,_ in pairs(active) do
		--	local si,sk = key:match("(-?%d+):(-?%d+)")
		--	si, sk = tonumber(si), tonumber(sk)
		--	local cx,cz = tileCenter(si,sk)
		--	local dx, dz = cx - focus.X, cz - focus.Z
		--	local d = math.sqrt(dx*dx + dz*dz)
		--	if d > killR + math.sqrt(2)*Config.TILE_SIZE*0.5 then
		--		retireTile(si, sk)
		--	end
		--end

		updateAtmosphereForZ(focus.Z)
		RunService.Heartbeat:Wait()
	end
end)
