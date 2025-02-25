.PHONY: all delete

all:
	command -v stow >/dev/null 2>&1 || brew install stow
	stow --verbose --target=$$HOME --restow */

delete:
	stow --verbose --target=$$HOME --delete */
