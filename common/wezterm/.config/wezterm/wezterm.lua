local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.color_scheme = 'Londontube (light) (terminal.sexy)'
config.colors = {
    tab_bar = {
        inactive_tab = {
            bg_color = "#f0f0f0",
            fg_color = "#000000",
        },
        active_tab = {
            bg_color = "#0f0f0f",
            fg_color = "#ffffff",
        },
    },
    -- Londontube (light) (terminal.sexy) colors
    ansi = {
        "#231f20",
        "#ee2e24",
        "#00853e",
        "#ffaa04", -- darker yellow, increase readability with my bg image
        "#009ddc",
        "#98005d",
        "#85cebc",
        "#d9d8d8",
    },
    brights = {
        "#737171",
        "#ee2e24",
        "#00853e",
        "#ffaa04", -- darker yellow, increase readability with my bg image
        "#009ddc",
        "#98005d",
        "#85cebc",
        "#ffffff",
    }
}

config.font = wezterm.font('FiraCode Nerd Font Mono')
config.font_size = 14

config.window_decorations = "RESIZE"
config.hide_tab_bar_if_only_one_tab = true
config.tab_bar_at_bottom = true

-- Send composed key using left alt (ex: write a pipe)
config.send_composed_key_when_left_alt_is_pressed = true
config.send_composed_key_when_right_alt_is_pressed = false

-- Set background image
config.window_background_image = os.getenv('HOME') .. '/doom_white_terminal_bg.jpg'

config.keys = {
    {key="b", mods="OPT", action=wezterm.action.EmitEvent('toggle-background')},
}

-- Toggle background configuration between
-- doom "wallpaper" & white background
local function toggle_background(window, pane)
    local overrides = window:get_config_overrides() or {}
    if overrides.window_background_opacity then
        window:set_config_overrides(nil)
    else
        overrides.window_background_image = ""
        overrides.window_background_opacity = 1
        overrides.colors = config.colors or {}
        overrides.colors.background = "white"
        window:set_config_overrides(overrides)
    end
end

wezterm.on('toggle-background', toggle_background)

return config
