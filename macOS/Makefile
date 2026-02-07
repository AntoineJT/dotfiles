.PHONY: all delete

all:
	command -v stow >/dev/null 2>&1 || brew install stow
	stow --verbose --no-folding --target=$$HOME --restow */
	cp ../common/wezterm/doom_white_terminal_bg.jpg ~

delete:
	stow --verbose --target=$$HOME --delete */
	rm -f ~/doom_white_terminal_bg.jpg
