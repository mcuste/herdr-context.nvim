local M = {
  name = 'noice.nvim notifications',
}

function M.collect()
  local manager = package.loaded['noice.message.manager']
  if type(manager) ~= 'table' or type(manager.get) ~= 'function' then return {} end

  local ok, history = pcall(manager.get, { event = 'notify' }, { history = true, sort = true })
  if not ok or type(history) ~= 'table' then return {} end

  local notifications = {}
  for _, record in ipairs(history) do
    if type(record) == 'table' and type(record.content) == 'function' then
      local content_ok, content = pcall(record.content, record)
      if content_ok and type(content) == 'string' then
        table.insert(notifications, { message = content, level = record.level, title = record.title })
      end
    end
  end
  return notifications
end

return M
