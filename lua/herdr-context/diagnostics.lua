local M = {}

local function severity_name(severity)
  local name = vim.diagnostic.severity[severity]
  if type(name) ~= 'string' then return 'UNKNOWN' end
  return name
end

-- Agent input holds one diagnostic per line.
local function single_line(message)
  if type(message) ~= 'string' then return '' end
  local text = message:gsub('%s+', ' ')
  return vim.trim(text)
end

local function origin(item)
  local parts = {}
  if type(item.source) == 'string' and item.source ~= '' then table.insert(parts, item.source) end

  local code = item.code
  if type(code) == 'number' then code = tostring(code) end
  if type(code) == 'string' and code ~= '' then table.insert(parts, code) end

  if #parts == 0 then return '' end
  return string.format(' [%s]', table.concat(parts, ' '))
end

local function lines_of(item)
  local start_line = math.max((item.lnum or 0) + 1, 1)
  local end_line = math.max((item.end_lnum or item.lnum or 0) + 1, 1)
  -- A range that ends at column 0 stops before that line.
  if end_line > start_line and (item.end_col or 0) == 0 then end_line = end_line - 1 end
  return start_line, math.max(end_line, start_line)
end

function M.text(item)
  return string.format('%s %s%s', severity_name(item.severity), single_line(item.message), origin(item))
end

function M.collect(buf, first_line, last_line)
  local items = {}

  for _, item in ipairs(vim.diagnostic.get(buf or 0)) do
    local start_line, end_line = lines_of(item)
    local inside = first_line == nil or (start_line <= last_line and end_line >= first_line)
    if inside then
      table.insert(items, {
        start_line = start_line,
        end_line = end_line,
        severity = item.severity or 0,
        text = M.text(item),
      })
    end
  end

  table.sort(items, function(first, second)
    if first.start_line ~= second.start_line then return first.start_line < second.start_line end
    if first.severity ~= second.severity then return first.severity < second.severity end
    return first.text < second.text
  end)

  return items
end

return M
