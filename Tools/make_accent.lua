-- Makes Media/Logo/alc_mark_accent_64.tga: the part of ALC's mark that carries the accent colour (the green, lower part),
-- as white pixels with the mark's own soft edges, so a window can tint just that part with another addon's colour
-- (Soft Reserve: purple) over the all-white mark. Run from the ArbiterLootCouncil folder:  lua Tools/make_accent.lua
local SRC = "Media/Logo/alc_mark_64.tga"
local DST = "Media/Logo/alc_mark_accent_64.tga"

local function readf(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
local function writef(p, s) local f = assert(io.open(p, "wb")) f:write(s) f:close() end

-- The TGA files are uncompressed 32 bit BGRA. A pixel is "accent" when green leads clearly (as in ASR's make_mark).
local data = readf(SRC)
local idlen = data:byte(1)
local w, h = data:byte(13) + data:byte(14) * 256, data:byte(15) + data:byte(16) * 256
assert(data:byte(3) == 2 and data:byte(17) == 32, "expected an uncompressed 32 bit TGA")
local off = 18 + idlen
local out = { data:sub(1, off) }
local kept = 0
for p = 0, w * h - 1 do
	local i = off + p * 4 + 1
	local b, g, r, a = data:byte(i, i + 3)
	if a > 0 and g - r > 25 and g - b > 15 then
		out[#out + 1] = string.char(255, 255, 255, a)
		kept = kept + 1
	else
		out[#out + 1] = string.char(255, 255, 255, 0)
	end
end
out[#out + 1] = data:sub(off + w * h * 4 + 1)
writef(DST, table.concat(out))
print(string.format("made %s: %d of %d pixels carry the accent", DST, kept, w * h))
