local M = {}

local function relative_to(file, cwd)
  local prefix = cwd:sub(-1) == '/' and cwd or cwd .. '/'
  local compared_file = file
  local compared_prefix = prefix

  if vim.fn.has('win32') == 1 then
    compared_file = compared_file:lower()
    compared_prefix = compared_prefix:lower()
  end
  if not vim.startswith(compared_file, compared_prefix) then return nil end

  return file:sub(#prefix + 1)
end

local function file_context(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  if file == '' then return nil, 'The current buffer has no file.' end
  if vim.bo[buf].buftype ~= '' then return nil, 'The current buffer is not a file buffer.' end

  return {
    file = vim.fs.normalize(file),
    filetype = vim.bo[buf].filetype,
    modified = vim.bo[buf].modified,
  }
end

function M.from_buffer(buf)
  buf = buf or 0

  local context, context_error = file_context(buf)
  if context == nil then return nil, context_error end
  if context.modified then return nil, 'The current buffer has unsaved changes.' end
  if vim.fn.filereadable(context.file) ~= 1 then return nil, 'The current buffer is not saved on disk.' end

  return context
end

function M.from_buffers(focus)
  local current = vim.api.nvim_get_current_buf()
  local contexts = {}
  local skipped = 0

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      local buffer_context = M.from_buffer(buf)
      if focus ~= nil and buf == current then buffer_context = focus end
      if buffer_context == nil then
        skipped = skipped + 1
      else
        table.insert(contexts, buffer_context)
      end
    end
  end

  return contexts, skipped
end

function M.from_selection(buf, mode, first, last)
  buf = buf or 0

  local context, context_error = file_context(buf)
  if context == nil then return nil, context_error end
  if vim.fn.filereadable(context.file) ~= 1 then return nil, 'The current buffer is not saved on disk.' end

  first = first or vim.api.nvim_buf_get_mark(buf, '<')
  last = last or vim.api.nvim_buf_get_mark(buf, '>')
  if first[1] == 0 or last[1] == 0 then return nil, 'The current buffer has no visual selection.' end
  if first[1] > last[1] or (first[1] == last[1] and first[2] > last[2]) then
    first, last = last, first
  end

  local region_mode = mode or vim.fn.visualmode()
  if region_mode == '' then region_mode = 'v' end
  if region_mode == 'V' then
    first = { first[1], 0 }
    last = { last[1], 0 }
  end
  local buffer_number = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local first_position = { buffer_number, first[1], first[2] + 1, 0 }
  local last_position = { buffer_number, last[1], last[2] + 1, 0 }
  local ok, lines = pcall(vim.fn.getregion, first_position, last_position, { type = region_mode })
  if not ok or #lines == 0 then return nil, 'Could not read the visual selection.' end

  context.start_line = math.min(first[1], last[1])
  context.end_line = math.max(first[1], last[1])
  context.range = true

  local full_lines = vim.api.nvim_buf_get_lines(buf, context.start_line - 1, context.end_line, false)
  context.whole_lines = vim.deep_equal(lines, full_lines)
  if context.modified and context.whole_lines then return nil, 'The current buffer has unsaved changes.' end
  if not context.whole_lines then context.selection = table.concat(lines, '\n') end

  return context
end

function M.for_agent(context, cwd)
  local result = vim.deepcopy(context)
  result.relative_file = result.file

  if type(cwd) ~= 'string' or cwd == '' then return result end

  local relative_path = relative_to(result.file, vim.fs.normalize(cwd))
  if relative_path ~= nil then result.relative_file = relative_path end

  return result
end

return M
