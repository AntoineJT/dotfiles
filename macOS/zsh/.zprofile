eval "$(/opt/homebrew/bin/brew shellenv)"

# load another profile, useful
# for private configuration that
# should not be published publicly
# or testing
if [ -n $ZSH_PROFILE_EXT ]; then
    source $ZSH_PROFILE_EXT
fi

# change root directory when
# loading profile in home folder
# else ignore it
if [ $(pwd) = $HOME ]; then
    cd $ZSH_STARTUP_DIR
fi
