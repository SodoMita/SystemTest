-- ================================================================
-- sl_texgen/png.lua
-- Minimal pure-Lua PNG encoder (no bitops needed: Lua 5.1 safe).
--
-- Emits 8-bit RGBA (color type 6), filter type 0 per scanline and a
-- zlib stream built from stored (uncompressed) deflate blocks.  This
-- is the *fallback* encoder: when the engine provides
-- core.encode_png (5.13+) sl_texgen uses that instead, which produces
-- properly deflated output.  The fallback exists so the pipeline and
-- its headless tests do not depend on engine version.
--
-- Everything is deterministic: same pixels in, same bytes out.
-- ================================================================

local PNG = {}

-- 8-bit xor table (64K entries) so we never need Lua 5.2 bitops.
local xor8 = {}
do
	for a = 0, 255 do
		for b = 0, 255 do
			local x, p, q, bit = 0, a, b, 1
			for _ = 1, 8 do
				if p % 2 ~= q % 2 then x = x + bit end
				p = math.floor(p / 2)
				q = math.floor(q / 2)
				bit = bit * 2
			end
			xor8[a * 256 + b + 1] = x
		end
	end
end

local function bxor16(a, b)
	-- 16-bit xor via two 8-bit table lookups
	local al, ah = a % 256, math.floor(a / 256) % 256
	local bl, bh = b % 256, math.floor(b / 256) % 256
	return xor8[al * 256 + bl + 1] + xor8[ah * 256 + bh + 1] * 256
end

local function bxor32(a, b)
	local al, ah = a % 65536, math.floor(a / 65536) % 65536
	local bl, bh = b % 65536, math.floor(b / 65536) % 65536
	return bxor16(al, bl) + bxor16(ah, bh) * 65536
end

local crc_table
local function crc32(s)
	if not crc_table then
		crc_table = {}
		for n = 0, 255 do
			local c = n
			for _ = 1, 8 do
				if c % 2 == 1 then
					c = bxor32(math.floor(c / 2), 3988292384) -- 0xEDB88320
				else
					c = math.floor(c / 2)
				end
			end
			crc_table[n] = c
		end
	end
	local c = 4294967295 -- 0xFFFFFFFF
	for i = 1, #s do
		local b = s:byte(i)
		c = bxor32(math.floor(c / 256), crc_table[bxor16(c % 256, b)])
	end
	return bxor32(c, 4294967295)
end

local function adler32(s)
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + s:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return b * 65536 + a
end

-- exposed for tests
PNG.crc32 = crc32
PNG.adler32 = adler32

-- ----------------------------------------------------------------
-- base64 (standard alphabet, padded).  Used to build "[png:" texture
-- modifiers; falls back to the engine's core.encode_base64 when the
-- caller wires it up (see init.lua), so tests can run without it.
-- ----------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function PNG.encode_base64(data)
	local out = {}
	local n = #data
	for i = 1, n - n % 3, 3 do
		local a, b, c = data:byte(i, i + 2)
		local v = a * 65536 + b * 256 + c
		out[#out + 1] = B64:sub(math.floor(v / 262144) % 64 + 1, math.floor(v / 262144) % 64 + 1)
			.. B64:sub(math.floor(v / 4096) % 64 + 1, math.floor(v / 4096) % 64 + 1)
			.. B64:sub(math.floor(v / 64) % 64 + 1, math.floor(v / 64) % 64 + 1)
			.. B64:sub(v % 64 + 1, v % 64 + 1)
	end
	local rem = n % 3
	if rem == 1 then
		local a = data:byte(n)
		out[#out + 1] = B64:sub(math.floor(a / 4) + 1, math.floor(a / 4) + 1)
			.. B64:sub(a % 4 * 16 + 1, a % 4 * 16 + 1)
			.. "=="
	elseif rem == 2 then
		local a, b = data:byte(n - 1, n)
		local v = a * 256 + b
		out[#out + 1] = B64:sub(math.floor(v / 1024) + 1, math.floor(v / 1024) + 1)
			.. B64:sub(math.floor(v / 16) % 64 + 1, math.floor(v / 16) % 64 + 1)
			.. B64:sub(v % 16 * 4 + 1, v % 16 * 4 + 1)
			.. "="
	end
	return table.concat(out)
end

local function be32(n)
	return string.char(
		math.floor(n / 16777216) % 256,
		math.floor(n / 65536) % 256,
		math.floor(n / 256) % 256,
		n % 256)
end

local function be16(n)
	return string.char(math.floor(n / 256) % 256, n % 256)
end

local function chunk(ctype, data)
	return be32(#data) .. ctype .. data .. be32(crc32(ctype .. data))
end

-- zlib wrapper (RFC 1950) around raw stored deflate blocks (RFC 1951).
local function zlib_stored(raw)
	local parts = {"\120\001"} -- CMF 0x78, FLG 0x01 (check value valid, level 0)
	local pos, n = 1, #raw
	while pos <= n do
		local len = math.min(65535, n - pos + 1)
		local block = raw:sub(pos, pos + len - 1)
		local final = (pos + len - 1 >= n) and 1 or 0
		local nlen = bxor16(len, 65535)
		parts[#parts + 1] = string.char(final) .. be16(len) .. be16(nlen) .. block
		pos = pos + len
	end
	parts[#parts + 1] = be32(adler32(raw))
	return table.concat(parts)
end

-- canvas: { w, h, px = table of w*h*4 ints (RGBA, row-major) }
function PNG.encode(c)
	local raw_parts = {}
	for y = 0, c.h - 1 do
		local row = {}
		local base = y * c.w * 4
		for x = 0, c.w - 1 do
			local i = base + x * 4
			row[#row + 1] = string.char(
				c.px[i + 1] or 0, c.px[i + 2] or 0, c.px[i + 3] or 0, c.px[i + 4] or 0)
		end
		raw_parts[#raw_parts + 1] = "\000" .. table.concat(row) -- filter 0
	end
	local ihdr = be32(c.w) .. be32(c.h)
		.. string.char(8, 6, 0, 0, 0) -- bit depth 8, RGBA, deflate, filter 0, no interlace
	return "\137PNG\r\n\026\n"
		.. chunk("IHDR", ihdr)
		.. chunk("IDAT", zlib_stored(table.concat(raw_parts)))
		.. chunk("IEND", "")
end

return PNG
