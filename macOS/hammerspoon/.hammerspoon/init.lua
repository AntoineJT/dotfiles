local WEZTERM_BUNDLE_ID = 'com.github.wez.wezterm'
local FIREFOX_BUNDLE_ID = 'org.mozilla.firefox'

local AppOpener = require('AppOpener')

hs.loadSpoon('HoldToQuit')

-- Delay CMD+Q, avoiding accidental quits
spoon.HoldToQuit:init()
spoon.HoldToQuit:start()

-- "Dropdown mode" for Wezterm
-- Show/hide Wezterm with OPT+Space
hs.hotkey.bind({'option'}, 'space', function () 
    AppOpener.showHide(WEZTERM_BUNDLE_ID)
end)

-- Show/hide Firefox with OPT+F
hs.hotkey.bind({'option'}, 'f', function ()
    AppOpener.showHide(FIREFOX_BUNDLE_ID)
end)

-- TODO exclude wezterm from alt-tab
