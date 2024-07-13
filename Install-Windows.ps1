# TODO ask for terminal root dir and set it in the environment variable
# TODO ask for image to use for winfetch
# TODO copy files in <sysname> to home directory

$WINTERM_QUAKE_MODE_KEY = "²"
$WINTERM_SETTINGS_PATH = "$Env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

# install git (required for NerdFonts)
Write-Output "Installing Git..."
winget install Git.Git

# install nerdfonts
Write-Output "Installing NerdFonts version of Cascadia Code & Cascadia Mono..."
Set-Location cache
if (!(Test-Path -Path ./nerd-fonts)) {
    git clone --depth 1 https://github.com/ryanoasis/nerd-fonts nerd-fonts
} else {
    Write-Output "NerdFonts git already cloned. If you want to update it, do it manually."
}
Set-Location nerd-fonts
./install.ps1 CascadiaCode, CascadiaMono
Set-Location ../..

# install Oh My Posh
Write-Output "Installing Oh My Posh..."
winget install JanDeDobbeleer.OhMyPosh -s winget

# install Terminal-Icons
Write-Output "Installing Terminal Icons..."
Install-Module -Name Terminal-Icons -Scope CurrentUser

# install winfetch
Write-Output "Installing winfetch..."
Install-Script -Name winfetch -Scope CurrentUser

# configure windows terminal
Write-Output "Configuring Windows Terminal..."
$settingsJson = Get-Content $WINTERM_SETTINGS_PATH -Raw | ConvertFrom-Json
# set NerdFonts' Cascadia Code as Windows Terminal font
$settingsJson.profiles.defaults = @{
    "font" = @{
        "face" = "CaskaydiaCove Nerd Font Mono"
    }
}
# setup quake mode activation on given key press
$settingsJson.actions += @{
    "command" = @{
        "action" = "globalSummon"
        "name" = "_quake"
    }
    "keys" = $WINTERM_QUAKE_MODE_KEY
}
$settingsJson | ConvertTo-Json -Depth 32 | Set-Content $WINTERM_SETTINGS_PATH
