-- Generates the rounded-rectangle textures the windows are drawn with (Media/Shapes).
-- Run from the addon folder:  lua Tools/make_shapes.lua
--
-- For every corner radius there is a filled shape and a ring (a border) of 1 and 2 px.
-- Each is a 32x32 white 32-bit TGA whose alpha is the anti-aliased shape. The addon cuts
-- it into nine pieces (UI.NewFill / UI.AddBorder), keeping the corners crisp at any size,
-- and tints it with vertex colours. Not shipped in the game folder's load path: only the
-- generated files in Media/Shapes are used.

local SIZE = 32
local SAMPLES = 4 -- 4x4 subsamples per pixel
local RADII = { 4, 6, 8, 10 }
local THICKNESS = { 1, 2 }

-- Signed distance from (x, y) to a rounded rectangle spanning [lo, hi] on both axes with
-- corner radius r. Negative inside.
local function distance(x, y, lo, hi, r)
	local cx, cy = (lo + hi) / 2, (lo + hi) / 2
	local half = (hi - lo) / 2
	local qx = math.abs(x - cx) - (half - r)
	local qy = math.abs(y - cy) - (half - r)
	local ox, oy = math.max(qx, 0), math.max(qy, 0)
	return math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0) - r
end

-- Fraction of a pixel covered by the shape: the outer rounded rectangle minus, for a
-- ring, the inner one inset by `thickness`.
local function coverage(px, py, radius, thickness)
	local hits = 0
	for sy = 0, SAMPLES - 1 do
		for sx = 0, SAMPLES - 1 do
			local x = px + (sx + 0.5) / SAMPLES
			local y = py + (sy + 0.5) / SAMPLES
			local inside = distance(x, y, 0, SIZE, radius) <= 0
			if inside and thickness then
				local inner = distance(x, y, thickness, SIZE - thickness, math.max(radius - thickness, 0)) <= 0
				if inner then inside = false end
			end
			if inside then hits = hits + 1 end
		end
	end
	return hits / (SAMPLES * SAMPLES)
end

local function writeTga(path, radius, thickness)
	local header = string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, SIZE % 256, math.floor(SIZE / 256),
		SIZE % 256, math.floor(SIZE / 256), 32, 8) -- 32 bit, 8 alpha bits, origin bottom left
	local rows = {}
	for row = SIZE - 1, 0, -1 do -- TGA stores the bottom row first
		local pixels = {}
		for col = 0, SIZE - 1 do
			local alpha = math.floor(coverage(col, row, radius, thickness) * 255 + 0.5)
			pixels[#pixels + 1] = string.char(255, 255, 255, alpha) -- B, G, R, A
		end
		rows[#rows + 1] = table.concat(pixels)
	end
	local file = assert(io.open(path, "wb"))
	file:write(header, table.concat(rows))
	file:close()
end

local folder = "Media/Shapes/"
local count = 0
for _, radius in ipairs(RADII) do
	writeTga(string.format("%sfill_r%d.tga", folder, radius), radius, nil)
	count = count + 1
	for _, thickness in ipairs(THICKNESS) do
		writeTga(string.format("%sring_r%d_t%d.tga", folder, radius, thickness), radius, thickness)
		count = count + 1
	end
end
print(string.format("wrote %d shapes to %s", count, folder))
