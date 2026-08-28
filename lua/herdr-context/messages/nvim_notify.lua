local M = {
  name = 'nvim-notify notifications',
}

local function message_value(value)
  if type(value) == 'string' then return value end
  if type(value) ~= 'table' then return nil end

  local lines = {}
  for _, line in ipairs(value) do
    if type(line) == 'string' then table.insert(lines, line) end
  end
  if #lines == 0 then return nil end
  return table.concat(lines, '\n')
end

local function title_value(value)
  if type(value) == 'string' then return value end
  if type(value) ~= 'table' then return nil end

  local parts = {}
  for _, part in ipairs(value) do
    if type(part) == 'string' then table.insert(parts, part) end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ' ')
end

function M.collect()
  local notify = package.loaded.notify
  if type(notify) ~= 'table' or type(notify.history) ~= 'function' then return {} end

  local ok, history = pcall(notify.history)
  if not ok or type(history) ~= 'table' then return {} end

  local notifications = {}
  for _, record in ipairs(history) do
    if type(record) == 'table' then
      local message = message_value(record.message)
      if message ~= nil then
        table.insert(notifications, { message = message, level = record.level, title = title_value(record.title) })
      end
    end
  end
  return notifications
end

return M
