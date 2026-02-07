# TODO unify zshrc between macOS & NixOS
# could be done by splitting into different
# zsh scripts for example.

# Aliases
alias lsa="ls -aho --color=always"
alias tree="eza --tree"

# Aliases for overridden commands
alias ocat="$(where cat)"
alias odiff="$(where diff)"
alias ovi="$(where vi)"
alias ovim="$(where vim)"

# Overrides
alias cat="bat --paging=never"
alias diff="riff"
alias vi="nvim"
alias vim="nvim"

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
source $ANTIDOTE_CMD
antidote load

# History settings
# (enforce default over history plugin)
HISTFILE=~/.zsh_history

# Activate mise package manager if present
command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"

# Load starship shell prompt if present
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
