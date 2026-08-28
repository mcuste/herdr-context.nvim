local shared = dofile('tests/compat/shared.lua')

require('snacks').setup({ notifier = { enabled = true } })
Snacks.notifier.notify(shared.message, 'warn', { title = shared.title })

local collected = shared.wait_for_collected()
local body = shared.assert_section(collected, 'Snacks.notifier notifications')
shared.assert_label(body, '[WARN ' .. shared.title .. ']')
shared.pass('Snacks.notifier')
