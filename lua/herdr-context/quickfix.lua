local text = require('herdr-context.text')

local M = {}

local function lines_of(item)
  local start_line = math.max(item.lnum or 0, 1)
  local end_line = math.max(item.end_lnum or 0, start_line)
  -- A range that ends at column 0 stops before that line.
  if end_line > start_line and (item.end_col or 0) == 0 then end_line = end_line - 1 end
  return start_line, math.max(end_line, start_line)
end

-- An item without a buffer is a plain text line, for example a header a plugin inserted. Neovim
-- also reports `valid = 0` for an item that names a file without a line, so the buffer decides.
local function entry_of(item)
  local buf = item.bufnr or 0
  if buf == 0 or not vim.api.nvim_buf_is_valid(buf) then return nil end

  local entry = { bufnr = buf, note = text.single_line(item.text), range = (item.lnum or 0) > 0 }
  if entry.range then
    entry.start_line, entry.end_line = lines_of(item)
  end

  return entry
end

-- Reads the items Neovim stores, never the quickfix window text, so 'errorformat' and
-- 'quickfixtextfunc' cannot change what the agent receives.
function M.collect(source)
  local items = source == 'loclist' and vim.fn.getloclist(0) or vim.fn.getqflist()
  local entries = {}
  local skipped = 0

  for _, item in ipairs(items) do
    local entry = entry_of(item)
    if entry == nil then
      skipped = skipped + 1
    else
      table.insert(entries, entry)
    end
  end

  return entries, skipped
end

return M
