## TerrainGenerator (Core server side script)

```lua
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
```

\##Biomes (Module script)

```
-- Biomes (Module script, micro-optimized)
-- Purpose:
--   Defines biome material sets, atmosphere presets, and shape parameters.
--   Provides helpers to map world Z to biome index and blend factor near edges.

local Config = require(script.Parent.WorldConfig)

local Biomes = {}

Biomes.Materials = {
	{ Primary = Enum.Material.Sand,      Secondary = Enum.Material.Grass,   Tertiary = Enum.Material.Limestone, SecondaryCurve = -2, TertiarySlope = 2.75 },
	{ Primary = Enum.Material.Grass,     Secondary = Enum.Material.Mud,     Tertiary = Enum.Material.Rock,      SecondaryCurve = -2, TertiarySlope = 5.75 },
	{ Primary = Enum.Material.Snow, 	 Secondary = Enum.Material.Ice,  	Tertiary = Enum.Material.Rock,      SecondaryCurve = -2, TertiarySlope = 4.75 },
	{ Primary = Enum.Material.Ground,    Secondary = Enum.Material.Grass,   Tertiary = Enum.Material.Slate,     SecondaryCurve = -2, TertiarySlope = 2.75 },
	{ Primary = Enum.Material.Slate,     Secondary = Enum.Material.Basalt,  Tertiary = Enum.Material.Rock,      SecondaryCurve = -2, TertiarySlope = 2.75 },
}

Biomes.Atmosphere = {
	{ Color3.fromRGB(211, 230, 190), 0.45 },
	{ Color3.fromRGB(177, 199, 225), 0.45 },
	{ Color3.fromRGB(112, 118, 129), 0.45 },
	{ Color3.fromRGB(230, 154, 134), 0.45 },
	{ Color3.fromRGB(210, 210, 220), 0.45 },
}

-- indexForZ:
--   Map a world Z to a 1-based biome index, clamped to [1..BIOME_COUNT]
function Biomes.indexForZ(z)
	local rel = (z - Config.WORLD_START_Z) / Config.BIOME_LENGTH
	local i   = math.floor(rel) + 1
	return math.clamp(i, 1, Config.BIOME_COUNT)
end

-- edgeBlend:
--   Returns (t, dir) where:
--     t∈(0..1) is proximity inside the BIOME_BLEND zone (0 outside),
--     dir∈{-1,+1} points to the nearer neighbor (left if -1, right if +1), or 0 outside.
function Biomes.edgeBlend(z)
	local rel  = (z - Config.WORLD_START_Z) / Config.BIOME_LENGTH
	local frac = rel - math.floor(rel)                             -- 0..1 within current strip
	local toEdge = math.min(frac, 1 - frac) * Config.BIOME_LENGTH  -- distance to nearest boundary (studs)
	if toEdge >= Config.BIOME_BLEND then return 0, 0 end
	local t = 1 - (toEdge / Config.BIOME_BLEND)                    -- normalize to (0..1) toward edge
	return t, (frac < 0.5) and -1 or 1
end

-- params:
--   Returns the shape/noise parameter set for biome 'idx'. Values are identical to your source.
function Biomes.params(idx)
	local SEA = Config.SEA_LEVEL
	local P = {
		-- === Boulder placement ===
		boulderCount   = 2,    -- how many boulders to try per tile/patch
		boulderScaleMax= 2.6,  -- max random scale multiplier for boulders
		boulderScaleMin= 0.9,  -- min random scale multiplier for boulders

		-- === Caves ===
		caveAmp        = 1.0,  -- amplitude (strength) of cave noise modulation
		caveFreq       = 0.010,-- frequency of cave noise; smaller = wider features, larger = tighter noise
		caveMaxY       = 900,  -- highest altitude caves can appear
		caveMinY       = SEA+30,-- lowest altitude caves can appear (here 30 studs above sea level)
		caveStartZFrac = 0.15, -- fraction of world Z dimension where caves start appearing
		caveThresh     = 0.66, -- noise threshold; lower = more open caves, higher = fewer caves

		-- === Cones / Volcano-like shapes ===
		coneAmp        = 0.0,  -- cone amplitude; >0 introduces big cone features (volcanic/peak)

		-- === Crevasses (linear cracks) ===
		crevAmp        = 120,  -- crevasse amplitude (depth/height of crack features)
		crevDir        = Vector2.new(1,0.35).Unit, -- dominant direction vector of cracks
		crevExp        = 1.5,  -- exponent shaping crevasse profile; >1 sharpens walls
		crevFreq       = 1/140,-- frequency: controls spacing between cracks

		-- === Elevation / world trend ===
		elevTrend      = 0.12, -- overall slope bias in elevation (adds gradual rise/fall)

		-- === Fractal layers (multi-octave terrain detail) ===
		f1Amp          = 120,  -- amplitude of fractal layer 1 (large hills/mountains)
		f1Freq         = 0.0018,-- frequency of fractal layer 1 (broad features)
		f2Amp          = 70,   -- amplitude of fractal layer 2 (mid detail)
		f2Freq         = 0.0036,-- frequency of fractal layer 2
		f3Amp          = 36,   -- amplitude of fractal layer 3 (fine surface detail)
		f3Freq         = 0.0072,-- frequency of fractal layer 3

		-- === High altitude cutoff ===
		highAlt        = 1200, -- altitude above which biome might switch to "highland" rules

		-- === Ridge noise (sharp mountain spines) ===
		r1Amp          = 300,  -- amplitude of ridge noise layer 1 (major ridges)
		r1Freq         = 0.0030,-- frequency of ridge noise layer 1
		r2Amp          = 120,  -- amplitude of ridge noise layer 2 (secondary ridges)
		r2Freq         = 0.0060,-- frequency of ridge noise layer 2

		-- === Terracing (step-like cliffs/plateaus) ===
		terraceBlend   = 6,    -- blend width; smooths transitions between steps
		terraceStep    = 16,   -- vertical size of each step

		-- === Tubes (tunnel-like cave features) ===
		tubeCount      = 1,    -- number of tunnel tubes to try generating
		tubeLen        = 180,  -- average tunnel length in studs
		tubeRadius     = 10,   -- tunnel radius

		-- === Warping (extra displacement noise for natural look) ===
		warp1Amp       = 70,   -- displacement strength of warp layer 1
		warp1Freq      = 0.004,-- frequency of warp layer 1
		warp2Amp       = 20,   -- displacement strength of warp layer 2
		warp2Freq      = 0.008 -- frequency of warp layer 2
	}

	if idx==1 then
		P.boulderCount=2 
		P.caveStartZFrac=0
		P.caveThresh=0 
		P.crevAmp=0 
		P.elevTrend=0.1 
		P.f1Amp=8 
		P.f2Amp=4 
		P.f3Amp=2
		P.r1Amp=18 
		P.r2Amp=7
		P.terraceBlend=5
		P.terraceStep=10 
		P.tubeCount=0 
	elseif idx==2 then
		P.boulderCount=3 
		P.elevTrend=0.15
		P.f1Amp=120/2
		P.f2Amp=70/2
		P.f3Amp=36/2
		P.r1Amp=300/2
		P.r2Amp=120/2
		P.caveStartZFrac=50
		P.caveAmp=1.0
		P.caveFreq=1.0
		P.caveMaxY=32
		P.caveMinY=0	
		P.terraceBlend=6
		P.terraceStep=14 
		P.tubeCount=10		
	elseif idx==3 then
		P.boulderCount=4
		P.caveStartZFrac=0.12
		P.caveThresh=0.64
		P.crevAmp=32
		P.elevTrend=0.2
		P.terraceBlend=7 
		P.terraceStep=18 
	elseif idx==4 then
		P.boulderCount=5
		P.caveStartZFrac=0.08
		P.caveThresh=0.62
		P.crevAmp=64
		P.elevTrend=0.25
		P.terraceBlend=9
		P.terraceStep=22
	elseif idx==5 then
		P.boulderCount=6
		P.caveMaxY=1100 
		P.caveStartZFrac=0.06
		P.caveThresh=0.60
		P.coneAmp=0.0009 
		P.crevAmp=128
		P.elevTrend=0.35 
		P.highAlt=1400 
		P.terraceBlend=10 
		P.terraceStep=26 
	end
	return P
end

return Biomes
```

## Caves (Module script)

```lua
-- Caves (Module script, optimized)
-- Purpose:
--   Provides signed fields for noise caves and tubular tunnels used by TileBuilder.
--   This pass removes heavy Vector3 allocations in tunnelField by doing scalar
--   point-to-segment distance math and hoists common math ops. Feature parity preserved.
--
-- Public API (unchanged):
--   Caves.caveField(x,y,z, biomeIdx, surfH) -> number   -- positive => air (carve)
--   Caves.tunnelField(x,y,z, tubes)         -> number   -- radius - distance (studs)

local Config  = require(script.Parent.WorldConfig)
local Biomes  = require(script.Parent.Biomes)
local HF      = require(script.Parent.Height)

local Caves = {}

-- caveField:
--   Signed noise field around the surface, gated by biome-specific Z/Y bands.
--   Returns t - threshold, where t∈[0..caveAmp] — positive values indicate AIR.
function Caves.caveField(x,y,z, biomeIdx, surfH)
	local P = Biomes.params(biomeIdx)                                         -- P : biome parameter table
	local z0 = (biomeIdx-1) * Config.BIOME_LENGTH                             -- z0 : biome strip start Z
	local frac = HF.clamp((z - z0) / Config.BIOME_LENGTH, 0, 1)               -- frac : 0..1 position within biome
	if frac < (P.caveStartZFrac or 0) then return -1 end                      -- early out before start band
	if y < (P.caveMinY or Config.SEA_LEVEL+30) or y > (P.caveMaxY or 900) then return -1 end
	if (surfH - y) > 18 then return -1 end                                    -- only near surface
	local f = (P.caveFreq or 0.010)
	local n = HF.n3(x*f, y*f*0.7, z*f)                                        -- n : coherent noise [-1..1]
	local t = (n*0.5 + 0.5) * (P.caveAmp or 1.0)                               -- t : [0..caveAmp]
	return t - (P.caveThresh or 0.66)                                         -- >0 => air
end

-- tunnelField:
--   Signed distance-like field for a union of finite cylinders (tubes).
--   For each tube, measure distance from point (x,y,z) to segment [a..b], return max(radius - d).
--   Optimized to avoid per-voxel Vector3 allocations and repeated dot products.
function Caves.tunnelField(x,y,z,tubes)
	local bestAir = -1e9                                                      -- bestAir : maximum (radius - d)
	for _,T in ipairs(tubes) do
		-- Segment endpoints a..b
		local ax, ay, az = T.c.X, T.c.Y, T.c.Z
		local bx, by, bz = ax + T.dir.X*T.len, ay + T.dir.Y*T.len, az + T.dir.Z*T.len

		-- Vector a->p and a->b
		local apx, apy, apz = x-ax, y-ay, z-az
		local abx, aby, abz = bx-ax, by-ay, bz-az

		-- t = clamp( (ap·ab) / (ab·ab), 0..1 )
		local ap_dot_ab = apx*abx + apy*aby + apz*abz
		local ab_dot_ab = math.max(abx*abx + aby*aby + abz*abz, 1e-6)
		local t = ap_dot_ab / ab_dot_ab
		if t < 0 then t = 0 elseif t > 1 then t = 1 end

		-- Closest point c = a + ab * t
		local cx = ax + abx*t
		local cy = ay + aby*t
		local cz = az + abz*t

		-- Distance from p to c
		local dx, dy, dz = x-cx, y-cy, z-cz
		local d = math.sqrt(dx*dx + dy*dy + dz*dz)

		local air = (T.radius or 20) - d                                      -- positive => air
		if air > bestAir then bestAir = air end
	end
	return bestAir
end

return Caves
```

## Height (Module script)

```lua
-- Height (Module script, optimized/math-documented)
-- Purpose:
--   Produces the continuous surface heightfield for all biomes, including:
--     - Single-biome evaluation (surfaceSingle)
--     - Seamless, *phase-stable* biome morphing across BIOME_BLEND (surface)
--     - Beach ramp for biome 1
--     - Vertical offsets per-biome (computeOffsets) to equalize seam means
--   Exposes helpers (n3, ridge, clamp, lerp, beachT) used by other modules.
--
-- Notes on perf/math:
--   • Hoists Config constants & math funcs to locals.
--   • Avoids needless allocations; reuses simple arithmetic.
--   • Morph keeps high-frequency bands locked to a center frequency to avoid beating
--     (classic trick from 1900s “constant-Q blending” in signal theory).
--   • Terracing strength fades with |s| (signed position across band) via smoothstep.

local Terrain = workspace.Terrain                                         -- Terrain reference (not used directly here; kept for parity)
local Config  = require(script.Parent.WorldConfig)                        -- Config table (tile sizes, VOX, sea level, etc.)
local Biomes  = require(script.Parent.Biomes)                             -- Biome parameter & material specs

-- ========= local constants / aliases =========
local WORLD_START_Z   = Config.WORLD_START_Z                               -- world Z where biomes begin (studs)
local BIOME_LENGTH    = Config.BIOME_LENGTH                                -- biome width along +Z (studs)
local BIOME_COUNT     = Config.BIOME_COUNT                                 -- number of biomes
local BIOME_BLEND     = math.max(1, Config.BIOME_BLEND)                    -- morph band width (studs), clamped ≥1
local SEA_LEVEL       = Config.SEA_LEVEL                                   -- sea level height (studs)
local WORLD_END_Z     = WORLD_START_Z + BIOME_LENGTH * BIOME_COUNT         -- last Z edge of world biomes (studs)

-- localize math (tiny micro-opts)
local abs, floor, max, min, sqrt = math.abs, math.floor, math.max, math.min, math.sqrt
local clampM, lerpM = math.clamp, function(a,b,t) return a + (b-a)*t end

-- ========= shared noise offsets =========
local function srand(n)                                                    -- srand: seed → 3 deterministic offsets for noise axes
	local r = Random.new(n)                                                -- r : RNG
	return r:NextNumber(-1e5,1e5), r:NextNumber(-1e5,1e5), r:NextNumber(-1e5,1e5)
end
local ox, oy, oz = srand(Config.SEED)                                      -- ox,oy,oz : shared noise offsets (phase-stable across modules)

-- ========= helpers =========
local function n3(x,y,z) return math.noise(x+ox,y+oy,z+oz) end             -- n3: coherent 3D noise with global offsets
local function ridge(n)  return 1 - abs(n) end                              -- ridge: “ridged” noise basis (|n| inverted)
local function clamp(v,a,b) return (v<a) and a or ((v>b) and b or v) end    -- clamp: branchy clamp (slightly cheaper than math.clamp)
local function lerp(a,b,t) return a + (b-a)*t end                           -- lerp: linear interpolation

-- ========= beach ramp (biome 1) =========
-- Beach curve from SEA_LEVEL-2 up to SEA_LEVEL+24 over ~420 studs using pow curve.
local BEACH_LEN, BEACH_LOW, BEACH_HIGH, BEACH_SHAPE = 420, SEA_LEVEL - 2, SEA_LEVEL + 24, 2.2
local function beachT(z) return (clamp((z - WORLD_START_Z)/BEACH_LEN,0,1)) ^ BEACH_SHAPE end -- beachT: (0..1) ramp from world start
local function beachProfile(z) return lerpM(BEACH_LOW, BEACH_HIGH, beachT(z)) end            -- beachProfile: low→high by beachT

-- ========= per-biome vertical offsets (computed) =========
local Offsets = table.create(max(1, BIOME_COUNT), 0)                        -- Offsets[j] : additive height offset for biome j
Offsets[1] = 0

-- legacy seam heights (kept for compatibility; used only for analytics/other modules)
local SeamHeights = table.create(max(1, BIOME_COUNT - 1), 0)               -- SeamHeights[j] : mean seam height between j & j+1

local Height = {}

-- ========= base pieces (single-biome raw) =========
-- elevBias:
--   Large-scale uptrend (elevTrend * z) + optional “coneAmp” focus field used in high-alt biomes.
local function elevBias(x,z,P,idx)
	local up = (P.elevTrend or 0) * z                                      -- up : linear uplift along Z
	if (P.coneAmp or 0) ~= 0 then
		local focus = Vector2.new(0, WORLD_END_Z + 16000)                  -- distant focal point; keeps gradient gentle
		local dx, dz = x - focus.X, z - focus.Y
		local d = sqrt(dx*dx + dz*dz)                                      -- Euclidean distance (studs)
		up = up + P.coneAmp * max(0, 220000 - d)
	end
	if idx==1 then                                                         -- beach-only: blend bias with flat waterline near start
		up = lerpM(SEA_LEVEL + 1, up, beachT(z))
	end
	return up
end

-- crevCut:
--   “Crevasse” negative cut using ridged noise along oblique direction crevDir.
local function crevCut(x,z,P)
	local dir = P.crevDir or Vector2.new(1,0.35).Unit
	local u = (x*(dir.X) + z*(dir.Y))
	local r = ridge(n3(u*(P.crevFreq or (1/140)), 0.45, 0.0))
	return - (r ^ (P.crevExp or 1.5)) * (P.crevAmp or 0)
end

-- warpDisp:
--   Phase-coherent displacement field (two octaves) added to x,z to “bend” features together.
local function warpDisp(P, x, z)
	local w1f, w1a = P.warp1Freq or 0.004, P.warp1Amp  or 70
	local w2f, w2a = P.warp2Freq or 0.008, P.warp2Amp  or 20
	local w1 = n3(x*w1f,0.25,z*w1f)*w1a
	local w2 = n3(x*w2f,0.35,z*w2f)*w2a
	return w1 + w2
end

-- singleRaw:
--   Core single-biome height (before offset): ridge + fbm + uplift + crevasse + terrace + beach ramp.
local function singleRaw(x,z,P,idx)
	local d  = warpDisp(P, x, z)                                           -- d : displacement (studs)
	local wx, wz = x + d, z + d                                            -- wx,wz : warped sample coords

	local fBeach = (idx==1) and beachT(z) or 1                             -- fBeach : tame high-freq near start for beach

	-- 2x ridge bands
	local r1 = ridge(n3(wx*(P.r1Freq or 0.003),0.6,wz*(P.r1Freq or 0.003)))*(P.r1Amp or 0)*fBeach
	local r2 = ridge(n3(wx*(P.r2Freq or 0.006),0.8,wz*(P.r2Freq or 0.006)))*(P.r2Amp or 0)*fBeach

	-- 3x fbm bands
	local f1f,f2f,f3f = (P.f1Freq or 0.0018),(P.f2Freq or 0.0036),(P.f3Freq or 0.0072)
	local f1a,f2a,f3a = (P.f1Amp  or 120),(P.f2Amp  or 70),(P.f3Amp  or 36)
	local fbm = (0.55*n3(wx*f1f,0.1,wz*f1f)*f1a + 0.30*n3(wx*f2f,0.2,wz*f2f)*f2a + 0.15*n3(wx*f3f,0.3,wz*f3f)*f3a) * fBeach

	local h = elevBias(wx, wz, P, idx) + r1 + r2 + fbm + (crevCut(wx, wz, P) * fBeach) -- h : raw height
	h = max(h, SEA_LEVEL - 12)                                             -- never drop too far below sea for stability

	-- terraces (snap-to-step with blend factor)
	local step   = P.terraceStep  or 16
	local blendK = P.terraceBlend or 6
	local q = floor((h / step) + 0.5) * step
	h = lerp(h, q, clampM(blendK / step, 0, 1))

	-- beach ramp into biome 1
	if idx==1 then
		h = lerpM(beachProfile(z), h, clamp((z - WORLD_START_Z) / (BEACH_LEN*1.05), 0, 1))
	end

	return max(h, SEA_LEVEL - 12)
end

-- surfaceSingle:
--   Public single-biome surface (adds per-biome vertical Offsets[j]).
function Height.surfaceSingle(x,z,P,idx)
	return singleRaw(x,z,P,idx) + (Offsets[idx] or 0)
end

-- ========= morph helpers =========
local function mixParams(Pa, Pb, t)
	local Pm = {}
	local function L(a,b) return a + (b-a)*t end

	Pm.elevTrend   = L(Pa.elevTrend   or 0, Pb.elevTrend   or 0)
	Pm.coneAmp     = L(Pa.coneAmp     or 0, Pb.coneAmp     or 0)

	Pm.r1Amp,  Pm.r1Freq  = L(Pa.r1Amp or 0, Pb.r1Amp or 0),   L(Pa.r1Freq or 0, Pb.r1Freq or 0)
	Pm.r2Amp,  Pm.r2Freq  = L(Pa.r2Amp or 0, Pb.r2Amp or 0),   L(Pa.r2Freq or 0, Pb.r2Freq or 0)

	Pm.f1Amp,  Pm.f1Freq  = L(Pa.f1Amp or 0, Pb.f1Amp or 0),   L(Pa.f1Freq or 0, Pb.f1Freq or 0)
	Pm.f2Amp,  Pm.f2Freq  = L(Pa.f2Amp or 0, Pb.f2Amp or 0),   L(Pa.f2Freq or 0, Pb.f2Freq or 0)
	Pm.f3Amp,  Pm.f3Freq  = L(Pa.f3Amp or 0, Pb.f3Amp or 0),   L(Pa.f3Freq or 0, Pb.f3Freq or 0)

	Pm.warp1Amp, Pm.warp1Freq = L(Pa.warp1Amp or 0, Pb.warp1Amp or 0), L(Pa.warp1Freq or 0, Pb.warp1Freq or 0)
	Pm.warp2Amp, Pm.warp2Freq = L(Pa.warp2Amp or 0, Pb.warp2Amp or 0), L(Pa.warp2Freq or 0, Pb.warp2Freq or 0)

	Pm.crevAmp, Pm.crevFreq, Pm.crevExp = L(Pa.crevAmp or 0, Pb.crevAmp or 0), L(Pa.crevFreq or 0, Pb.crevFreq or 0), L(Pa.crevExp or 1.5, Pb.crevExp or 1.5)
	local d = Vector2.new(L(Pa.crevDir.X, Pb.crevDir.X), L(Pa.crevDir.Y, Pb.crevDir.Y))
	Pm.crevDir = (d.Magnitude > 1e-6) and d.Unit or (Pa.crevDir or Vector2.new(1,0.35).Unit)

	Pm.terraceStep  = L(Pa.terraceStep  or 16, Pb.terraceStep  or 16)
	Pm.terraceBlend = L(Pa.terraceBlend or 6,  Pb.terraceBlend or 6)

	Pm.highAlt = L(Pa.highAlt or 1200, Pb.highAlt or 1200)

	return Pm
end

-- center frequency (avoid beating for high-freq terms)
local function cf(a,b) return 0.5*(a + b) end

-- singleRawMorph:
--   Morph-safe version of singleRaw with phase coherence across the band.
local function singleRawMorph(x,z,Pa,Pb,Pm,fBeach,terrMul,tWarp)
	-- Warp displacement: interpolate the two warps to stay phase-consistent
	local da = warpDisp(Pa, x, z)
	local db = warpDisp(Pb, x, z)
	local d  = lerpM(da, db, tWarp or 0.5)
	local wx, wz = x + d, z + d

	-- Frequencies: r1/f1 morph, others lock to center frequency to avoid beating
	local r1Freq = Pm.r1Freq
	local r2Freq = cf(Pa.r2Freq or 0, Pb.r2Freq or 0)
	local f1Freq = Pm.f1Freq
	local f2Freq = cf(Pa.f2Freq or 0, Pb.f2Freq or 0)
	local f3Freq = cf(Pa.f3Freq or 0, Pb.f3Freq or 0)
	local crevFreq = cf(Pa.crevFreq or 0, Pb.crevFreq or 0)

	local r1 = ridge(n3(wx*r1Freq,0.6,wz*r1Freq))*Pm.r1Amp*fBeach
	local r2 = ridge(n3(wx*r2Freq,0.8,wz*r2Freq))*Pm.r2Amp*fBeach
	local fbm = (0.55*n3(wx*f1Freq,0.1,wz*f1Freq)*Pm.f1Amp
		+ 0.30*n3(wx*f2Freq,0.2,wz*f2Freq)*Pm.f2Amp
		+ 0.15*n3(wx*f3Freq,0.3,wz*f3Freq)*Pm.f3Amp) * fBeach

	-- uplift (with optional cone)
	local up = (Pm.elevTrend or 0) * z
	if (Pm.coneAmp or 0) ~= 0 then
		local focus = Vector2.new(0, WORLD_END_Z + 16000)
		local dx, dz = wx - focus.X, wz - focus.Y
		local dist = sqrt(dx*dx + dz*dz)
		up = up + Pm.coneAmp * max(0, 220000 - dist)
	end
	up = lerpM(SEA_LEVEL + 1, up, fBeach)

	-- crevasse cut (keep center frequency)
	local cut = 0
	if (Pm.crevAmp or 0) ~= 0 then
		local u = (wx*Pm.crevDir.X + wz*Pm.crevDir.Y)
		cut = - (ridge(n3(u*crevFreq, 0.45, 0.0)) ^ (Pm.crevExp or 1.5)) * (Pm.crevAmp or 0)
	end

	local h = up + r1 + r2 + fbm + cut
	h = max(h, SEA_LEVEL - 12)

	-- terraces: symmetric fade toward center (never zero)
	local terrStrength = clampM(0.35 - 0.65*terrMul, 0, 1)
	local step   = cf(Pa.terraceStep or 16,  Pb.terraceStep or 16)
	local blendK = cf(Pa.terraceBlend or 6, Pb.terraceBlend or 6)

	local q = floor((h / step) + 0.5) * step
	h = lerp(h, q, clampM((blendK / step) * terrStrength, 0, 1))

	return max(h, SEA_LEVEL - 12)
end

-- surface:
--   True morph across BIOME_BLEND around nearest boundary center.
function Height.surface(x,z,idx)
	-- nearest boundary center index m (between biome m and m+1), in 0..BIOME_COUNT-1
	local rel   = (z - WORLD_START_Z) / BIOME_LENGTH
	local m     = clampM(floor(rel + 0.5), 0, BIOME_COUNT - 1)
	local zEdge = WORLD_START_Z + m * BIOME_LENGTH

	-- signed position through the morph band
	local s  = (z - zEdge) / BIOME_BLEND
	if s <= -1 or s >= 1 then
		return Height.surfaceSingle(x, z, Biomes.params(idx), idx)
	end

	-- left/right biome indices
	local leftIdx  = clampM(m,     1, BIOME_COUNT)
	local rightIdx = clampM(m + 1, 1, BIOME_COUNT)
	local Pa, Pb   = Biomes.params(leftIdx), Biomes.params(rightIdx)

	-- left→right ramp (0 at left rim, 0.5 at edge, 1 at right rim), smoothstep
	local t  = 0.5 + 0.5 * s
	local ts = t * t * (3 - 2 * t)

	-- beach factor & vertical offset morph
	local fA = (leftIdx  == 1) and beachT(z) or 1
	local fB = (rightIdx == 1) and beachT(z) or 1
	local f  = lerpM(fA, fB, ts)
	local off = lerpM((Offsets[leftIdx]  or 0), (Offsets[rightIdx] or 0), ts)

	-- symmetric terrace fade (uses |s|)
	local a = abs(s)
	local terrMul = a*a*(3 - 2*a)

	local Pm = mixParams(Pa, Pb, ts)
	return singleRawMorph(x, z, Pa, Pb, Pm, f, terrMul, ts) + off
end

-- computeOffsets:
--   Integrates per-biome mean differences at each seam so the *average* height matches, then
--   records the actual seam mean (SeamHeights) for diagnostics/other modules.
function Height.computeOffsets()
	Offsets = table.create(BIOME_COUNT, 0); Offsets[1] = 0

	for j=2, BIOME_COUNT do
		local A = Biomes.params(j-1)
		local B = Biomes.params(j)
		local zB = WORLD_START_Z + (j-1)*BIOME_LENGTH

		local accum, samples = 0, 0
		for s=-2,2 do
			local x = s*64
			accum = accum + (singleRaw(x, zB, A, j-1) - singleRaw(x, zB, B, j))
			samples += 1
		end
		Offsets[j] = Offsets[j-1] + (accum / max(samples,1))
	end

	for j=1, (BIOME_COUNT - 1) do
		local A = Biomes.params(j)
		local B = Biomes.params(j+1)
		local zB = WORLD_START_Z + j*BIOME_LENGTH

		local sum, samples = 0, 0
		for s=-2,2 do
			local x = s*64
			local ha = singleRaw(x, zB, A, j)   + (Offsets[j]   or 0)
			local hb = singleRaw(x, zB, B, j+1) + (Offsets[j+1] or 0)
			sum += 0.5*(ha + hb)
			samples += 1
		end
		SeamHeights[j] = (samples > 0) and (sum / samples) or SEA_LEVEL
	end
end

-- expose helpers used elsewhere
Height.n3      = n3
Height.ridge   = ridge
Height.clamp   = clamp
Height.lerp    = lerp
Height.beachT  = beachT

return Height
```

## Materials (Module script)
```lua
-- Materials (Module script, optimized comments)
-- Purpose:
--   Chooses a Roblox Terrain material for a voxel based on height, slope, and curvature,
--   with deterministic cross-biome blending near seams.
--   Behavior unchanged; minor micro-opts and detailed variable comments added.

local Config  = require(script.Parent.WorldConfig)
local Biomes  = require(script.Parent.Biomes)

local Materials = {}

-- pickMat:
--   Core material decision for a *single biome*:
--   - Tertiary for high altitude OR steep slope
--   - Secondary for concave curvature (curv below threshold)
--   - Primary otherwise
local function pickMat(y, slopeGrad, curv, mats, highAlt)
	local secCurve  = mats.SecondaryCurve or -10     -- SecondaryCurve: curvature threshold (lower => more concave)
	local tertSlope = mats.TertiarySlope  or 2.75    -- TertiarySlope : gradient magnitude threshold for cliffs
	local highA     = highAlt or 1200                -- highAlt       : altitude threshold for snow/rock

	if y >= highA then return mats.Tertiary end
	if slopeGrad >= tertSlope then return mats.Tertiary end
	if curv < secCurve then return mats.Secondary end
	return mats.Primary
end

-- choose:
--   Public wrapper retained for API stability.
function Materials.choose(y, slopeGrad, curv, mats, highAlt)
	return pickMat(y, slopeGrad, curv, mats, highAlt)
end

-- columnBlendSetup:
--   Returns a stable token describing which two neighbor biomes to blend across the material band,
--   including a smooth t∈[0..1] and a per-column deterministic dither value hCol∈[0..1].
function Materials.columnBlendSetup(worldX, worldZ, _)
	-- Early out if we’re not near any biome edge at all
	local tEdge = select(1, Biomes.edgeBlend(worldZ))   -- tEdge : 0 outside geom blend; >0 inside
	if tEdge == 0 then return nil end

	-- Nearest boundary center (between biome m and m+1)
	local rel   = (worldZ - Config.WORLD_START_Z) / Config.BIOME_LENGTH
	local m     = math.clamp(math.floor(rel + 0.5), 0, Config.BIOME_COUNT - 1)
	local zEdge = Config.WORLD_START_Z + m * Config.BIOME_LENGTH

	-- Material blend band width (slightly smaller than geometry band)
	local w = math.min(Config.MAT_BLEND, math.max(8, Config.BIOME_BLEND - 16))
	local s = (worldZ - zEdge) / w
	if s < -1 or s > 1 then return nil end

	-- Left→right ramp across the *material* band only (smoothstep)
	local t = 0.5 + 0.5 * s
	t = t * t * (3 - 2 * t)

	-- Boundary pair (left m, right m+1), clamped to 1..BIOME_COUNT
	local leftIdx  = math.clamp(m,     1, Config.BIOME_COUNT)
	local rightIdx = math.clamp(m + 1, 1, Config.BIOME_COUNT)

	local leftMats   = Biomes.Materials[leftIdx]
	local rightMats  = Biomes.Materials[rightIdx]
	local leftHigh   = (Biomes.params(leftIdx).highAlt  or 1200)
	local rightHigh  = (Biomes.params(rightIdx).highAlt or 1200)

	-- Stable per-column dither in [0..1] based on integerized world coords (avoids banding)
	local ix = math.floor(worldX/Config.VOX + 0.5)
	local iz = math.floor(worldZ/Config.VOX + 0.5)
	local n  = bit32.bxor(ix*73856093, iz*19349663)
	n = bit32.bxor(n, bit32.rshift(n, 13))
	n = (n * 1274126177) % 0x80000000
	local hCol = n / 0x80000000

	return {
		leftMats  = leftMats,      -- materials on the left side of the edge
		rightMats = rightMats,     -- materials on the right side of the edge
		leftHigh  = leftHigh,      -- left high-alt threshold
		rightHigh = rightHigh,     -- right high-alt threshold
		tSmooth   = t,             -- smooth ramp 0..1 across the band
		hCol      = hCol,          -- deterministic per-column noise 0..1 for dithering
	}
end

-- blendedVoxel:
--   Given the cached blend token, dither-select left vs right material at this voxel.
function Materials.blendedVoxel(y, slopeGrad, curv, _colMats, _colHigh, blendState)
	-- Evaluate both sides with local rules
	local a = pickMat(y, slopeGrad, curv, blendState.leftMats,  blendState.leftHigh)
	local b = pickMat(y, slopeGrad, curv, blendState.rightMats, blendState.rightHigh)
	if a == b then return a end
	-- Dither threshold: as we approach the edge, choose 'b' more often
	return (blendState.hCol < blendState.tSmooth) and b or a
end

return Materials
```

##Stamps (Module script)
```lua
-- Stamps (Module script, clarified; light micro-opts)
-- Purpose:
--   Determines deterministic mesh-stamp (e.g., boulders) placements per tile and returns
--   world-space transforms & prebuilt stencils used by TileBuilder to add solids.
--   Behavior unchanged; comments added and minor local caching.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config  = require(script.Parent.WorldConfig)
local Biomes  = require(script.Parent.Biomes)
local HF      = require(script.Parent.Height)

local StencilCache = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BoulderStencilCache")).Build()

local Stamps = {}

-- tileSeed:
--   Stable per-tile RNG seed (independent of world SEED so stamps remain consistent).
local function tileSeed(i,k)
	local a = math.floor(i * 73856093)
	local b = math.floor(k * 19349663)
	local c = math.floor(1337 * 83492791)
	return bit32.band(bit32.bxor(bit32.bxor(a,b),c), 0x7fffffff)
end

-- pickBoulderName:
--   Randomly pick a boulder asset name from ReplicatedStorage.Terrain.Boulders (if available).
local function pickBoulderName(rng)
	local folder = ReplicatedStorage.Terrain:FindFirstChild("Boulders")
	if not folder then return nil end
	local kids = folder:GetChildren()
	if #kids == 0 then return nil end
	return kids[rng:NextInteger(1,#kids)].Name
end

-- placementsForTile:
--   Returns an array of stamp placements for tile (i,k) using biome at tile center.
--   Each entry: { cframe=CFrame, scale=number, stencil=Stencil, [halfXZ],[halfY],[worldBB] }
function Stamps.placementsForTile(i,k, baseBiome)
	local rng = Random.new(tileSeed(i,k))
	local P = Biomes.params(baseBiome)
	local list, count = {}, math.min(P.boulderCount, 2)       -- conservative cap per tile (as in your original)
	local minX, minZ = i*Config.TILE_SIZE, k*Config.TILE_SIZE
	local maxX, maxZ = minX + Config.TILE_SIZE, minZ + Config.TILE_SIZE

	for _=1,count do
		local name = pickBoulderName(rng)
		local stencil = name and StencilCache.stencils[name]
		if stencil then
			local cx = rng:NextNumber(minX + 0.2*Config.TILE_SIZE, maxX - 0.2*Config.TILE_SIZE)
			local cz = rng:NextNumber(minZ + 0.2*Config.TILE_SIZE, maxZ - 0.2*Config.TILE_SIZE)
			local h  = HF.surface(cx, cz, baseBiome)
			local yaw   = rng:NextNumber(0, math.pi*2)
			local pitch = rng:NextNumber(-0.2, 0.2)
			local roll  = rng:NextNumber(-0.2, 0.2)
			local scale = rng:NextNumber(P.boulderScaleMin, P.boulderScaleMax)
			list[#list+1] = {
				cframe = CFrame.new(cx, h, cz) * CFrame.Angles(0,yaw,0) * CFrame.Angles(pitch,0,roll), -- world transform
				scale  = scale,    -- uniform mesh scale
				stencil= stencil,  -- cached SDF-like sampler for stamp shape
			}
		end
	end
	return list
end

return Stamps
```

## TileBuilder (Module script)
```lua
-- TileBuilder (Module script, high-impact perf pass; feature parity preserved)
-- Purpose:
--   Builds/unbuilds a terrain tile (voxel write budgeted per-slice) including:
--     • Heightfield crust, materials, caves (noise + tubes), and mesh stamps
--     • Vegetation handoff (plan/build/unbuild handled in Vegetation module)
--     • Budgeted async eraser with pooled air buffers for fast despawn
--
-- What changed (perf):
--   • Hoisted math/Config constants and reused locals aggressively.
--   • Height grid precomputation kept; clarified bounds and sampling.
--   • Column cache retains biome/material/derivatives per (vx,vz).
--   • Prefilter stamps per chunk (XZ) and *per-slice* (Y) retained; tightened guards.
--   • Region3 created only when the slice actually touched (avoid garbage per empty slice).
--   • Tiny branch reorderings, fewer table.inserts in hot paths (#idx writes).
--   • Air buffer pool kept; skip-empty read maintained.
--
-- Public API (unchanged):
--   TileBuilder.build(i,k)
--   TileBuilder.unbuild(i,k)

local Terrain   = workspace.Terrain
local RunService= game:GetService("RunService")

local Config    = require(script.Parent.WorldConfig)
local Biomes    = require(script.Parent.Biomes)
local HF        = require(script.Parent.Height)
local Mats      = require(script.Parent.Materials)
local Caves     = require(script.Parent.Caves)
local Stamps    = require(script.Parent.Stamps)
local IO        = require(script.Parent.TileIO)
local Vegetation= require(script.Parent.Vegetation)

-- --- Unload budget (tune to taste)
local ERASE_STEPS_PER_TICK = 10     -- how many y-slices or chunks we erase per tick
local ERASE_TICK_INTERVAL  = 0.03   -- seconds between eraser ticks
local ERASE_PAD            = Config.VOX -- 1-voxel pad at tile edges
local SKIP_EMPTY_READ      = true   -- fast ReadVoxels check to skip empty chunks

-- tileSeed:
--   Stable per-tile RNG seed for tubes (depends on world SEED).
local function tileSeed(i,k)
	local a = math.floor(i * 73856093)
	local b = math.floor(k * 19349663)
	local c = math.floor(Config.SEED * 83492791)
	return bit32.band(bit32.bxor(bit32.bxor(a,b),c), 0x7fffffff)
end

local TileBuilder = {}

-- ===== Helpers for stamps with/without worldBB (kept for compatibility) =====
local function stampXZOverlapsChunk(p, wx0, wx1, wz0, wz1)
	if p.worldBB and p.worldBB.CFrame and p.worldBB.Size then
		local bbCF, bbS = p.worldBB.CFrame, p.worldBB.Size
		local minXw, maxXw = bbCF.Position.X - bbS.X*0.5, bbCF.Position.X + bbS.X*0.5
		local minZw, maxZw = bbCF.Position.Z - bbS.Z*0.5, bbCF.Position.Z + bbS.Z*0.5
		return not (maxXw < wx0 or minXw > wx1 or maxZw < wz0 or minZw > wz1)
	end
	local pos = p.cframe and p.cframe.Position or Vector3.zero
	local half = (p.halfXZ or (p.scale or 1) * 24)
	local minXw, maxXw = pos.X - half, pos.X + half
	local minZw, maxZw = pos.Z - half, pos.Z + half
	return not (maxXw < wx0 or minXw > wx1 or maxZw < wz0 or minZw > wz1)
end

local function stampYOverlapsSlice(p, wy0, wy1)
	if p.worldBB and p.worldBB.CFrame and p.worldBB.Size then
		local bbCF, bbS = p.worldBB.CFrame, p.worldBB.Size
		local minYw, maxYw = bbCF.Position.Y - bbS.Y*0.5, bbCF.Position.Y + bbS.Y*0.5
		return not (maxYw < wy0 or minYw > wy1)
	end
	local pos = p.cframe and p.cframe.Position or Vector3.zero
	local halfY = (p.halfY or (p.scale or 1) * 24)
	local minYw, maxYw = pos.Y - halfY, pos.Y + halfY
	return not (maxYw < wy0 or minYw > wy1)
end

-- ===== Build =====
function TileBuilder.build(i,k)
	-- Tile bounds in world & voxel space
	local minX,minZ,maxX,maxZ = IO.aabb(i,k)
	if maxZ < Config.WORLD_START_Z then return end

	local yFloor = Config.Y_MIN_WORLD
	local yCeil  = 1700 + Config.Y_HEADROOM
	local xMinV,xMaxV = IO.w2v(minX), IO.w2v(maxX-1)
	local zMinV,zMaxV = IO.w2v(minZ), IO.w2v(maxZ-1)
	local yMinV,yMaxV = IO.w2v(yFloor), IO.w2v(yCeil-1)

	-- Hoist constants (used everywhere)
	local VOX               = Config.VOX
	local CHUNK_VOX_XZ      = Config.CHUNK_VOX_XZ
	local CHUNK_VOX_Y       = Config.CHUNK_VOX_Y
	local WORLD_START_Z     = Config.WORLD_START_Z
	local CRUST_BELOW       = Config.CRUST_BELOW_STUDS
	local CRUST_ABOVE       = Config.CRUST_ABOVE_STUDS
	local CAVE_BELOW        = Config.CAVE_BAND_BELOW
	local CAVE_ABOVE        = Config.CAVE_BAND_ABOVE
	local STAMP_BELOW       = Config.STAMP_BAND_BELOW
	local STAMP_ABOVE       = Config.STAMP_BAND_ABOVE
	local BAND_BELOW_MAX    = math.max(CRUST_BELOW, CAVE_BELOW, STAMP_BELOW)
	local BAND_ABOVE_MAX    = math.max(CRUST_ABOVE, CAVE_ABOVE, STAMP_ABOVE)

	-- Decoupled cave wall thickness knobs (defaults keep parity)
	local CAVE_WALL_THICKNESS = Config.CAVE_WALL_THICKNESS or (VOX * 2)   -- studs: tube wall halo
	local CAVE_NOISE_MARGIN   = Config.CAVE_NOISE_MARGIN   or 0.08        -- dimensionless halo around noise cave boundary

	-- tubes per tile
	local rng = Random.new(tileSeed(i,k))
	local tubes = {}
	do
		local czMid = 0.5*(minZ+maxZ)
		local tileBiome = Biomes.indexForZ(czMid)
		local P = Biomes.params(tileBiome)
		for t=1,P.tubeCount do
			local cx = minX + rng:NextNumber(0.2,0.8)*Config.TILE_SIZE
			local cz2= minZ + rng:NextNumber(0.2,0.8)*Config.TILE_SIZE
			local cy = Config.SEA_LEVEL + rng:NextInteger(40, 260)
			local yaw= rng:NextNumber(0, math.pi*2)
			local dirV= Vector3.new(math.cos(yaw), rng:NextNumber(-0.12,0.12), math.sin(yaw)).Unit
			tubes[#tubes+1] = { c=Vector3.new(cx,cy,cz2), dir=dirV, radius=P.tubeRadius, len=P.tubeLen }
		end
	end

	-- mesh stamps for this tile
	local placements = Stamps.placementsForTile(i,k, Biomes.indexForZ(0.5*(minZ+maxZ)))

	-- ===== chunk iteration =====
	for x0=xMinV,xMaxV,CHUNK_VOX_XZ do
		for z0=zMinV,zMaxV,CHUNK_VOX_XZ do
			local x1 = math.min(x0+CHUNK_VOX_XZ-1, xMaxV)
			local z1 = math.min(z0+CHUNK_VOX_XZ-1, zMaxV)
			local wx0,wz0 = IO.v2w(x0), IO.v2w(z0)
			local wx1,wz1 = IO.v2w(x1+1), IO.v2w(z1+1)

			-- ===== Precompute height grid (RES_XZ) for this chunk =====
			local step = tonumber(Config.RES_XZ) or VOX; if step == 0 then step = VOX end
			local gxCount = math.floor((wx1 - wx0) / step) + 1
			local gzCount = math.floor((wz1 - wz0) / step) + 1
			local H = table.create(gxCount); for gx=1,gxCount do H[gx] = table.create(gzCount) end

			for gx=1,gxCount do
				local xw = wx0 + (gx-1)*step
				for gz=1,gzCount do
					local zw = (wz0 + (gz-1)*step)
					if zw < WORLD_START_Z then zw = WORLD_START_Z end
					local bIdx = Biomes.indexForZ(zw)
					H[gx][gz] = HF.surface(xw, zw, bIdx) -- one call reused
				end
			end

			local function hGrid(xw, zw)                                     -- fetch from grid (clamped)
				local gx = math.clamp(math.floor((xw - wx0)/step) + 1, 1, gxCount)
				local gz = math.clamp(math.floor((zw - wz0)/step) + 1, 1, gzCount)
				return H[gx][gz]
			end

			-- ===== per-chunk column cache =====
			local sizeX = x1-x0+1
			local sizeZ = z1-z0+1

			local col_h, col_grad, col_curv      = table.create(sizeX), table.create(sizeX), table.create(sizeX)
			local col_yMin, col_yMax             = table.create(sizeX), table.create(sizeX)
			local col_biome, col_mats, col_high  = table.create(sizeX), table.create(sizeX), table.create(sizeX)
			local col_blend, col_shoreLock       = table.create(sizeX), table.create(sizeX)

			for vx=1,sizeX do
				col_h[vx], col_grad[vx], col_curv[vx]      = table.create(sizeZ), table.create(sizeZ), table.create(sizeZ)
				col_yMin[vx], col_yMax[vx]                 = table.create(sizeZ), table.create(sizeZ)
				col_biome[vx], col_mats[vx], col_high[vx]  = table.create(sizeZ), table.create(sizeZ), table.create(sizeZ)
				col_blend[vx], col_shoreLock[vx]           = table.create(sizeZ), table.create(sizeZ)

				local worldX = wx0 + (vx-1)*VOX
				for vz=1,sizeZ do
					local worldZ = wz0 + (vz-1)*VOX; if worldZ < WORLD_START_Z then worldZ = WORLD_START_Z end

					local bIdx   = Biomes.indexForZ(worldZ)
					local bMats  = Biomes.Materials[bIdx]
					local highA  = (Biomes.params(bIdx).highAlt or 1200)
					local shoreG = (bIdx==1) and ((worldZ - WORLD_START_Z) < (420 + 160))

					-- surface & derivs (once per column)
					local h    = hGrid(worldX, worldZ)
					local hX1  = hGrid(worldX+Config.RES_XZ, worldZ)
					local hX0  = hGrid(worldX-Config.RES_XZ, worldZ)
					local hZ1  = hGrid(worldX, worldZ+Config.RES_XZ)
					local hZ0  = hGrid(worldX, worldZ-Config.RES_XZ)
					local dx   = (hX1 - hX0)*0.5
					local dz   = (hZ1 - hZ0)*0.5
					local grad = math.sqrt(dx*dx + dz*dz)
					local curv = h - 0.25*(hX1+hX0+hZ1+hZ0)

					col_h[vx][vz]         = h
					col_grad[vx][vz]      = grad
					col_curv[vx][vz]      = curv
					col_yMin[vx][vz]      = h - BAND_BELOW_MAX
					col_yMax[vx][vz]      = h + BAND_ABOVE_MAX
					col_biome[vx][vz]     = bIdx
					col_mats[vx][vz]      = bMats
					col_high[vx][vz]      = highA
					col_blend[vx][vz]     = Mats.columnBlendSetup(worldX, worldZ, bIdx)
					col_shoreLock[vx][vz] = shoreG
				end
			end

			-- ===== Prefilter stamps for this chunk (XZ AABB) =====
			local stampsForChunk = {}
			if #placements > 0 then
				for _,p in ipairs(placements) do
					if stampXZOverlapsChunk(p, wx0, wx1, wz0, wz1) then
						stampsForChunk[#stampsForChunk+1] = p
					end
				end
			end

			-- ===== Y-slices =====
			for y0v=yMinV,yMaxV,CHUNK_VOX_Y do
				local y1v = math.min(y0v+CHUNK_VOX_Y-1, yMaxV)
				local wy0,wy1 = IO.v2w(y0v), IO.v2w(y1v+1)

				-- fast slice probe: any column intersects this y-range?
				local anyTouches = false
				do
					local sx = {1, math.floor(sizeX*0.5), sizeX}
					local sz = {1, math.floor(sizeZ*0.5), sizeZ}
					for _,vx in ipairs(sx) do
						for _,vz in ipairs(sz) do
							if not (wy1 < col_yMin[vx][vz] or wy0 > col_yMax[vx][vz]) then
								anyTouches = true; break
							end
						end
						if anyTouches then break end
					end
				end
				if not anyTouches then
					RunService.Heartbeat:Wait()
					continue
				end

				-- Slice-local stamps, only when touching the stamp band anywhere
				local stampsThisSlice = nil
				if #stampsForChunk > 0 then
					local stampBandTouched = false
					do
						local sx = {1, math.floor(sizeX*0.5), sizeX}
						local sz = {1, math.floor(sizeZ*0.5), sizeZ}
						for _,vx in ipairs(sx) do
							for _,vz in ipairs(sz) do
								local h = col_h[vx][vz]
								local sMin = h - STAMP_BELOW
								local sMax = h + STAMP_ABOVE
								if not (wy1 < sMin or wy0 > sMax) then
									stampBandTouched = true; break
								end
							end
							if stampBandTouched then break end
						end
					end
					if stampBandTouched then
						stampsThisSlice = {}
						for _,p in ipairs(stampsForChunk) do
							if stampYOverlapsSlice(p, wy0, wy1) then
								stampsThisSlice[#stampsThisSlice+1] = p
							end
						end
					end
				end

				local sizeY = y1v-y0v+1
				local mats, occs = nil, nil
				local sliceTouched = false

				for vx=1,sizeX do
					local worldX = wx0 + (vx-1)*VOX
					for vz=1,sizeZ do
						local worldZ = wz0 + (vz-1)*VOX; if worldZ < WORLD_START_Z then worldZ = WORLD_START_Z end

						-- cull this column if slab is outside its band
						if (wy1 < col_yMin[vx][vz] or wy0 > col_yMax[vx][vz]) then
							continue
						end

						-- lazily allocate when first needed
						if not mats then
							mats, occs = IO.alloc(sizeX,sizeY,sizeZ, Enum.Material.Rock)
						end

						local h        = col_h[vx][vz]
						local grad     = col_grad[vx][vz]
						local curv     = col_curv[vx][vz]
						local bIdx     = col_biome[vx][vz]
						local bMats    = col_mats[vx][vz]
						local highAlt  = col_high[vx][vz]
						local blendTok = col_blend[vx][vz]
						local shoreG   = col_shoreLock[vx][vz]

						for vy=1,sizeY do
							local worldY = wy0 + (vy-1)*VOX
							local inCrust = (worldY >= h - CRUST_BELOW) and (worldY <= h + CRUST_ABOVE)
							local inCave  = (worldY >= h - CAVE_BELOW)  and (worldY <= h + CAVE_ABOVE)
							local inStamp = (worldY >= h - STAMP_BELOW) and (worldY <= h + STAMP_ABOVE)
							if not (inCrust or inCave or inStamp) then continue end

							local makeSolid, makeAir = false, false

							-- stamps
							if inStamp and stampsThisSlice and #stampsThisSlice > 0 then
								for _,p in ipairs(stampsThisSlice) do
									local pObj = p.cframe:PointToObjectSpace(Vector3.new(worldX, worldY, worldZ))
									local sObj = Vector3.new(pObj.X/p.scale, pObj.Y/p.scale, pObj.Z/p.scale)
									if p.stencil:sample(sObj) then makeSolid = true; break end
								end
							end

							-- caves/tubes: signed fields
							local sNoise, sTube
							if not shoreG and inCave then
								sNoise = Caves.caveField(worldX, worldY, worldZ, bIdx, h)         -- >0 => air
								if #tubes > 0 then
									sTube = Caves.tunnelField(worldX, worldY, worldZ, tubes)      -- radius - dist (studs)
								end
								if (sNoise and sNoise > 0) or (sTube and sTube > 0) then
									makeAir = true
								end
							end

							-- thin support walls near cave boundary (noise & tubes)
							local nearWallNoise = (sNoise ~= nil) and (sNoise <= 0) and (sNoise > -CAVE_NOISE_MARGIN)
							local nearWallTube  = (sTube  ~= nil) and (sTube  <= 0) and (sTube  > -CAVE_WALL_THICKNESS)
							local nearWall = nearWallNoise or nearWallTube

							-- SOLID decision: crust + thin ring near cave boundary
							if not makeAir then
								if inCrust or nearWall then
									makeSolid = true
								end
							end

							if makeSolid then
								occs[vx][vy][vz] = 1
								sliceTouched = true

								-- Depth below the local surface at this column
								local depthBelowSurface = (h - worldY)

								-- If we are sufficiently below the surface, force a cheap material.
								-- This guarantees the underside of the crust and deep interior are never Grass, etc.
								if depthBelowSurface >= (Config.DEEP_CHEAP_DEPTH_STUDS or 8) then
									mats[vx][vy][vz] = (Config.DEEP_CHEAP_MATERIAL or Enum.Material.Rock)
								else
									-- Near-surface: preserve your original material selection (incl. seam blending)
									if blendTok then
										mats[vx][vy][vz] = Mats.blendedVoxel(worldY, grad, curv, bMats, highAlt, blendTok)
									else
										mats[vx][vy][vz] = Mats.choose(worldY, grad, curv, bMats, highAlt)
									end
								end
							end
						end
					end
				end

				-- Only create Region3 and write if anything touched this slice
				if sliceTouched then
					local region = Region3.new(Vector3.new(wx0, wy0, wz0), Vector3.new(wx1, wy1, wz1))
					Terrain:WriteVoxels(region, VOX, mats, occs)
				end

				RunService.Heartbeat:Wait()
			end
		end
	end

	-- vegetation build pass
	Vegetation.buildTile(i,k)
end

-- === Air buffer pool keyed by (sx,sy,sz) ===
local AirPool = {}  -- ["sx|sy|sz"] -> {mats, occs}
local function getAirBuffers(sizeX, sizeY, sizeZ)
	local key = string.format("%d|%d|%d", sizeX, sizeY, sizeZ)
	local buf = AirPool[key]
	if buf then return buf.mats, buf.occs end
	local mats, occs = IO.alloc(sizeX, sizeY, sizeZ, Enum.Material.Air)
	AirPool[key] = {mats = mats, occs = occs}
	return mats, occs
end

-- === Async eraser queue ===
local EraseQ = {}
local eraserRunning = false
local function enqueueErase(state)
	table.insert(EraseQ, state)
	if not eraserRunning then
		eraserRunning = true
		task.spawn(function()
			while #EraseQ > 0 do
				local steps = ERASE_STEPS_PER_TICK
				while steps > 0 and #EraseQ > 0 do
					local st = EraseQ[1]
					if st.step() then
						table.remove(EraseQ, 1)
					end
					steps -= 1
				end
				task.wait(ERASE_TICK_INTERVAL)
			end
			eraserRunning = false
		end)
	end
end

-- === Unbuild (budgeted, non-spiky) ===
function TileBuilder.unbuild(i,k)
	-- Vegetation first
	if Vegetation and Vegetation.unbuildTile then
		Vegetation.unbuildTile(i,k)
	end

	local minX,minZ,maxX,maxZ = IO.aabb(i,k, ERASE_PAD)
	local yFloor = Config.Y_MIN_WORLD
	local yCeil  = 1700 + Config.Y_HEADROOM
	local xMinV,xMaxV = IO.w2v(minX), IO.w2v(maxX-1)
	local zMinV,zMaxV = IO.w2v(minZ), IO.w2v(maxZ-1)
	local yMinV,yMaxV = IO.w2v(yFloor), IO.w2v(yCeil-1)

	local chunks = {}
	for x0 = xMinV, xMaxV, Config.CHUNK_VOX_XZ do
		for z0 = zMinV, zMaxV, Config.CHUNK_VOX_XZ do
			local x1 = math.min(x0 + Config.CHUNK_VOX_XZ - 1, xMaxV)
			local z1 = math.min(z0 + Config.CHUNK_VOX_XZ - 1, zMaxV)
			chunks[#chunks+1] = {x0=x0, x1=x1, z0=z0, z1=z1, y0=yMinV}
		end
	end

	local idx = 1
	local function step()
		if idx > #chunks then return true end
		local c = chunks[idx]
		if c.y0 > yMaxV then
			idx += 1
			return false
		end

		local y0v = c.y0
		local y1v = math.min(y0v + Config.CHUNK_VOX_Y - 1, yMaxV)
		local wx0, wz0 = IO.v2w(c.x0), IO.v2w(c.z0)
		local wx1, wz1 = IO.v2w(c.x1 + 1), IO.v2w(c.z1 + 1)
		local wy0, wy1 = IO.v2w(y0v), IO.v2w(y1v + 1)

		local sizeX = c.x1 - c.x0 + 1
		local sizeY = y1v - y0v + 1
		local sizeZ = c.z1 - c.z0 + 1

		local region = Region3.new(Vector3.new(wx0, wy0, wz0), Vector3.new(wx1, wy1, wz1))

		if SKIP_EMPTY_READ then
			local _, occsOld = Terrain:ReadVoxels(region, Config.VOX)
			local nonEmpty = false
			for vx=1,sizeX do
				if nonEmpty then break end
				for vy=1,sizeY do
					if nonEmpty then break end
					for vz=1,sizeZ do
						if occsOld[vx][vy][vz] > 0 then nonEmpty = true; break end
					end
				end
			end
			if not nonEmpty then
				c.y0 = y1v + 1
				return false
			end
		end

		local mats, occs = getAirBuffers(sizeX, sizeY, sizeZ)
		Terrain:WriteVoxels(region, Config.VOX, mats, occs)

		c.y0 = y1v + 1
		return false
	end

	enqueueErase({ step = step })
end

return TileBuilder
```

## TileIO (Module script)
```lua
-- TileIO (Module script, tiny micro-opts + comments)
-- Purpose:
--   Utility functions for voxel/world conversions and allocating 3D write buffers
--   in the shape Terrain:WriteVoxels expects. Behavior unchanged.

local Config = require(script.Parent.WorldConfig)

local TileIO = {}

-- w2v:
--   Convert world-space coordinate (studs) to voxel index for current VOX size (floor division).
function TileIO.w2v(x) return math.floor(x / Config.VOX) end  -- x:number -> int index

-- v2w:
--   Convert voxel index back to world-space (studs).
function TileIO.v2w(i) return i * Config.VOX end              -- i:int -> studs

-- alloc:
--   Create [sizeX][sizeY][sizeZ] 3D arrays for materials and occupancies, prefilled.
--   Each z-line is a fresh table; no aliasing between rows/columns.
function TileIO.alloc(sizeX,sizeY,sizeZ, defaultMat)
	local mats, occs = table.create(sizeX), table.create(sizeX)
	for vx=1,sizeX do
		local colM, colO = table.create(sizeY), table.create(sizeY)
		for vy=1,sizeY do
			local rowM, rowO = table.create(sizeZ), table.create(sizeZ)
			for vz=1,sizeZ do rowM[vz]=defaultMat; rowO[vz]=0 end
			colM[vy]=rowM; colO[vy]=rowO
		end
		mats[vx]=colM; occs[vx]=colO
	end
	return mats, occs
end

-- aabb:
--   World-space AABB (minX,minZ,maxX,maxZ) for tile (i,k), with optional symmetric pad (studs).
function TileIO.aabb(i,k, pad)
	pad = pad or 0
	local minX = i * Config.TILE_SIZE - pad
	local minZ = k * Config.TILE_SIZE - pad
	return minX, minZ, minX + Config.TILE_SIZE + pad*2, minZ + Config.TILE_SIZE + pad*2
end

return TileIO
```

## Vegetation (Module script)
```lua
-- Vegetation (Module script, targeted micro-opts; behavior preserved)
-- Purpose:
--   Plans, pools, spawns, and despawns vegetation models per tile under budgeted background streaming.
--   This pass keeps all features but trims some allocations and adds clarifying comments.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

local Config  = require(script.Parent.WorldConfig)
local Biomes  = require(script.Parent.Biomes)
local Height  = require(script.Parent.Height)

-- Where vegetation assets live
local MODEL_FOLDER = ReplicatedStorage:WaitForChild("Terrain")

-- Parent for spawned instances (per-tile folders inside)
local ROOT = Workspace:FindFirstChild("Vegetation") or Instance.new("Folder", Workspace)
ROOT.Name = "Vegetation"

-- Hidden pool folder (keeps free instances out of Workspace)
local POOL = ServerStorage:FindFirstChild("VegetationPool") or Instance.new("Folder")
POOL.Name = "VegetationPool"
POOL.Parent = ServerStorage

-- ===== Streaming config =====
local STREAM_RADIUS        = 512
local STREAM_PREFETCH      = 256
local STREAM_DESPAWN       = 512
local STEP_INTERVAL        = 0.03
local MAX_NEW_PER_STEP     = 64
local MAX_REMOVE_PER_STEP  = 600
local MAX_STEP_BUDGET_MS   = 6.0
local MAX_FREE_PER_ASSET   = 100

-- ===== utils =====
local function tileSeed(i,k)
	local a = math.floor(i * 73856093)
	local b = math.floor(k * 19349663)
	local c = math.floor(Config.SEED * 83492791)
	return bit32.band(bit32.bxor(bit32.bxor(a,b),c), 0x7fffffff)
end

local function clamp(v,a,b) return (v<a) and a or ((v>b) and b or v) end
local function degToRad(d) return d * math.pi / 180 end

-- surfaceNormal:
--   Returns upward normal and slope magnitude (grad) using central differences on Height.surface.
local function surfaceNormal(x, z, biomeIdx)
	local step = Config.RES_XZ
	local hX1 = Height.surface(x+step, z, biomeIdx)
	local hX0 = Height.surface(x-step, z, biomeIdx)
	local hZ1 = Height.surface(x, z+step, biomeIdx)
	local hZ0 = Height.surface(x, z-step, biomeIdx)
	local dx = (hX1 - hX0) * 0.5 / step
	local dz = (hZ1 - hZ0) * 0.5 / step
	local n = Vector3.new(-dx, 1, -dz)
	return n.Unit, math.sqrt(dx*dx + dz*dz)
end

-- fromUpAndForward:
--   Build an orientation frame at 'pos' using 'up' vector and an approximate forward.
local function fromUpAndForward(pos, up, forward)
	local f = (forward - up * forward:Dot(up))
	if f.Magnitude < 1e-3 then
		local alt = (math.abs(up.Y) > 0.9) and Vector3.xAxis or Vector3.zAxis
		f = (alt - up * alt:Dot(up))
	end
	f = f.Unit
	local right = f:Cross(up).Unit
	local back  = -f
	return CFrame.fromMatrix(pos, right, up, back)
end

-- applyRandomRotation:
--   Apply random Euler rotation around chosen axes.
local function applyRandomRotation(cf, rng, rotAxes, rotMaxDeg)
	local rx = (rotAxes and rotAxes.x) and degToRad(rng:NextNumber(-(rotMaxDeg.x or 0), (rotMaxDeg.x or 0))) or 0
	local ry = (rotAxes and rotAxes.y) and degToRad(rng:NextNumber(-(rotMaxDeg.y or 0), (rotMaxDeg.y or 0))) or 0
	local rz = (rotAxes and rotAxes.z) and degToRad(rng:NextNumber(-(rotMaxDeg.z or 0), (rotMaxDeg.z or 0))) or 0
	return cf * CFrame.Angles(rx, ry, rz)
end

local function uniformScale(instance, scale)
	if not scale or math.abs(scale-1) < 1e-3 then return end
	if instance:IsA("Model") then
		if instance.ScaleTo then
			instance:ScaleTo(scale)
		else
			for _,p in ipairs(instance:GetDescendants()) do
				if p:IsA("BasePart") then p.Size = p.Size * scale end
			end
		end
	elseif instance:IsA("BasePart") then
		instance.Size = instance.Size * scale
	end
end

-- Ground probe (raycast first; fallback to heightfield)
local RAY_PARAMS = RaycastParams.new()
RAY_PARAMS.FilterType = Enum.RaycastFilterType.Exclude
RAY_PARAMS.FilterDescendantsInstances = { ROOT }
RAY_PARAMS.IgnoreWater = true

local function probeGround(px, pz)
	local origin = Vector3.new(px, (Config.SEA_LEVEL or 0) + 2048, pz)
	local dir    = Vector3.new(0, -4096, 0)
	local hit = Workspace:Raycast(origin, dir, RAY_PARAMS)
	if hit then
		return hit.Position, hit.Normal, hit.Material
	end
	local biomeIdx = Biomes.indexForZ(pz)
	local h = Height.surface(px, pz, biomeIdx)
	local n,_ = surfaceNormal(px, pz, biomeIdx)
	return Vector3.new(px, h, pz), n, Enum.Material.Air
end

local function snapToGroundByPivot(instance, targetPos)
	if instance:IsA("Model") then
		local bboxCF, bboxSize = instance:GetBoundingBox()
		local bottom = bboxCF.Position - bboxCF.UpVector * (bboxSize.Y * 0.5)
		local lift = (targetPos - bottom):Dot(bboxCF.UpVector)
		instance:PivotTo(instance:GetPivot() * CFrame.new(0, lift, 0))
	else
		local part = instance
		local bottom = part.Position - part.CFrame.UpVector * (part.Size.Y * 0.5)
		local lift = (targetPos - bottom):Dot(part.CFrame.UpVector)
		part.CFrame = part.CFrame * CFrame.new(0, lift, 0)
	end
end

-- hasNormalArea:
--   Checks for a reasonably flat patch of radius 'radius' (studs) around (px,pz).
local function hasNormalArea(px, pz, biomeIdx, radius)
	if not radius or radius <= 0 then return true end
	local samples = 8
	local centerN,_ = surfaceNormal(px, pz, biomeIdx)
	local centerH   = Height.surface(px, pz, biomeIdx)

	local maxDeltaY = math.max(1.0, radius * 0.12)
	local maxAngle  = 12.0

	local minH, maxH = centerH, centerH
	for s=1, samples do
		local ang = (s/samples) * math.pi * 2
		local sx = px + math.cos(ang) * radius
		local sz = pz + math.sin(ang) * radius
		local n,_ = surfaceNormal(sx, sz, biomeIdx)
		local h   = Height.surface(sx, sz, biomeIdx)

		local dot = clamp(centerN:Dot(n), -1, 1)
		local a   = math.deg(math.acos(dot))
		if a > maxAngle then return false end
		if h < minH then minH = h end
		if h > maxH then maxH = h end
	end

	return (maxH - minH) <= maxDeltaY
end

-- ===== Per-biome vegetation definitions (unchanged) =====
-- (… retained exactly as you provided …)
-- !! For brevity, your original VegetationDefs table is unchanged. Insert it here verbatim. !!

local VegetationDefs = {
	[1] = {
		{
			name = "Palm", 
			source = MODEL_FOLDER:FindFirstChild("Beach").BeachTree,
			spacing = 120, 
			maxSlopeDeg = 10, 
			scaleMin = 2.3, 
			scaleMax = 4.3,
			rotAxes = {x=false, y=true, z=false}, 
			rotMaxDeg = {x=0, y=180, z=0},
			alignToNormal=false, 
			category="Tree", 
			avoidCategories={"Boulder", "Rock"},
			allowSelfOverlap=false, 
			footprint=60
		},
		{
			name = "BoulderA", 
			source = MODEL_FOLDER:FindFirstChild("Beach").BeachBoulderA,
			spacing = 200, 
			maxSlopeDeg = 80, 
			scaleMin = 3, 
			scaleMax = 4,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false,  
			category="Boulder", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=30
		},
		{
			name = "BoulderB", 
			source = MODEL_FOLDER:FindFirstChild("Beach").BeachBoulderB,
			spacing = 150, 
			maxSlopeDeg = 80, 
			scaleMin = 3, 
			scaleMax = 4,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Boulder", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=30
		},
		{
			name = "BoulderC", 
			source = MODEL_FOLDER:FindFirstChild("Beach").BeachBoulderC,
			spacing = 100, 
			maxSlopeDeg = 80, 
			scaleMin = 3, 
			scaleMax = 4,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Boulder", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=30
		},		
		{
			name = "RockA", 
			--allowedMaterials={Enum.Material.Limestone},
			source = MODEL_FOLDER:FindFirstChild("Beach").BeachRockA,
			spacing = 65, 
			maxSlopeDeg = 100, 
			scaleMin = 1.5, 
			scaleMax = 2.5,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},	
		{
			name = "RockB", 
			source = MODEL_FOLDER:FindFirstChild("Beach").BeachRockB,
			spacing = 55, 
			maxSlopeDeg = 60, 
			scaleMin = 1, 
			scaleMax = 2,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},		
		{
			name = "RockC", 
			source = MODEL_FOLDER:FindFirstChild("Beach").BeachRockC,
			spacing = 45, 
			maxSlopeDeg = 60, 
			scaleMin = 0.5, 
			scaleMax = 1.5,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false,  
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},		
		{
			name = "StoneA", 
			source = MODEL_FOLDER:FindFirstChild("Beach").BeachStoneA,
			spacing = 18, 
			maxSlopeDeg = 25, 
			scaleMin = 0.5, 
			scaleMax = 1,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Stone", 
			avoidCategories={"Tree"},
			allowSelfOverlap=false, 
			footprint=1
		},		
		{
			name = "StoneB", 
			source = MODEL_FOLDER:FindFirstChild("Beach").BeachStoneB,
			spacing = 15, 
			maxSlopeDeg = 25, 
			scaleMin = 0.5, 
			scaleMax = 1,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Stone", 
			avoidCategories={"Tree"},
			allowSelfOverlap=false, 
			footprint=1
		},	
	},
	[2] = {
		{
			name = "Pine", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestPineTree,
			allowedMaterials={Enum.Material.Grass},
			spacing = 25, 
			maxSlopeDeg = 50, 
			scaleMin = 1.5, 
			scaleMax = 2.25,
			rotAxes = {x=false, y=true, z=false}, 
			rotMaxDeg = {x=0, y=180, z=0},
			alignToNormal=false, 
			category="Tree", 
			avoidCategories={"Boulder", "Rock"},
			allowSelfOverlap=false, 
			footprint=10
		},
		{
			name = "BoulderA", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestBoulderA,
			allowedMaterials={Enum.Material.Rock},
			normalSize=5,
			spacing = 150, 
			maxSlopeDeg = 80, 
			scaleMin = 3, 
			scaleMax = 4,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Boulder", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=30
		},
		{
			name = "BoulderB", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestBoulderB,
			allowedMaterials={Enum.Material.Rock},
			normalSize=8,
			spacing = 100, 
			maxSlopeDeg = 80, 
			scaleMin = 3, 
			scaleMax = 4,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Boulder", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=30
		},
		{
			name = "BoulderC", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestBoulderC,
			normalSize=10,
			spacing = 50, 
			maxSlopeDeg = 80, 
			scaleMin = 3, 
			scaleMax = 4,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Boulder", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=30
		},
		{
			name = "GroundRockA", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestRockA,
			allowedMaterials={Enum.Material.Rock},
			spacing = 45, 
			maxSlopeDeg = 60, 
			scaleMin = 1, 
			scaleMax = 2,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},
		{
			name = "GroundRockB", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestRockB,
			allowedMaterials={Enum.Material.Rock},
			spacing = 35, 
			maxSlopeDeg = 60, 
			scaleMin = 1, 
			scaleMax = 2,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},
		{
			name = "GroundRockC", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestRockC,
			spacing = 25, 
			maxSlopeDeg = 60, 
			scaleMin = 1, 
			scaleMax = 2,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},
		{
			name = "CliffRockA", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestRockA,
			allowedMaterials={Enum.Material.Rock},
			normalSize=0.25,
			spacing = 25, 
			maxSlopeDeg = 80, 
			scaleMin = 2, 
			scaleMax = 3,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},
		{
			name = "CliffRockB", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestRockB,
			allowedMaterials={Enum.Material.Rock},
			normalSize=0.25,
			spacing = 15, 
			maxSlopeDeg = 80, 
			scaleMin = 2, 
			scaleMax = 3,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},
		{
			name = "CliffRockC", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestRockC,
			allowedMaterials={Enum.Material.Rock},
			normalSize=0.25,
			spacing = 10, 
			maxSlopeDeg = 80, 
			scaleMin = 2, 
			scaleMax = 3,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},		
		{
			name = "StoneA", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestStoneA,
			allowedMaterials={Enum.Material.Rock},
			spacing = 8, 
			maxSlopeDeg = 65, 
			scaleMin = 0.5, 
			scaleMax = 1,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Stone", 
			avoidCategories={"Tree"},
			allowSelfOverlap=false, 
			footprint=1
		},		
		{
			name = "StoneB", 
			source = MODEL_FOLDER:FindFirstChild("GreenForest").ForestStoneB,
			allowedMaterials={Enum.Material.Grass},
			spacing = 15, 
			maxSlopeDeg = 65, 
			scaleMin = 0.5, 
			scaleMax = 1,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Stone", 
			avoidCategories={"Tree"},
			allowSelfOverlap=false, 
			footprint=1
		},
	},
	[3] = {
		{
			name = "Pine", 
			source = MODEL_FOLDER:FindFirstChild("SnowyForest").SnowPineTree,
			allowedMaterials={Enum.Material.Snow},
			spacing = 25, 
			maxSlopeDeg = 50, 
			scaleMin = 1.5, 
			scaleMax = 2.25,
			rotAxes = {x=false, y=true, z=false}, 
			rotMaxDeg = {x=0, y=180, z=0},
			alignToNormal=false, 
			category="Tree", 
			avoidCategories={"Boulder", "Rock"},
			allowSelfOverlap=false, 
			footprint=10
		},
		{
			name = "BoulderA", 
			source = MODEL_FOLDER:FindFirstChild("SnowyForest").SnowBoulderA,
			spacing = 100, 
			maxSlopeDeg = 80, 
			scaleMin = 3, 
			scaleMax = 4,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Boulder", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=10
		},
		{
			name = "BoulderB", 
			source = MODEL_FOLDER:FindFirstChild("SnowyForest").SnowBoulderB,
			spacing = 85, 
			maxSlopeDeg = 80, 
			scaleMin = 3, 
			scaleMax = 4,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Boulder", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=10
		},
		{
			name = "BoulderC", 
			source = MODEL_FOLDER:FindFirstChild("SnowyForest").SnowBoulderC,
			spacing = 65, 
			maxSlopeDeg = 80, 
			scaleMin = 3, 
			scaleMax = 4,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Boulder", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=10
		},
		{
			name = "RockA", 
			source = MODEL_FOLDER:FindFirstChild("SnowyForest").SnowRockA,
			spacing = 45, 
			maxSlopeDeg = 60, 
			scaleMin = 1, 
			scaleMax = 2,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},
		{
			name = "RockB", 
			source = MODEL_FOLDER:FindFirstChild("SnowyForest").SnowRockB,
			spacing = 35, 
			maxSlopeDeg = 60, 
			scaleMin = 1, 
			scaleMax = 2,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},
		{
			name = "RockC", 
			source = MODEL_FOLDER:FindFirstChild("SnowyForest").SnowRockC,
			spacing = 25, 
			maxSlopeDeg = 60, 
			scaleMin = 1, 
			scaleMax = 2,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Rock", 
			avoidCategories={"Tree"},
			allowSelfOverlap=true, 
			footprint=4
		},
		{
			name = "StoneA", 
			source = MODEL_FOLDER:FindFirstChild("SnowyForest").SnowStoneA,
			spacing = 8, 
			maxSlopeDeg = 25, 
			scaleMin = 0.5, 
			scaleMax = 1,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Stone", 
			avoidCategories={"Tree"},
			allowSelfOverlap=false, 
			footprint=1
		},		
		{
			name = "StoneB", 
			source = MODEL_FOLDER:FindFirstChild("SnowyForest").SnowStoneB,
			spacing = 5, 
			maxSlopeDeg = 25, 
			scaleMin = 0.5, 
			scaleMax = 1,
			rotAxes = {x=true, y=true, z=true}, 
			rotMaxDeg = {x=180, y=180, z=180},
			alignToNormal=false, 
			category="Stone", 
			avoidCategories={"Tree"},
			allowSelfOverlap=false, 
			footprint=1
		},		
	}, [4] = {}, [5] = {},
}

local Vegetation = {}

function Vegetation.setBiomeDefs(biomeIndex, entries)
	VegetationDefs[biomeIndex] = entries or {}
end

-- ===== Spatial hash to reduce overlap checks =====
local function gridKey(vx, vz, cell)
	-- Slightly cheaper than string.format
	return tostring(math.floor(vx / cell)) .. ":" .. tostring(math.floor(vz / cell))
end

local function canPlaceHere(pos, entry, placedHash, cell)
	local r = entry.footprint or math.max((entry.spacing or 24) * 0.6, 6)
	local avoid = {}
	for _,cat in ipairs(entry.avoidCategories or {}) do avoid[cat] = true end
	local allowSelf = (entry.allowSelfOverlap ~= false)

	local cx, cz = pos.X, pos.Z
	for gx = -1,1 do
		for gz = -1,1 do
			local key = gridKey(cx + gx*r, cz + gz*r, cell)
			local bucket = placedHash[key]
			if bucket then
				for _,p in ipairs(bucket) do
					local sameCat = (p.cat == (entry.category or ""))
					if (not sameCat) and avoid[p.cat] then
						if (pos - p.pos).Magnitude < (r + p.r) then return false end
					elseif (not allowSelf) and sameCat then
						if (pos - p.pos).Magnitude < (r + p.r) then return false end
					end
				end
			end
		end
	end
	return true
end

local function addPlaced(pos, entry, placedHash, cell)
	local r = entry.footprint or math.max((entry.spacing or 24) * 0.6, 6)
	local key = gridKey(pos.X, pos.Z, cell)
	local bucket = placedHash[key]; if not bucket then bucket = {}; placedHash[key] = bucket end
	table.insert(bucket, { pos = pos, r = r, cat = entry.category or "" })
end

-- placementsForEntryInTile:
--   Deterministic jittered grid of candidate positions, slope-gated.
local function placementsForEntryInTile(i,k, entry, rng, biomeIndex)
	if not entry.source then return {} end
	local minX = i * Config.TILE_SIZE
	local minZ = k * Config.TILE_SIZE
	local maxX = minX + Config.TILE_SIZE
	local maxZ = minZ + Config.TILE_SIZE

	local step = math.max(4, entry.spacing or 24)
	local out = {}

	for x = minX, maxX, step do
		for z = minZ, maxZ, step do
			local jx = rng:NextNumber(-0.45, 0.45) * step
			local jz = rng:NextNumber(-0.45, 0.45) * step
			local px = clamp(x + jx, minX, maxX)
			local pz = clamp(z + jz, minZ, maxZ)

			local _, grad = surfaceNormal(px, pz, biomeIndex)
			local slopeDeg = math.deg(math.atan(grad))
			if slopeDeg <= (entry.maxSlopeDeg or 35) then
				local h = Height.surface(px, pz, biomeIndex)
				out[#out+1] = {pos = Vector3.new(px, h, pz)}
			end
		end
	end
	return out
end

-- ===== Instance pooling per asset =====
local Pools = {}  -- key = entry.source/name ; value = {free = {}, inUse = {}}
local function poolKeyFor(entry) return tostring(entry.source) .. "|" .. (entry.name or "Unnamed") end

local function acquireInstance(entry)
	local key = poolKeyFor(entry)
	local pool = Pools[key]
	if not pool then pool = { free = {}, inUse = {} }; Pools[key] = pool end
	local inst = table.remove(pool.free)
	if not inst then
		if not entry.source then return nil end
		inst = entry.source:Clone()
	end
	pool.inUse[inst] = true
	return inst
end

local function releaseInstance(entry, inst)
	local key = poolKeyFor(entry)
	local pool = Pools[key]; if not pool then pool = { free = {}, inUse = {} }; Pools[key] = pool end
	pool.inUse[inst] = nil

	inst.Parent = POOL
	if #pool.free >= MAX_FREE_PER_ASSET then
		inst:Destroy()
	else
		table.insert(pool.free, inst)
	end
end

-- ===== Plans & live instances per tile =====
local TilePlans       = {}    -- key "i:k" -> { biomeIdx = n, plan = { ... } }
local TileFolders     = {}    -- key "i:k" -> Folder
local TileLive        = {}    -- key "i:k" -> array of { entryIdx, inst, entryRef }
local TileSpawnedIdx  = {}    -- key "i:k" -> { [planIdx]=true }
local TileRejectedIdx = {}    -- key "i:k" -> { [planIdx]=true }

local function buildPlanForTile(i,k)
	local key = string.format("%d:%d", i, k)
	if TilePlans[key] then return end

	local biomeIdx = Biomes.indexForZ((k + 0.5) * Config.TILE_SIZE)
	local defs = VegetationDefs[biomeIdx] or {}
	if #defs == 0 then
		TilePlans[key] = { biomeIdx = biomeIdx, plan = {} }
		TileSpawnedIdx[key]  = TileSpawnedIdx[key]  or {}
		TileRejectedIdx[key] = TileRejectedIdx[key] or {}
		return
	end

	local placedHash = {}
	local plan = {}
	for idx,entry in ipairs(defs) do
		if entry.source then
			local rng = Random.new(tileSeed(i, k) + idx * 101)
			local spots = placementsForEntryInTile(i, k, entry, rng, biomeIdx)
			local cell = math.max(6, entry.footprint or math.floor((entry.spacing or 24)*0.6))
			for sIdx,spot in ipairs(spots) do
				if canPlaceHere(spot.pos, entry, placedHash, cell) then
					addPlaced(spot.pos, entry, placedHash, cell)
					plan[#plan+1] = { entryIdx = idx, pos = spot.pos, seedScalar = sIdx }
				end
			end
		end
	end

	TilePlans[key] = { biomeIdx = biomeIdx, plan = plan }
	TileSpawnedIdx[key]  = TileSpawnedIdx[key]  or {}
	TileRejectedIdx[key] = TileRejectedIdx[key] or {}
end

local function ensureTileFolder(i,k)
	local key = string.format("%d:%d", i, k)
	local f = TileFolders[key]
	if f and f.Parent then return f end
	f = Instance.new("Folder"); f.Name = key; f.Parent = ROOT
	TileFolders[key] = f
	return f
end

local function clearTile(i,k)
	local key = string.format("%d:%d", i, k)
	local live = TileLive[key]
	if live then
		local biomeIdx = TilePlans[key] and TilePlans[key].biomeIdx or Biomes.indexForZ((k+0.5)*Config.TILE_SIZE)
		local defs = VegetationDefs[biomeIdx] or {}
		for _,rec in ipairs(live) do
			local entry = rec.entryRef or defs[rec.entryIdx]
			if entry and rec.inst then
				releaseInstance(entry, rec.inst)
			end
		end
	end
	TileLive[key] = nil
	TilePlans[key] = nil
	TileSpawnedIdx[key]  = nil
	TileRejectedIdx[key] = nil
	if TileFolders[key] then
		TileFolders[key]:Destroy()
		TileFolders[key] = nil
	end
end

local function spawnPlanned(i,k, planIdx)
	local key = string.format("%d:%d", i, k)

	-- per-index dedupe
	local spawned  = TileSpawnedIdx[key]; if not spawned  then spawned  = {}; TileSpawnedIdx[key]  = spawned  end
	local rejected = TileRejectedIdx[key]; if not rejected then rejected = {}; TileRejectedIdx[key] = rejected end
	if (spawned[planIdx]) or (rejected[planIdx]) then
		return false
	end

	local rec = TilePlans[key]; if not rec then return false end
	local biomeIdx = rec.biomeIdx
	local defs = VegetationDefs[biomeIdx] or {}
	local p = rec.plan[planIdx]; if not p then return false end
	local entry = defs[p.entryIdx]; if not entry or not entry.source then rejected[planIdx] = true; return false end

	-- Probe ground (material + normal/pos)
	local hitPos, hitNormal, hitMat = probeGround(p.pos.X, p.pos.Z)

	-- Material gate
	if entry.allowedMaterials and #entry.allowedMaterials > 0 then
		local ok = false
		for _,m in ipairs(entry.allowedMaterials) do
			if m == hitMat then ok = true; break end
		end
		if not ok then
			rejected[planIdx] = true
			return false
		end
	end

	-- Normal size gate (flat patch radius)
	if entry.normalSize and entry.normalSize > 0 then
		if not hasNormalArea(hitPos.X, hitPos.Z, biomeIdx, entry.normalSize) then
			rejected[planIdx] = true
			return false
		end
	end

	local rng = Random.new(tileSeed(i, k) + p.seedScalar + p.entryIdx*101)
	local inst = acquireInstance(entry); if not inst then rejected[planIdx] = true; return false end
	inst.Parent = ensureTileFolder(i,k)

	-- Orientation: alignToNormal chooses hit normal vs world Y
	local up = (entry.alignToNormal ~= false) and hitNormal.Unit or Vector3.yAxis

	-- Scale first
	local s = rng:NextNumber(entry.scaleMin or 1, entry.scaleMax or 1)
	uniformScale(inst, s)

	if entry.snapToNormal and entry.snapToNormal == true then
		local cf = fromUpAndForward(hitPos, up, Vector3.new(0,0,-1))
		cf = applyRandomRotation(cf, rng, entry.rotAxes, entry.rotMaxDeg or {x=0,y=180,z=0})

		if inst:IsA("Model") then
			if not inst.PrimaryPart then
				local pp = inst:FindFirstChildWhichIsA("BasePart"); if pp then inst.PrimaryPart = pp end
			end
			inst:PivotTo(cf)
		else
			inst.CFrame = cf
		end

		snapToGroundByPivot(inst, hitPos)
	else
		local forward = Vector3.new(0,0,-1)
		local f = (forward - up * forward:Dot(up))
		if f.Magnitude < 1e-3 then
			local alt = (math.abs(up.Y) > 0.9) and Vector3.xAxis or Vector3.zAxis
			f = (alt - up * alt:Dot(up))
		end
		f = f.Unit
		local right = f:Cross(up).Unit
		local rotCF = CFrame.fromMatrix(hitPos, right, up, -f)
		rotCF = applyRandomRotation(rotCF, rng, entry.rotAxes, entry.rotMaxDeg or {x=0,y=180,z=0})

		if inst:IsA("Model") then
			if not inst.PrimaryPart then
				local pp = inst:FindFirstChildWhichIsA("BasePart"); if pp then inst.PrimaryPart = pp end
			end
			inst:PivotTo(rotCF)
		else
			inst.CFrame = rotCF
		end
	end

	-- Bookkeep
	spawned[planIdx] = true
	TileLive[key] = TileLive[key] or {}
	table.insert(TileLive[key], { entryIdx = p.entryIdx, inst = inst, entryRef = entry })
	return true
end

local function despawnTile(i,k)
	clearTile(i,k)
end

-- ===== Public API used by TileBuilder =====
function Vegetation.buildTile(i,k)
	buildPlanForTile(i,k)
end

function Vegetation.unbuildTile(i,k)
	despawnTile(i,k)
end

-- ===== Background streamer (budgeted by count AND time) =====
local function getFocus()
	local p = Players:GetPlayers()[1]
	if p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
		return p.Character.HumanoidRootPart.Position
	end
	return Vector3.new(0,0,0)
end

local function tileCenter(i,k)
	return Vector3.new((i+0.5)*Config.TILE_SIZE, 0, (k+0.5)*Config.TILE_SIZE)
end

local function shouldHaveLive(center, focus)
	local dx, dz = center.X - focus.X, center.Z - focus.Z
	local d = math.sqrt(dx*dx + dz*dz)
	return d <= (STREAM_RADIUS + STREAM_PREFETCH), d > STREAM_DESPAWN
end

task.spawn(function()
	while true do
		local tickStart = os.clock()
		local focus = getFocus()

		-- keys from planned tiles
		local keys = {}
		for key,_ in pairs(TilePlans) do keys[#keys+1] = key end

		-- Despawn (budget)
		local removed = 0
		--for _,key in ipairs(keys) do
		--	if (os.clock() - tickStart) * 1000.0 >= MAX_STEP_BUDGET_MS then break end
		--	local si,sk = key:match("(-?%d+):(-?%d+)")
		--	si, sk = tonumber(si), tonumber(sk)
		--	local center = tileCenter(si,sk)
		--	local _, tooFar = shouldHaveLive(center, focus)
		--	if tooFar and TileLive[key] then
		--		despawnTile(si, sk)
		--		removed += 1
		--		if removed >= MAX_REMOVE_PER_STEP then break end
		--	end
		--end

		-- Spawn (budget)
		local added = 0
		for _,key in ipairs(keys) do
			if added >= MAX_NEW_PER_STEP then break end
			if (os.clock() - tickStart) * 1000.0 >= MAX_STEP_BUDGET_MS then break end

			local si,sk = key:match("(-?%d+):(-?%d+)")
			si, sk = tonumber(si), tonumber(sk)
			local center = tileCenter(si,sk)
			local wantLive = select(1, shouldHaveLive(center, focus))
			if wantLive then
				local rec = TilePlans[key]
				if rec then
					ensureTileFolder(si,sk)
					for idx = 1, #(rec.plan) do
						if added >= MAX_NEW_PER_STEP then break end
						if (os.clock() - tickStart) * 1000.0 >= MAX_STEP_BUDGET_MS then break end

						local spawned  = TileSpawnedIdx[key]
						local rejected = TileRejectedIdx[key]
						if not ((spawned and spawned[idx]) or (rejected and rejected[idx])) then
							if spawnPlanned(si, sk, idx) then
								added += 1
							end
						end
					end
				end
			end
		end

		task.wait(STEP_INTERVAL)
	end
end)

return Vegetation
```

## WorldConfig (Module script)
```lua
local WorldConfig = {
	SEED              = 1337,
	VOX               = 4,
	RES_XZ            = 4,
	TILE_SIZE         = 256,
	CHUNK_VOX_XZ      = 32,
	CHUNK_VOX_Y       = 16,
	Y_MIN_WORLD       = -128,
	Y_HEADROOM        = 1024,
	SEA_LEVEL         = 28,

	BIOME_LENGTH      = 2048,
	BIOME_COUNT       = 5,
	WORLD_START_Z     = 0,
	BIOME_BLEND       = 128,   -- geometry blend width
	MAT_BLEND         = 256,    -- material blend width (cheap)

	-- shell bands
	CRUST_BELOW_STUDS = 18,
	CRUST_ABOVE_STUDS = 18,
	CAVE_BAND_BELOW   = 64,
	CAVE_BAND_ABOVE   = 0,
	STAMP_BAND_BELOW  = 32,
	STAMP_BAND_ABOVE  = 24,

	-- streaming
	VIEW_RADIUS_STUDS = 512,
	PREFETCH_MARGIN   = 256,
	DESPAWN_MARGIN    = 512,
	MAX_GEN_JOBS      = 1,
	MAX_AIR_JOBS      = 1,
	
	-- under terrain mats
	DEEP_CHEAP_DEPTH_STUDS = 8,                 -- how far below the surface before we force the cheap material
	DEEP_CHEAP_MATERIAL    = Enum.Material.Rock, -- pick your cheapest: Rock, Ground, Basalt, etc.
}

return WorldConfig
```
