# winfetch, decorate with some data on startup
winfetch

# add terminal icons to ls/dir commands
Import-Module -Name Terminal-Icons

# oh my posh with half-life theme
oh-my-posh init pwsh --config $Env:POSH_THEMES_PATH/half-life.omp.json | Invoke-Expression

# change directory to terminal root dir
Set-Location -Path $Env:PS_STARTUP_DIR
