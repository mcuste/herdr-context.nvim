local M = {}

local notification_sources = {
  require('herdr-context.messages.nvim_notify'),
  require('herdr-context.messages.mini_notify'),
  require('herdr-context.messages.snacks_notifier'),
  require('herdr-context.messages.noice'),
}

local function fence(text)
  local longest = 0
  for ticks in text:gmatch('`+') do
    longest = math.max(longest, #ticks)
  end
  return string.rep('`', math.max(3, longest + 1))
end

local function has_text(text) return type(text) == 'string' and text:find('%S') ~= nil end

local function format_section(title, text)
  if not has_text(text) then return nil end

  text = text:gsub('\n+$', '')
  local marker = fence(text)
  return string.format('%s:\n\n%stext\n%s\n%s', title, marker, text, marker)
end

local function level_name(level)
  if type(level) == 'string' then return level:upper() end
  if type(level) ~= 'number' then return nil end

  for name, value in pairs(vim.log.levels) do
    if value == level then return name end
  end
end

local function format_notifications(source)
  local ok, notifications = pcall(source.collect)
  if not ok or type(notifications) ~= 'table' then return nil end

  local formatted = {}
  for _, notification in ipairs(notifications) do
    if type(notification) == 'table' and has_text(notification.message) then
      local label = {}
      local level = level_name(notification.level)
      if level ~= nil then table.insert(label, level) end
      if has_text(notification.title) then table.insert(label, notification.title) end

      local text = #label == 0 and notification.message
        or string.format('[%s]\n%s', table.concat(label, ' '), notification.message)
      table.insert(formatted, text)
    end
  end
  return format_section(source.name, table.concat(formatted, '\n\n'))
end

local function add_section(sections, section)
  if section ~= nil then table.insert(sections, section) end
end

function M.collect()
  local result = vim.api.nvim_exec2('messages', { output = true })
  local history = {}

  add_section(history, format_section('Neovim messages', result.output))
  for _, source in ipairs(notification_sources) do
    add_section(history, format_notifications(source))
  end

  if #history == 0 then return nil, 'No Neovim messages or notification history is available.' end
  return ' ' .. table.concat(history, '\n\n') .. ' '
end

return M
