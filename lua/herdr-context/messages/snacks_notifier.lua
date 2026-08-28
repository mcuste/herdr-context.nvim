local M = {
  name = 'Snacks.notifier notifications',
}

function M.collect()
  local snacks = rawget(_G, 'Snacks')
  if type(snacks) ~= 'table' or type(snacks.notifier) ~= 'table' or type(snacks.notifier.get_history) ~= 'function' then
    return {}
  end

  local ok, history = pcall(snacks.notifier.get_history)
  if not ok or type(history) ~= 'table' then return {} end

  local notifications = {}
  for _, notification in ipairs(history) do
    if type(notification) == 'table' and type(notification.msg) == 'string' then
      table.insert(
        notifications,
        { message = notification.msg, level = notification.level, title = notification.title }
      )
    end
  end
  return notifications
end

return M
