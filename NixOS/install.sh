sudo cp configuration.nix /etc/nixos/configuration.nix
cp ../common/wezterm/doom_white_terminal_bg.jpg ~
cp ./.config/VSCodium/product.json ~/.config/VSCodium

# prevent issue trying to symlink a test build
[ -f ./result ] && rm ./result

# symlink configurations
# WezTerm ne suit pas les symlinks pour son image de fond : elle est copiée dans
# $HOME, donc exclue du stow. --ignore matche des basenames, pas des chemins.
stow_it() { stow --verbose --no-folding --target=$HOME --ignore='doom_white_terminal_bg\.jpg' --restow */; }
stow_it
(cd ../common && stow_it)
