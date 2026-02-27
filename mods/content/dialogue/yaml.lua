-- Minimal YAML loader supporting a subset used by our dialogue files.
-- Supports:
--   key: value (string values; quoted or bare)
--   lines: - item maps with nested key: value
--   nested sequences via key: then indented list with -
-- This is NOT a full YAML parser.

local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function unquote(s)
  if (s:sub(1,1) == '"' and s:sub(-1) == '"') or (s:sub(1,1) == "'" and s:sub(-1) == "'") then
    s = s:sub(2, -2)
  end
  -- unescape simple sequences
  s = s:gsub("\\\"", '"')
  s = s:gsub("\\n", "\n")
  return s
end

local function parse_value(v)
  v = trim(v)
  if v == "" or v == "null" or v == "~" then return nil end
  if v == "true" then return true end
  if v == "false" then return false end
  if v:match("^[-%d][%d_]*$") then
    local n = tonumber(v:gsub("_", ""))
    if n then return n end
  end
  return unquote(v)
end

local function count_indent(line)
  local n = 0
  for i = 1, #line do
    local c = line:sub(i,i)
    if c == ' ' then n = n + 1 else break end
  end
  return n
end

local function load_lines(lines)
  local i = 1
  local function peek() return lines[i] end
  local function nextl() local l = lines[i]; i = i + 1; return l end

  local function parse_block(base_indent)
    local obj = {}
    while true do
      local line = peek()
      if not line then break end
      if line:match("^%s*$") or line:match("^%s*#") then nextl() goto continue end
      local indent = count_indent(line)
      if indent < base_indent then break end
      -- trim leading spaces at base block
      line = line:sub(base_indent + 1)
      if line:sub(1,1) == '-' then
        -- sequence at this level
        local arr = {}
        while true do
          local l = peek(); if not l then break end
          if l:match("^%s*$") or l:match("^%s*#") then nextl() goto inner_continue end
          local ind = count_indent(l)
          if ind < base_indent then break end
          l = l:sub(base_indent + 1)
          if l:sub(1,1) ~= '-' then break end
          -- item
          l = trim(l:sub(2))
          if l == '' then
            -- multi-line mapping follows
            nextl()
            table.insert(arr, parse_block(base_indent + 2))
          else
            -- could be "- key: value" short form
            local k, v = l:match("^([^:]+):%s*(.*)$")
            if k then
              local item = {}
              item[trim(k)] = parse_value(v)
              nextl()
              -- consume any nested props indented further
              local nested = parse_block(base_indent + 2)
              for nk, nv in pairs(nested) do item[nk] = nv end
              table.insert(arr, item)
            else
              table.insert(arr, parse_value(l))
              nextl()
            end
          end
          ::inner_continue::
        end
        return arr
      else
        -- mapping entry
        local k, v = line:match("^([^:]+):%s*(.*)$")
        if not k then -- invalid line, skip
          nextl()
          goto continue
        end
        k = trim(k)
        if v == nil or v == '' then
          nextl()
          local child = parse_block(base_indent + 2)
          obj[k] = child
        else
          obj[k] = parse_value(v)
          nextl()
        end
      end
      ::continue::
    end
    return obj
  end

  return parse_block(0)
end

function M.load(str)
  local lines = {}
  for line in (str .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  return load_lines(lines)
end

function M.load_file(path)
  local f = io.open(path, "rb")
  if not f then error("cannot open YAML: " .. tostring(path)) end
  local s = f:read("*a")
  f:close()
  return M.load(s)
end

return M
