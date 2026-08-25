local M = {}

local minimum_herdr_version = { 0, 7, 5 }

local function parse_version(output)
  local major, minor, patch = output:match('herdr%s+(%d+)%.(%d+)%.(%d+)')
  if major == nil then return nil end
  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function version_at_least(actual, minimum)
  for index = 1, 3 do
    if actual[index] > minimum[index] then return true end
    if actual[index] < minimum[index] then return false end
  end
  return true
end

function M.check()
  vim.health.start('herdr-context.nvim')

  if vim.fn.has('nvim-0.10') == 1 then
    vim.health.ok('Neovim 0.10 or later is available')
  else
    vim.health.error('Neovim 0.10 or later is required')
  end

  if vim.fn.executable('herdr') ~= 1 then
    vim.health.error('Herdr CLI was not found in PATH')
    return
  end

  local version_result = vim.system({ 'herdr', '--version' }, { text = true }):wait()
  local version = parse_version(version_result.stdout or '')
  if version_result.code ~= 0 then
    vim.health.error('Could not run `herdr --version`')
  elseif version == nil then
    vim.health.warn('Could not parse the Herdr version')
  elseif version_at_least(version, minimum_herdr_version) then
    vim.health.ok((version_result.stdout or ''):match('^%s*(.-)%s*$'))
  else
    vim.health.error('Herdr 0.7.5 or later is required')
  end

  local workspace_id = vim.env.HERDR_WORKSPACE_ID
  if workspace_id == nil or workspace_id == '' then
    vim.health.warn('HERDR_WORKSPACE_ID is not set; run Neovim inside a Herdr pane')
  else
    vim.health.ok('HERDR_WORKSPACE_ID is set')
  end

  if vim.env.HERDR_TAB_ID == nil or vim.env.HERDR_TAB_ID == '' then
    vim.health.warn('HERDR_TAB_ID is not set; run Neovim inside a Herdr pane')
  else
    vim.health.ok('HERDR_TAB_ID is set')
  end

  local list_result = vim.system({ 'herdr', 'agent', 'list' }, { text = true }):wait()
  if list_result.code == 0 then
    vim.health.ok('Herdr accepted `agent list`')
  else
    vim.health.error('Herdr did not accept `agent list`')
  end

  if workspace_id ~= nil and workspace_id ~= '' then
    local tabs_result = vim.system({ 'herdr', 'tab', 'list', '--workspace', workspace_id }, { text = true }):wait()
    if tabs_result.code == 0 then
      vim.health.ok('Herdr accepted `tab list`')
    else
      vim.health.error('Herdr did not accept `tab list`')
    end
  end
end

return M
