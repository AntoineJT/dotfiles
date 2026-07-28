.PHONY: all delete

STOW := stow --verbose --no-folding --target=$$HOME

# Packages de ../common à stow directement : ceux que ce dossier ne re-exporte
# pas déjà par symlink (git, starship, wezterm, zsh), sinon stow verrait la même
# cible déclarée deux fois et abandonnerait. Un nouveau package dans common/ est
# donc installé sans rien toucher ici.
COMMON := $(filter-out $(patsubst %/,%,$(wildcard */)),\
          $(notdir $(patsubst %/,%,$(wildcard ../common/*/))))

all:
	command -v stow >/dev/null 2>&1 || brew install stow
	$(STOW) --restow */
	$(if $(COMMON),cd ../common && $(STOW) --restow $(COMMON))
	cp ../common/wezterm/doom_white_terminal_bg.jpg ~

delete:
	stow --verbose --target=$$HOME --delete */
	$(if $(COMMON),cd ../common && stow --verbose --target=$$HOME --delete $(COMMON))
	rm -f ~/doom_white_terminal_bg.jpg
