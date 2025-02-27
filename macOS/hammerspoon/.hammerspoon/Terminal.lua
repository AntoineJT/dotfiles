module = {}

local WEZTERM_BUNDLE_ID = 'com.github.wez.wezterm'

local function moveToCurrentScreen(appWindow)
    screen = hs.mouse.getCurrentScreen()
    if screen == nil then
        hs.alert.show('Error while getting current screen')
        return
    end
    appWindow:moveToScreen(screen)
end

local function tryToMaxWindow(hs, window)
    window:maximize()
    if window == nil then
        hs.alert.show('Wezterm window not found')
    end
end

function module.showHide()
    local wezterm = hs.application.get(WEZTERM_BUNDLE_ID)

    -- if wezterm not opened yet, open it
    if wezterm == nil then
        wezterm = hs.application.open(WEZTERM_BUNDLE_ID)
        if wezterm == nil then
            hs.alert.show('Wezterm not found')
            return
        end
    end

    local window = wezterm:mainWindow()
    if window ~= nil then
        -- wezterm already opened, toggle visibility
        if wezterm:isFrontmost() then
            wezterm:hide()
        else
            moveToCurrentScreen(window)
            window:maximize()
            wezterm:activate()
        end
        return
    end

    -- wezterm not opened, wait for 1s before trying to maximize
    hs.timer.doAfter(1, function ()
        tryToMaxWindow(hs, wezterm:mainWindow())
    end)
end

return module
