# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="arrow" # See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
plugins=(git dotenv docker kubectl common-aliases helm jira otp colorize)
source $ZSH/oh-my-zsh.sh

# Give current TTY to GPG for passphrase prompt
export GPG_TTY=$(tty)

# Aliases
# TODO allow to select brewfiles to use
alias brew-rebuild="brew update && cat ~/.config/brew/Brewfile-* | brew bundle install --file=- --cleanup && brew upgrade"

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
