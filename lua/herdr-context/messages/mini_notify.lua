local M = {
  name = 'mini.notify notifications',
}

function M.collect()
  local mini_notify = rawget(_G, 'MiniNotify')
  if type(mini_notify) ~= 'table' or type(mini_notify.get_all) ~= 'function' then return {} end

  local ok, history = pcall(mini_notify.get_all)
  if not ok or type(history) ~= 'table' then return {} end

  local records = {}
  for index, notification in pairs(history) do
    if type(notification) == 'table' and type(notification.msg) == 'string' then
      table.insert(records, { index = index, notification = notification })
    end
  end
  table.sort(records, function(left, right)
    local left_time = tonumber(left.notification.ts_update) or 0
    local right_time = tonumber(right.notification.ts_update) or 0
    if left_time ~= right_time then return left_time < right_time end
    return (tonumber(left.index) or 0) < (tonumber(right.index) or 0)
  end)

  local notifications = {}
  for _, record in ipairs(records) do
    local notification = record.notification
    table.insert(notifications, { message = notification.msg, level = notification.level })
  end
  return notifications
end

return M
