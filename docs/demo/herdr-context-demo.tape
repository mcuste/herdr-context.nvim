Output docs/demo/herdr-context-demo.gif

Set FontSize 15
Set Width 1600
Set Height 900
Set TypingSpeed 20ms
Set Theme "Catppuccin Mocha"
Set CursorBlink false

Env HERDR_CONTEXT_DEMO_SESSION "herdr-context-vhs"

Hide
Type "./docs/demo/start-herdr-context-demo.sh"
Enter
Wait+Screen /herdr-context.nvim demo/
Sleep 5s
Type ":lua vim.notify = function() end; pcall(function() require('mini.notify').clear() end)"
Enter
Sleep 1s
Show
Sleep 2s

Type ":HerdrContextSendBuffer"
Sleep 1s
Enter
Wait+Screen /@docs\/demo\/context-example.lua/
Sleep 3s

Ctrl+C
Ctrl+H
Sleep 1s
Type ":HerdrContextSendBuffers"
Sleep 1s
Enter
Wait+Screen /@docs\/demo\/context-helpers.lua/
Sleep 3s

Ctrl+C
Ctrl+H
Sleep 1s
Type "7G"
Type "Vjj"
Sleep 2s
Type ":HerdrContextSendSelection"
Sleep 1s
Enter
Wait+Screen /#L7-9/
Sleep 3s

Ctrl+C
Ctrl+H
Sleep 1s
Ctrl+C
Type "3G0"
Type "f'"
Type "v8l"
Sleep 2s
Type ":HerdrContextSendSelection"
Sleep 1s
Enter
Wait+Screen /#L3-3/
Sleep 3s

Ctrl+C
Hide
Wait+Screen@30s /Claude/
Sleep 1s
Show
Sleep 3s

Ctrl+C
Type ":HerdrContextSendBuffer"
Sleep 1s
Enter
Sleep 2s
Type@200ms "cl"
Sleep 2s
Enter
Wait+Screen /@docs\/demo\/context-example.lua/
Sleep 4s

Hide
Ctrl+C
Ctrl+A
Type "q"
Sleep 2s
