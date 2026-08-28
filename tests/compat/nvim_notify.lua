local shared = dofile('tests/compat/shared.lua')

local notify = require('notify')
notify.setup({ background_colour = '#000000', timeout = 100 })
notify(shared.message, vim.log.levels.WARN, { title = shared.title })

local collected = shared.wait_for_collected()
local body = shared.assert_section(collected, 'nvim-notify notifications')
shared.assert_label(body, '[WARN ')
shared.assert_label(body, shared.title)
shared.pass('nvim-notify')
