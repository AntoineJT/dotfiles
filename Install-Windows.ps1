# todo install nerdfonts
# todo configure terminal to use nerdfonts
# todo configure terminal for quake mode using ² key as trigger
# todo ask for terminal root dir and set it in the environment variable

# install Oh My Posh
winget update
winget install JanDeDobbeleer.OhMyPosh -s winget

# install Terminal-Icons
Install-Module -Name Terminal-Icons -Scope CurrentUser

# install winfetch
Install-Script -Name winfetch -Scope CurrentUser
