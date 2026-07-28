.PHONY: all delete

# WezTerm ne suit pas les symlinks pour son image de fond : elle est copiée dans
# $HOME, donc exclue du stow. --ignore matche des basenames, pas des chemins.
STOW := stow --verbose --no-folding --target=$$HOME --ignore='doom_white_terminal_bg\.jpg'

all:
	command -v stow >/dev/null 2>&1 || brew install stow
	$(STOW) --restow */
	cd ../common && $(STOW) --restow */
	cp ../common/wezterm/doom_white_terminal_bg.jpg ~

delete:
	$(STOW) --delete */
	cd ../common && $(STOW) --delete */
	rm -f ~/doom_white_terminal_bg.jpg
