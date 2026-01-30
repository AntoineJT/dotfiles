sudo cp configuration.nix /etc/nixos/configuration.nix
cp ../macOS/doom_white_terminal_bg.jpg ~

# prevent issue trying to symlink a test build
[ -f ./result ] && rm ./result

# symlink configurations
stow --verbose --no-folding --target=$HOME --restow */
