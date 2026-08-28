local shared = dofile('tests/compat/shared.lua')

require('mini.notify').setup()
MiniNotify.add(shared.message, 'WARN')

local collected = shared.wait_for_collected()
local body = shared.assert_section(collected, 'mini.notify notifications')
shared.assert_label(body, '[WARN]')
shared.pass('mini.notify')
