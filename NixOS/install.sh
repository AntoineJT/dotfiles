sudo cp configuration.nix /etc/nixos/configuration.nix
cp ../common/wezterm/doom_white_terminal_bg.jpg ~
cp ./.config/VSCodium/product.json ~/.config/VSCodium

# prevent issue trying to symlink a test build
[ -f ./result ] && rm ./result

# symlink configurations
stow --verbose --no-folding --target=$HOME --restow */
