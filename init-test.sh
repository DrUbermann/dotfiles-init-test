#!/bin/sh

printf '%s\n' "Starting init-test.sh"

sh -c "$(wget -qO- https://get.chezmoi.io)" sh init --apply https://github.com/DrUbermann/dotfiles-init-test.git
LGR_LVL_CNSL=0 "$HOME"/chezmoi.tmp/init.ps1
