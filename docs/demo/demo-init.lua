local namespace = vim.api.nvim_create_namespace('herdr-context-demo')

require('herdr-context').setup({ mappings = { buffer = 'gs', buffers = 'gS' } })
vim.diagnostic.set(namespace, 0, {
  {
    lnum = 2,
    col = 0,
    severity = vim.diagnostic.severity.ERROR,
    message = 'unused greeting',
    source = 'demo',
  },
  {
    lnum = 7,
    col = 0,
    severity = vim.diagnostic.severity.WARN,
    message = 'name missing',
    source = 'demo',
  },
})
