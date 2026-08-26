-- helpers used by the demo file
local M = {}

function M.upper(text) return text:upper() end

function M.join(list, separator) return table.concat(list, separator or ', ') end

return M
