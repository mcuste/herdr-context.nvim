local adapters = require('herdr-context.adapters')
local cli = require('herdr-context.cli')
local context = require('herdr-context.context')
local messages = require('herdr-context.messages')
local router = require('herdr-context.router')

local M = {}

M.config = {
  mappings = {
    buffer = '',
    buffers = '',
    diagnostics = '',
    messages = '',
    buffers_diagnostics = '',
    quickfix = '',
    quickfix_all = '',
    loclist = '',
  },
  quickfix = {
    limit = 50,
  },
}

local default_config = vim.deepcopy(M.config)

local function notify(message, level) vim.notify(message, level, { title = 'herdr-context.nvim' }) end

local function config_error(name, value, expected)
  error(string.format('(herdr-context.nvim) `%s` must be %s, not %s', name, expected, type(value)), 0)
end

local function parse_mappings(parsed, mappings)
  if mappings == nil then return end
  if type(mappings) ~= 'table' then config_error('mappings', mappings, 'a table') end

  for name in pairs(parsed.mappings) do
    local mapping = mappings[name]
    if mapping ~= nil then
      if type(mapping) ~= 'string' then config_error('mappings.' .. name, mapping, 'a string') end
      parsed.mappings[name] = mapping
    end
  end
end

local function parse_quickfix(parsed, quickfix)
  if quickfix == nil then return end
  if type(quickfix) ~= 'table' then config_error('quickfix', quickfix, 'a table') end

  local limit = quickfix.limit
  if limit == nil then return end
  if type(limit) ~= 'number' or limit < 0 or limit % 1 ~= 0 then
    config_error('quickfix.limit', limit, 'a whole number of 0 or more')
  end
  parsed.quickfix.limit = limit
end

local function parse_config(config)
  if config == nil then return vim.deepcopy(default_config) end
  if type(config) ~= 'table' then config_error('config', config, 'a table') end

  local parsed = vim.deepcopy(default_config)
  parse_mappings(parsed, config.mappings)
  parse_quickfix(parsed, config.quickfix)
  return parsed
end

local function herdr_location()
  local workspace_id = vim.env.HERDR_WORKSPACE_ID
  local tab_id = vim.env.HERDR_TAB_ID

  if workspace_id == nil or workspace_id == '' then return nil, 'HERDR_WORKSPACE_ID is not set.' end
  if tab_id == nil or tab_id == '' then return nil, 'HERDR_TAB_ID is not set.' end

  return { workspace_id = workspace_id, tab_id = tab_id }
end

local function insert_text(text, target, kind)
  local failure_subject = kind == 'context' and 'context' or 'Neovim messages'
  local placed_subject = kind == 'context' and 'Context was placed' or 'Neovim messages were placed'

  cli.send_text(target.pane_id, text, function(text_result)
    if not text_result.ok then
      notify(
        'Could not place ' .. failure_subject .. ' in the agent input: ' .. text_result.error,
        vim.log.levels.ERROR
      )
      return
    end

    cli.focus(target.pane_id, function(focus_result)
      if not focus_result.ok then
        notify(placed_subject .. ', but the agent could not be focused: ' .. focus_result.error, vim.log.levels.ERROR)
      end
    end)
  end)
end

local function insert_contexts(contexts, target)
  local cwd = target.foreground_cwd or target.cwd
  local agent_contexts = {}
  for _, buffer_context in ipairs(contexts) do
    table.insert(agent_contexts, context.for_agent(buffer_context, cwd))
  end
  insert_text(adapters.format_many(target, agent_contexts), target, 'context')
end

local function parse_and_insert(insert, agent)
  local target, target_error = router.delivery_target(agent)
  if target == nil then
    local level = target_error.code == 'invalid_agent' and vim.log.levels.ERROR or vim.log.levels.WARN
    notify(target_error.message, level)
    return
  end

  insert(target)
end

local function select_and_insert(insert, candidates, workspace_id)
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
      parse_and_insert(insert, choice.agent)
    end)
  end)
end

local function route_and_insert(insert, agents, location)
  local candidates, route_error = router.candidates(agents, location.workspace_id, location.tab_id)
  if candidates == nil then
    notify(route_error.message, vim.log.levels.WARN)
    return
  end

  if #candidates == 1 then
    parse_and_insert(insert, candidates[1])
    return
  end

  select_and_insert(insert, candidates, location.workspace_id)
end

local function send_to_agent(insert)
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

    route_and_insert(insert, result.value.agents, location)
  end)
end

local function send_contexts(contexts)
  send_to_agent(function(target) insert_contexts(contexts, target) end)
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

-- A nil focus selects the whole current buffer.
local function focus_context(opts)
  if visual_mode() ~= nil then return visual_context() end
  if type(opts) == 'table' and (opts.range or 0) > 0 then return context.from_selection(0) end
  return nil
end

-- Whole-line selections are references, so they require a saved buffer.
local function saved_focus_context(opts)
  local focus, focus_error = focus_context(opts)
  if focus_error ~= nil then return nil, focus_error end
  if focus ~= nil and focus.modified then return nil, 'The current buffer has unsaved changes.' end

  return focus
end

local function buffer_or_selection(opts)
  local focus, focus_error = saved_focus_context(opts)
  if focus_error ~= nil then return nil, focus_error end
  if focus ~= nil then return focus end

  return context.from_buffer(0)
end

local function warn_skipped(skipped, singular, plural)
  if skipped == 0 then return end

  local noun = skipped == 1 and singular or plural
  notify(string.format('Skipped %d %s with unsaved changes or no file on disk.', skipped, noun), vim.log.levels.WARN)
end

local list_names = {
  quickfix = { list = 'quickfix list', entry = 'quickfix entry', entries = 'quickfix entries' },
  loclist = { list = 'location list', entry = 'location list entry', entries = 'location list entries' },
}

local function send_list(source, limit)
  local names = list_names[source]
  local contexts, skipped, total = context.from_quickfix(source, limit)
  if #contexts == 0 then
    if skipped == 0 then
      notify(string.format('The %s is empty.', names.list), vim.log.levels.WARN)
    else
      notify(string.format('No %s points at a file saved on disk.', names.entry), vim.log.levels.WARN)
    end
    return
  end

  warn_skipped(skipped, names.entry, names.entries)
  if #contexts < total then
    local message = string.format('Sent the first %d of %d references from the %s.', #contexts, total, names.list)
    notify(message, vim.log.levels.WARN)
  end

  send_contexts(contexts)
end

local commands = {
  { name = 'HerdrContextSendBuffer', action = 'send_buffer', desc = 'the current file or visual selection' },
  { name = 'HerdrContextSendBuffers', action = 'send_buffers', desc = 'every open file' },
  { name = 'HerdrContextSendDiagnostics', action = 'send_diagnostics', desc = 'the current file and its diagnostics' },
  {
    name = 'HerdrContextSendBuffersDiagnostics',
    action = 'send_buffers_diagnostics',
    desc = 'every open file and its diagnostics',
  },
  { name = 'HerdrContextSendQuickfix', action = 'send_quickfix', desc = 'the quickfix list' },
  { name = 'HerdrContextSendQuickfixAll', action = 'send_quickfix_all', desc = 'the whole quickfix list' },
  { name = 'HerdrContextSendLoclist', action = 'send_loclist', desc = 'the location list' },
  { name = 'HerdrContextSendMessages', action = 'send_messages', desc = 'the Neovim message history' },
}

local mappings = {
  { name = 'buffer', action = 'send_buffer', desc = 'buffer or selection' },
  { name = 'buffers', action = 'send_buffers', desc = 'all open buffers' },
  { name = 'diagnostics', action = 'send_diagnostics', desc = 'diagnostics' },
  { name = 'buffers_diagnostics', action = 'send_buffers_diagnostics', desc = 'all open buffers and diagnostics' },
  { name = 'quickfix', action = 'send_quickfix', desc = 'quickfix list' },
  { name = 'quickfix_all', action = 'send_quickfix_all', desc = 'whole quickfix list' },
  { name = 'loclist', action = 'send_loclist', desc = 'location list' },
  { name = 'messages', action = 'send_messages', desc = 'Neovim message history' },
}

function M.setup(config)
  M.config = parse_config(config)

  for _, command in ipairs(commands) do
    vim.api.nvim_create_user_command(command.name, function(opts) M[command.action](opts) end, {
      desc = 'Send ' .. command.desc .. ' to its Herdr agent',
      force = true,
      range = true,
    })
  end

  for _, mapping in ipairs(mappings) do
    local keys = M.config.mappings[mapping.name]
    if keys ~= '' then
      vim.keymap.set({ 'n', 'x' }, keys, function() M[mapping.action]() end, {
        desc = 'Send ' .. mapping.desc .. ' to Herdr agent',
      })
    end
  end
end

function M.send_buffer(opts)
  local buffer_context, buffer_error = buffer_or_selection(opts)
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
  warn_skipped(skipped, 'buffer', 'buffers')

  send_contexts(contexts)
end

function M.send_diagnostics(opts)
  local base, base_error = buffer_or_selection(opts)
  if base == nil then
    notify(base_error, vim.log.levels.WARN)
    return
  end

  local contexts, diagnostics_error = context.with_diagnostics(0, base)
  if contexts == nil then
    notify(diagnostics_error, vim.log.levels.WARN)
    return
  end

  send_contexts(contexts)
end

function M.send_buffers_diagnostics(opts)
  local focus, focus_error = saved_focus_context(opts)
  if focus_error ~= nil then
    notify(focus_error, vim.log.levels.WARN)
    return
  end

  local contexts, skipped, reported = context.from_buffers_with_diagnostics(focus)
  if #contexts == 0 then
    notify('No open buffer is saved on disk.', vim.log.levels.WARN)
    return
  end
  if reported == 0 then
    notify('No open buffer has diagnostics.', vim.log.levels.WARN)
    return
  end
  warn_skipped(skipped, 'buffer', 'buffers')

  send_contexts(contexts)
end

function M.send_quickfix() send_list('quickfix', M.config.quickfix.limit) end

function M.send_quickfix_all() send_list('quickfix', 0) end

-- A location list holds the results of one window, so it stays under the quickfix limit.
function M.send_loclist() send_list('loclist', 0) end

function M.send_messages()
  local text, message_error = messages.collect()
  if text == nil then
    notify(message_error, vim.log.levels.WARN)
    return
  end

  send_to_agent(function(target) insert_text(text, target, 'messages') end)
end

return M
