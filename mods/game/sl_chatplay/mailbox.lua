-- ================================================================
-- sl_chatplay/mailbox.lua -- agent transport.
--
-- FILE MAILBOX (world/agent_inbox/):
--   cmd.txt      one /cp command per line (leading "#" = comment);
--                writing a new file (or appending) triggers execution.
--   out.txt      the response of the last executed command block.
--   out.log      append-only full transcript.
--   feed.log     append-only event feed (broadcasts + everything the
--                game says TO the console player).
-- Every line of cmd.txt is executed as the CONSOLE PLAYER.
--
-- HTTP (optional, sl_chatplay.http = true):
--   GET /chatplay?cmd=status          -> text/plain response
--   POST /chatplay  body = command    -> text/plain response
--   GET /chatplay?cmd=FEED            -> recent feed lines
-- ================================================================

local C = sl_chatplay
local modpath = minetest.get_modpath(C.modname)

C.mailbox_dir = minetest.get_worldpath() .. "/agent_inbox"
C.mailbox_last_mtime = 0
C.mailbox_seen = {}

local function ensure_dir()
	if not C.cfg.mailbox then return false end
	if C.mailbox_ok_dir then return true end
	if not minetest.mkdir then
		minetest.log("warning", "[sl_chatplay] minetest.mkdir unavailable; mailbox disabled")
		C.cfg.mailbox = false
		return false
	end
	local made_ok, made_err = pcall(minetest.mkdir, C.mailbox_dir)
	if not made_ok or not made_err then
		minetest.log("warning", "[sl_chatplay] cannot create agent_inbox: " .. tostring(made_err))
		C.cfg.mailbox = false
		return false
	end
	C.mailbox_ok_dir = true
	return true
end

local function read_cmd_file()
	local f = io.open(C.mailbox_dir .. "/cmd.txt", "r")
	if not f then return nil end
	local content = f:read("*a")
	f:close()
	return content
end

-- Execute one command block for the console player.
function C.mailbox_execute(content)
	local p = C.console
	if not p then
		return "No console player on station. (/cp console join)"
	end
	local lines = {}
	local count = 0
	for line in (content or ""):gmatch("[^\r\n]+") do
		local cmd = line:match("^%s*(.-)%s*$")
		if cmd ~= "" and cmd:sub(1, 1) ~= "#" then
			count = count + 1
		local results = { pcall(C.run, p, cmd) }
		local resp
		if results[1] then
			resp = results[3] or results[2] or "(ok)"
		else
			resp = "ERROR: " .. tostring(results[2])
		end
		resp = tostring(resp)
		if C.plain_text then resp = C.plain_text(resp) end
		lines[#lines + 1] = "> " .. cmd .. "\n" .. resp
		end
	end
	if count == 0 then return "(no commands)" end
	return table.concat(lines, "\n\n")
end

local function append_file(path, text)
	local f = io.open(path, "a")
	if not f then return end
	f:write(text .. "\n")
	f:close()
end

local function write_file(path, text)
	local f = io.open(path, "w")
	if not f then return end
	f:write(text)
	f:close()
end

-- Globalstep: poll cmd.txt (mtime-based), flush feed to feed.log.
local mail_accum = 0
minetest.register_globalstep(function(dtime)
	mail_accum = mail_accum + dtime
	if mail_accum < 1 then return end
	mail_accum = 0

	if C.cfg.mailbox and C.mailbox_ok ~= false then
		if ensure_dir() then
			C.mailbox_ok = true
			-- new file check: compare mtime
			local stat = io.open(C.mailbox_dir .. "/cmd.txt", "r")
			if stat then
				local mtime = stat:seek("end")
				stat:close()
				if mtime and mtime ~= C.mailbox_last_mtime then
					C.mailbox_last_mtime = mtime
					local content = read_cmd_file()
					if content and content ~= "" then
						local resp = C.mailbox_execute(content)
						write_file(C.mailbox_dir .. "/out.txt", resp)
						append_file(C.mailbox_dir .. "/out.log",
							"===== [" .. os.date("%Y-%m-%d %H:%M:%S") .. "] =====\n" .. resp)
						-- clear so mtime changes again on next write
						write_file(C.mailbox_dir .. "/cmd.txt", "")
					end
				end
			end
			-- flush unseen feed lines (seq-based: the ring buffer trims
			-- from the front, so index math is not stable)
			local last_seq = C.mailbox_seen.seq or 0
			local log_lines = {}
			for i = 1, #C.feed do
				local e = C.feed[i]
				if e and e.seq and e.seq > last_seq
						and (e.who == "ALL" or e.who == C.cfg.console_name) then
					log_lines[#log_lines + 1] = string.format("[%s] %s", os.date("%H:%M:%S", e.t), e.text)
				end
			end
			if #C.feed > 0 then
				C.mailbox_seen.seq = C.feed[#C.feed].seq or 0
			end
			if #log_lines > 0 then
				append_file(C.mailbox_dir .. "/feed.log", table.concat(log_lines, "\n"))
			end
		end
	end
end)

-- ----------------------------------------------------------------
-- HTTP API (optional)
-- ----------------------------------------------------------------
if C.cfg.http and minetest.register_http then
	local ok_http, http_err = pcall(function()
		minetest.register_http("chatplay", function(request)
			local cmd = request and request.forms and request.forms.cmd
			if request and request.method == "POST" and request.data and request.data ~= "" then
				cmd = request.data
			end
			if cmd == "FEED" then
				local lines = {}
				for i = math.max(1, #C.feed - 60), #C.feed do
					local e = C.feed[i]
					if e then lines[#lines + 1] = string.format("[%s] %s", os.date("%H:%M:%S", e.t), e.text) end
				end
				return { code = 200, data = table.concat(lines, "\n") }
			end
			if not cmd then
				return { code = 400, data = "usage: /chatplay?cmd=<command>, or POST with the command as body" }
			end
			if C.console then
				local results = { pcall(C.run, C.console, tostring(cmd)) }
				if results[1] then
					local data = results[3] or results[2] or "ok"
					if C.plain_text then data = C.plain_text(tostring(data)) end
					return { code = 200, data = data }
				end
				return { code = 500, data = "ERROR: " .. tostring(results[2]) }
			end
			return { code = 503, data = "No console player on station. (/cp console join)" }
		end)
	end)
	if not ok_http then
		minetest.log("warning", "[sl_chatplay] HTTP API unavailable: " .. tostring(http_err))
	end
end
