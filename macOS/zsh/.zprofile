eval "$(/opt/homebrew/bin/brew shellenv)"

# change root directory when
# loading profile in home folder
# else ignore it
if [ $(pwd) = $HOME ]; then
    cd $ZSH_STARTUP_DIR
fi
