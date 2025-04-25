# Give current TTY to GPG for passphrase prompt
export GPG_TTY=$(tty)

# Aliases
# TODO allow to select brewfiles to use
alias brew-rebuild="brew update && cat ~/.config/brew/Brewfile-* | brew bundle install --file=- --cleanup && brew upgrade"
alias lsa="ls -aho --color=always"
alias run-fork="open -a Fork" # open Fork with env vars
alias tree="eza --tree"

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

# zsh-autosuggestions: Accept autosuggest with ctrl+space
bindkey '^ ' autosuggest-accept
# zsh-history-substring-search: Use up and down arrows to search history
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Load enterprise zshrc if it exists
[ -f ~/.zshrc_enterprise ] && source ~/.zshrc_enterprise

# Move to the specified default directory
[ $(pwd) = $HOME ] && cd $ZSH_STARTUP_DIR

# Load zsh plugins
source $(brew --prefix)/opt/antidote/share/antidote/antidote.zsh
antidote load

# History settings
# (enforce default over history plugin)
HISTFILE=~/.zsh_history

# Load starship shell prompt
eval "$(starship init zsh)"
