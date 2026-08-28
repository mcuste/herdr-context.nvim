local M = {}

local function selection_fence(selection)
  local length = 3
  for run in selection:gmatch('`+') do
    length = math.max(length, #run + 1)
  end
  return string.rep('`', length)
end

local function append_selection(prompt, context)
  if context.selection == nil then return prompt end

  local fence = selection_fence(context.selection)
  return string.format('%s\n\n%s%s\n%s\n%s', prompt, fence, context.filetype or '', context.selection, fence)
end

local function append_diagnostic(prompt, context)
  if context.diagnostic == nil then return prompt end
  return string.format('%s%s ', prompt, context.diagnostic)
end

local function append_details(prompt, context) return append_selection(append_diagnostic(prompt, context), context) end

local function format_claude_style(context)
  local prompt = context.range
      and string.format(' @%s#%d-%d ', context.relative_file, context.start_line, context.end_line)
    or string.format(' @%s ', context.relative_file)
  return append_details(prompt, context)
end

local function format_codex_style(context)
  local path = context.relative_file
  if path:find('%s') ~= nil and path:find('"', 1, true) == nil then path = string.format('"%s"', path) end
  local prompt = context.range and string.format(' %s Lines %d-%d. ', path, context.start_line, context.end_line)
    or string.format(' %s ', path)
  return append_details(prompt, context)
end

local function format_gemini_style(context)
  local path = context.relative_file:gsub('[ \t%(%)%[%]{};%?!,]', '\\%0')
  local prompt = context.range and string.format(' @%s Lines %d-%d. ', path, context.start_line, context.end_line)
    or string.format(' @%s ', path)
  return append_details(prompt, context)
end

local function format_pi_style(context)
  local prompt = context.range
      and string.format(' @%s#L%d-%d ', context.relative_file, context.start_line, context.end_line)
    or string.format(' @%s ', context.relative_file)
  return append_details(prompt, context)
end

local function format_generic_style(context)
  local reference = '@' .. context.relative_file
  local prompt = context.range and string.format(' %s Lines %d-%d. ', reference, context.start_line, context.end_line)
    or string.format(' %s ', reference)
  return append_details(prompt, context)
end

local AntigravityAdapter = { format = format_generic_style }
local ClaudeAdapter = { format = format_claude_style }
local ClineAdapter = { format = format_generic_style }
local CodexAdapter = { format = format_codex_style }
local CopilotAdapter = { format = format_generic_style }
local CursorAdapter = { format = format_generic_style }
local GeminiAdapter = { format = format_gemini_style }
local KiloAdapter = { format = format_claude_style }
local KimiAdapter = { format = format_generic_style }
local OmpAdapter = { format = format_pi_style }
local OpencodeAdapter = { format = format_claude_style }
local PiAdapter = { format = format_pi_style }
local QwenAdapter = { format = format_gemini_style }
local GenericAdapter = { format = format_generic_style }

M.registry = {
  agy = AntigravityAdapter,
  claude = ClaudeAdapter,
  cline = ClineAdapter,
  codex = CodexAdapter,
  copilot = CopilotAdapter,
  cursor = CursorAdapter,
  gemini = GeminiAdapter,
  kilo = KiloAdapter,
  kimi = KimiAdapter,
  omp = OmpAdapter,
  opencode = OpencodeAdapter,
  pi = PiAdapter,
  qwen = QwenAdapter,
  generic = GenericAdapter,
}

function M.get(kind)
  if type(kind) ~= 'string' then return GenericAdapter end
  return M.registry[kind] or GenericAdapter
end

function M.for_agent(agent) return M.get(agent.kind or agent.agent) end

function M.format(agent, context) return M.for_agent(agent).format(context) end

-- One file per line, so a fenced selection cannot swallow the next reference.
function M.format_many(agent, contexts)
  local adapter = M.for_agent(agent)
  local prompts = {}
  for _, context in ipairs(contexts) do
    table.insert(prompts, adapter.format(context))
  end

  return table.concat(prompts, '\n')
end

return M
