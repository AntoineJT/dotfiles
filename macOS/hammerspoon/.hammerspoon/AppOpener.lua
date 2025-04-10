module = {}

local function moveToCurrentScreen(appWindow)
    screen = hs.mouse.getCurrentScreen()
    if screen == nil then
        hs.alert.show('Error while getting current screen')
        return
    end
    appWindow:moveToScreen(screen)
end

local function tryToMaxWindow(hs, window)
    if window == nil then
        hs.alert.show('App window not found')
    end
    window:maximize()
end

function module.showHide(appBundleId)
    local app = hs.application.get(appBundleId)

    -- if app not opened yet, open it
    if app == nil then
        app = hs.application.open(appBundleId)
        if app == nil then
            hs.alert.show('App not found')
            return
        end
    end

    local window = app:mainWindow()
    if window ~= nil then
        -- app already opened, toggle visibility
        if app:isFrontmost() then
            app:hide()
        else
            moveToCurrentScreen(window)
            window:maximize()
            app:activate()
        end
        return
    end

    -- app not opened, wait for 1s before trying to maximize
    hs.timer.doAfter(1, function ()
        tryToMaxWindow(hs, app:mainWindow())
    end)
end

return module
