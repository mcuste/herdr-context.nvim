local adapters = require('herdr-context.adapters')
local cli = require('herdr-context.cli')
local context = require('herdr-context.context')
local router = require('herdr-context.router')

local M = {}

M.config = {
  mappings = {
    buffer = '',
    buffers = '',
    selection = '',
  },
}

local default_config = vim.deepcopy(M.config)

local function notify(message, level) vim.notify(message, level, { title = 'herdr-context.nvim' }) end

local function config_error(name, value, expected)
  error(string.format('(herdr-context.nvim) `%s` must be %s, not %s', name, expected, type(value)), 0)
end

local function parse_config(config)
  if config == nil then return vim.deepcopy(default_config) end
  if type(config) ~= 'table' then config_error('config', config, 'a table') end

  local mappings = config.mappings
  if mappings == nil then return vim.deepcopy(default_config) end
  if type(mappings) ~= 'table' then config_error('mappings', mappings, 'a table') end

  local parsed = vim.deepcopy(default_config)
  for name in pairs(parsed.mappings) do
    local mapping = mappings[name]
    if mapping ~= nil then
      if type(mapping) ~= 'string' then config_error('mappings.' .. name, mapping, 'a string') end
      parsed.mappings[name] = mapping
    end
  end
  return parsed
end

local function herdr_location()
  local workspace_id = vim.env.HERDR_WORKSPACE_ID
  local tab_id = vim.env.HERDR_TAB_ID

  if workspace_id == nil or workspace_id == '' then return nil, 'HERDR_WORKSPACE_ID is not set.' end
  if tab_id == nil or tab_id == '' then return nil, 'HERDR_TAB_ID is not set.' end

  return { workspace_id = workspace_id, tab_id = tab_id }
end

local function insert_contexts(contexts, target)
  local cwd = target.foreground_cwd or target.cwd
  local agent_contexts = {}
  for _, buffer_context in ipairs(contexts) do
    table.insert(agent_contexts, context.for_agent(buffer_context, cwd))
  end
  local text = adapters.format_many(target, agent_contexts)

  cli.send_text(target.pane_id, text, function(text_result)
    if not text_result.ok then
      notify('Could not place context in the agent input: ' .. text_result.error, vim.log.levels.ERROR)
      return
    end

    cli.focus(target.pane_id, function(focus_result)
      if not focus_result.ok then
        notify('Context was placed, but the agent could not be focused: ' .. focus_result.error, vim.log.levels.ERROR)
      end
    end)
  end)
end

local function parse_and_insert(contexts, agent)
  local target, target_error = router.delivery_target(agent)
  if target == nil then
    local level = target_error.code == 'invalid_agent' and vim.log.levels.ERROR or vim.log.levels.WARN
    notify(target_error.message, level)
    return
  end

  insert_contexts(contexts, target)
end

local function select_and_insert(contexts, candidates, workspace_id)
  cli.list_tabs(workspace_id, function(result)
    if not result.ok then
      notify('Could not list Herdr tabs: ' .. result.error, vim.log.levels.ERROR)
      return
    end

    local choices = router.make_choices(candidates, result.value.tabs)
    vim.ui.select(choices, {
      prompt = 'Select a Herdr agent:',
      format_item = function(choice) return choice.label end,
    }, function(choice)
      if choice == nil then return end
      parse_and_insert(contexts, choice.agent)
    end)
  end)
end

local function route_and_insert(contexts, agents, location)
  local candidates, route_error = router.candidates(agents, location.workspace_id, location.tab_id)
  if candidates == nil then
    notify(route_error.message, vim.log.levels.WARN)
    return
  end

  if #candidates == 1 then
    parse_and_insert(contexts, candidates[1])
    return
  end

  select_and_insert(contexts, candidates, location.workspace_id)
end

local function send_contexts(contexts)
  local location, location_error = herdr_location()
  if location == nil then
    notify(location_error, vim.log.levels.ERROR)
    return
  end

  cli.list_agents(function(result)
    if not result.ok then
      notify('Could not list Herdr agents: ' .. result.error, vim.log.levels.ERROR)
      return
    end

    route_and_insert(contexts, result.value.agents, location)
  end)
end

local function visual_mode()
  local mode = vim.fn.mode()
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then return nil end
  return mode
end

local function visual_context()
  local mode = visual_mode()
  if mode == nil then return context.from_selection(0) end

  local anchor = vim.fn.getpos('v')
  local cursor = vim.fn.getpos('.')
  local first = { anchor[2], anchor[3] - 1 }
  local last = { cursor[2], cursor[3] - 1 }
  return context.from_selection(0, mode, first, last)
end

-- A nil result is not a failure here; it means the current buffer sends its whole file.
local function focus_context(opts)
  if visual_mode() ~= nil then return visual_context() end
  if type(opts) == 'table' and (opts.range or 0) > 0 then return context.from_selection(0) end
  return nil
end

function M.setup(config)
  M.config = parse_config(config)

  vim.api.nvim_create_user_command('HerdrContextSendBuffer', M.send_buffer, {
    desc = 'Send the current file to its Herdr agent',
    force = true,
  })
  vim.api.nvim_create_user_command('HerdrContextSendBuffers', M.send_buffers, {
    desc = 'Send every open file to its Herdr agent',
    force = true,
    range = true,
  })
  vim.api.nvim_create_user_command('HerdrContextSendSelection', M.send_selection, {
    desc = 'Send the visual selection to its Herdr agent',
    force = true,
    range = true,
  })

  if M.config.mappings.buffer ~= '' then
    vim.keymap.set('n', M.config.mappings.buffer, M.send_buffer, { desc = 'Send buffer to Herdr agent' })
  end
  if M.config.mappings.buffers ~= '' then
    vim.keymap.set(
      { 'n', 'x' },
      M.config.mappings.buffers,
      M.send_buffers,
      { desc = 'Send all open buffers to Herdr agent' }
    )
  end
  if M.config.mappings.selection ~= '' then
    vim.keymap.set('x', M.config.mappings.selection, M.send_selection, { desc = 'Send selection to Herdr agent' })
  end
end

function M.send_buffer()
  local buffer_context, buffer_error = context.from_buffer(0)
  if buffer_context == nil then
    notify(buffer_error, vim.log.levels.WARN)
    return
  end

  send_contexts({ buffer_context })
end

function M.send_buffers(opts)
  local focus, focus_error = focus_context(opts)
  if focus_error ~= nil then
    notify(focus_error, vim.log.levels.WARN)
    return
  end

  local contexts, skipped = context.from_buffers(focus)
  if #contexts == 0 then
    notify('No open buffer is saved on disk.', vim.log.levels.WARN)
    return
  end
  if skipped > 0 then
    local noun = skipped == 1 and 'buffer' or 'buffers'
    local message = string.format('Skipped %d %s with unsaved changes or no file on disk.', skipped, noun)
    notify(message, vim.log.levels.WARN)
  end

  send_contexts(contexts)
end

function M.send_selection()
  local selection_context, selection_error = visual_context()
  if selection_context == nil then
    notify(selection_error, vim.log.levels.WARN)
    return
  end

  send_contexts({ selection_context })
end

return M
