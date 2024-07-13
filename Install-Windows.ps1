# TODO configure terminal to use nerdfonts
# TODO configure terminal for quake mode using ² key as trigger
# TODO ask for terminal root dir and set it in the environment variable
# TODO ask for image to use for winfetch
# TODO copy files in <sysname> to home directory

# install git (required for NerdFonts)
Write-Output "Installing Git..."
winget install Git.Git

# install nerdfonts
Write-Output "Installing NerdFonts version of Cascadia Code & Cascadia Mono..."
cd cache
if (!(Test-Path -Path ./nerd-fonts)) {
    Write-Output "NerdFonts git already cloned. If you want to update it, do it manually."
    git clone --depth 1 https://github.com/ryanoasis/nerd-fonts nerd-fonts
}
cd nerd-fonts
./install.ps1 CascadiaCode, CascadiaMono
cd ../..

# install Oh My Posh
winget install JanDeDobbeleer.OhMyPosh -s winget

# install Terminal-Icons
Install-Module -Name Terminal-Icons -Scope CurrentUser

# install winfetch
Install-Script -Name winfetch -Scope CurrentUser
