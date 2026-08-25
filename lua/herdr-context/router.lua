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

  local bases = {}
  local counts = {}
  for index, agent in ipairs(ordered) do
    local tab = metadata[agent.tab_id]
    local tab_label = tab and tab.label or agent.tab_id or 'unknown'
    local base = string.format('%s > %s', tab_label, harness_name(agent))
    bases[index] = base
    counts[base] = (counts[base] or 0) + 1
  end

  local choices = {}
  for index, agent in ipairs(ordered) do
    local label = bases[index]
    if counts[label] > 1 then label = string.format('%s (%s)', label, agent.pane_id or 'unknown pane') end

    local details = {}
    if type(agent.agent_status) == 'string' and agent.agent_status ~= '' then
      table.insert(details, agent.agent_status)
    end
    local cwd = type(agent.foreground_cwd) == 'string' and agent.foreground_cwd or agent.cwd
    if type(cwd) == 'string' and cwd ~= '' then table.insert(details, cwd) end
    if #details > 0 then label = label .. ' | ' .. table.concat(details, ' | ') end

    table.insert(choices, { agent = agent, label = label })
  end

  return choices
end

return M
