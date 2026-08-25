local M = {}

local function harness_name(agent)
  for _, key in ipairs({ 'name', 'agent', 'kind' }) do
    if type(agent[key]) == 'string' and agent[key] ~= '' then return agent[key] end
  end
  return 'unknown'
end

local function tab_metadata(tabs)
  local result = {}
  if not vim.islist(tabs) then return result end

  for index, tab in ipairs(tabs) do
    if type(tab) == 'table' and type(tab.tab_id) == 'string' and tab.tab_id ~= '' then
      local label = tab.label or tab.number or tab.tab_id
      result[tab.tab_id] = { label = tostring(label), order = index }
    end
  end
  return result
end

function M.candidates(agents, workspace_id, tab_id)
  if not vim.islist(agents) then
    return nil, {
      code = 'invalid_agents',
      message = 'Herdr returned an invalid agent list.',
    }
  end

  local workspace = {}
  local current = {}
  for _, agent in ipairs(agents) do
    if type(agent) == 'table' and agent.workspace_id == workspace_id then
      table.insert(workspace, agent)
      if agent.tab_id == tab_id then table.insert(current, agent) end
    end
  end

  if #current > 0 then return current end
  if #workspace > 0 then return workspace end

  return nil, {
    code = 'no_agents',
    message = 'No Herdr agents are available in the current workspace.',
  }
end

function M.delivery_target(agent)
  if type(agent) ~= 'table' then
    return nil, { code = 'invalid_agent', message = 'The selected Herdr agent is invalid.' }
  end
  if agent.agent_status == 'blocked' then
    return nil, { code = 'blocked', message = 'The selected Herdr agent is blocked; no input was sent.' }
  end
  if type(agent.pane_id) ~= 'string' or agent.pane_id == '' then
    return nil, { code = 'invalid_agent', message = 'The selected Herdr agent has no pane identifier.' }
  end

  local kind = type(agent.kind) == 'string' and agent.kind or agent.agent
  local foreground_cwd = type(agent.foreground_cwd) == 'string' and agent.foreground_cwd or nil
  local cwd = type(agent.cwd) == 'string' and agent.cwd or nil
  return {
    pane_id = agent.pane_id,
    kind = kind,
    foreground_cwd = foreground_cwd,
    cwd = cwd,
  }
end

local status_indicators = {
  blocked = '●',
  working = '●',
  done = '●',
  idle = '○',
  unknown = '·',
}

local function status_indicator(status) return status_indicators[status] or status_indicators.unknown end

local function agent_title(agent)
  for _, key in ipairs({ 'title', 'terminal_title_stripped', 'terminal_title' }) do
    if type(agent[key]) == 'string' and agent[key] ~= '' then return agent[key] end
  end
end

function M.make_choices(agents, tabs)
  local metadata = tab_metadata(tabs)
  local ordered = {}
  if vim.islist(agents) then
    for _, agent in ipairs(agents) do
      if type(agent) == 'table' then table.insert(ordered, agent) end
    end
  end

  table.sort(ordered, function(left, right)
    local left_tab = metadata[left.tab_id] or { order = math.huge }
    local right_tab = metadata[right.tab_id] or { order = math.huge }
    if left_tab.order ~= right_tab.order then return left_tab.order < right_tab.order end
    return (left.pane_id or '') < (right.pane_id or '')
  end)

  local choices = {}
  for index, agent in ipairs(ordered) do
    local status = agent.agent_status
    if type(status) ~= 'string' or status == '' then status = 'unknown' end

    local tab = metadata[agent.tab_id]
    local tab_label = tab and tab.label or agent.tab_id or 'unknown'
    local label =
      string.format('[%d] %s  Agent: %s  Tab: %s', index, status_indicator(status), harness_name(agent), tab_label)

    local title = agent_title(agent)
    if title ~= nil then label = label .. '  Title: ' .. title end

    local cwd = type(agent.foreground_cwd) == 'string' and agent.foreground_cwd or agent.cwd
    if type(cwd) == 'string' and cwd ~= '' then label = label .. '  CWD: ' .. cwd end

    table.insert(choices, { agent = agent, label = label })
  end

  return choices
end

return M
