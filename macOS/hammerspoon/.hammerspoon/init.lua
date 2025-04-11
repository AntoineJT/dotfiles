local WEZTERM_BUNDLE_ID = 'com.github.wez.wezterm'
local FIREFOX_BUNDLE_ID = 'org.mozilla.firefox'
local VSCODE_BUNDLE_ID = 'com.microsoft.VSCode'

local AppOpener = require('AppOpener')

hs.loadSpoon('HoldToQuit')

-- Delay CMD+Q, avoiding accidental quits
spoon.HoldToQuit:init()
spoon.HoldToQuit:start()

-- "Dropdown mode" for Wezterm
-- Show/hide Wezterm with OPT+Space
hs.hotkey.bind({'option'}, 'space', function () 
    AppOpener.showHide(WEZTERM_BUNDLE_ID, 1)
end)

-- Show/hide VSCode with OPT+V
hs.hotkey.bind({'option'}, 'v', function ()
    AppOpener.showHide(VSCODE_BUNDLE_ID, 1)
end)

-- Show/hide Firefox with OPT+F
hs.hotkey.bind({'option'}, 'f', function ()
    AppOpener.showHide(FIREFOX_BUNDLE_ID, 2)
end)

-- TODO exclude wezterm from alt-tab
