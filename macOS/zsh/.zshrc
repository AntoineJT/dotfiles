# Give current TTY to GPG for passphrase prompt
export GPG_TTY=$(tty)

# Aliases
# TODO allow to select brewfiles to use
alias brew-rebuild="brew update && cat ~/.config/brew/Brewfile-* | brew bundle install --file=- --cleanup && brew upgrade"
alias run-fork="open -a Fork" # open Fork with env vars

# Overrides
alias cat="bat --paging=never"
alias diff="riff"
alias vi="nvim"
alias vim="nvim"

# Aliases for overridden commands
alias ocat="/bin/cat"
alias odiff="/usr/bin/diff"
alias ovi="/usr/bin/vi"
alias ovim="/usr/bin/vim"

# Accept autosuggest with ctrl+space
bindkey '^ ' autosuggest-accept

# Load enterprise zshrc if it exists
[ -f ~/.zshrc_enterprise ] && source ~/.zshrc_enterprise

# Move to the specified default directory
[ $(pwd) = $HOME ] && cd $ZSH_STARTUP_DIR

# Load zsh plugins
source $(brew --prefix)/opt/antidote/share/antidote/antidote.zsh
antidote load

# Load starship shell prompt
eval "$(starship init zsh)"
