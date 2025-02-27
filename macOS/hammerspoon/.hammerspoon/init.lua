local Terminal = require('Terminal')

hs.loadSpoon('HoldToQuit')

-- Delay CMD+Q, avoiding accidental quits
spoon.HoldToQuit:init()
spoon.HoldToQuit:start()

-- "Dropdown mode" for Wezterm
-- Show/hide Wezterm with OPT+Space
hs.hotkey.bind({'option'}, 'space', function () 
    Terminal:showHide()
end)

-- TODO exclude wezterm from alt-tab
