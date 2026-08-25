local M = {}

local function trim(value) return (value or ''):match('^%s*(.-)%s*$') end

local function decode_output(stdout)
  if stdout == '' then return nil end

  local ok, decoded = pcall(vim.json.decode, stdout)
  if not ok then return nil, 'Herdr returned invalid JSON.' end
  if type(decoded) ~= 'table' then return nil, 'Herdr returned an invalid response.' end

  return decoded
end

local function response_error(decoded, stderr)
  if type(decoded) == 'table' and type(decoded.error) == 'table' and type(decoded.error.message) == 'string' then
    return decoded.error.message
  end

  stderr = trim(stderr)
  if stderr ~= '' then return stderr end
  return 'Herdr command failed.'
end

function M.parse_result(result, empty_output_is_success)
  local stdout = trim(result.stdout)
  local decoded, decode_error = decode_output(stdout)

  if result.code ~= 0 then return { ok = false, code = result.code, error = response_error(decoded, result.stderr) } end
  if decode_error ~= nil then return { ok = false, code = result.code, error = decode_error } end
  if decoded == nil and empty_output_is_success then return { ok = true, code = result.code, value = {} } end
  if decoded == nil then return { ok = false, code = result.code, error = 'Herdr returned no JSON output.' } end
  if decoded.error ~= nil then
    return { ok = false, code = result.code, error = response_error(decoded, result.stderr) }
  end
  if type(decoded.result) ~= 'table' then
    return { ok = false, code = result.code, error = 'Herdr response has no result.' }
  end

  return { ok = true, code = result.code, value = decoded.result }
end

local agent_fields = {
  'workspace_id',
  'tab_id',
  'pane_id',
  'name',
  'agent',
  'kind',
  'agent_status',
  'title',
  'terminal_title',
  'terminal_title_stripped',
  'foreground_cwd',
  'cwd',
}

local function parse_optional_string(record, field)
  local value = record[field]
  if value == nil or type(value) == 'string' then return value end
  return nil, string.format('Herdr response has an invalid %s.', field)
end

local function parse_agent(record)
  if type(record) ~= 'table' then return nil, 'Herdr response has an invalid agent.' end

  local agent = {}
  for _, field in ipairs(agent_fields) do
    local value, parse_error = parse_optional_string(record, field)
    if parse_error ~= nil then return nil, parse_error end
    agent[field] = value
  end
  return agent
end

local function parse_tab(record)
  if type(record) ~= 'table' then return nil, 'Herdr response has an invalid tab.' end
  if type(record.tab_id) ~= 'string' or record.tab_id == '' then
    return nil, 'Herdr response has an invalid tab identifier.'
  end
  if record.label ~= nil and type(record.label) ~= 'string' and type(record.label) ~= 'number' then
    return nil, 'Herdr response has an invalid tab label.'
  end
  if record.number ~= nil and type(record.number) ~= 'number' then
    return nil, 'Herdr response has an invalid tab number.'
  end

  return {
    tab_id = record.tab_id,
    label = record.label and tostring(record.label) or nil,
    number = record.number and tostring(record.number) or nil,
  }
end

local function parse_records(result, field, list_error, parse_record)
  if not result.ok then return result end

  local records = result.value[field]
  if not vim.islist(records) then return { ok = false, code = result.code, error = list_error } end

  local parsed = {}
  for _, record in ipairs(records) do
    local value, parse_error = parse_record(record)
    if value == nil then return { ok = false, code = result.code, error = parse_error } end
    table.insert(parsed, value)
  end
  return { ok = true, code = result.code, value = { [field] = parsed } }
end

function M.parse_agent_list(result)
  return parse_records(result, 'agents', 'Herdr response has no agent list.', parse_agent)
end

function M.parse_tab_list(result) return parse_records(result, 'tabs', 'Herdr response has no tab list.', parse_tab) end

local function run(args, callback, empty_output_is_success)
  if vim.fn.executable('herdr') ~= 1 then
    callback({ ok = false, error = 'Herdr CLI was not found in PATH.' })
    return
  end

  local command = { 'herdr' }
  vim.list_extend(command, args)
  vim.system(command, { text = true }, function(result)
    vim.schedule(function() callback(M.parse_result(result, empty_output_is_success)) end)
  end)
end

function M.list_agents(callback)
  run({ 'agent', 'list' }, function(result) callback(M.parse_agent_list(result)) end)
end

function M.list_tabs(workspace_id, callback)
  run({ 'tab', 'list', '--workspace', workspace_id }, function(result) callback(M.parse_tab_list(result)) end)
end

function M.send_text(target, text, callback) run({ 'pane', 'send-text', target, text }, callback, true) end

function M.focus(target, callback) run({ 'agent', 'focus', target }, callback, true) end

return M
