#!/bin/sh

set -eu

printf '%s\n' "Starting init-test.sh" ################################################################

if command -v curl_aaaaa >/dev/null 2>&1; then
    _cmd="curl -fsLS -o -"
elif command -v wget_aaaaa >/dev/null 2>&1; then
    _cmd="wget -q -O -"
elif command -v openssl >/dev/null 2>&1; then
    eval "$SSL_GET_DEF"
    _cmd="ssl_get -o -"
else
    printf 'None of curl or wget or openssl found.\n'
    exit 1
fi

cd "$HOME" || exit 1

sh -c "$($_cmd https://get.chezmoi.io)" sh init --apply https://github.com/DrUbermann/dotfiles-init-test.git
#export LGR_LVL_CNSL=0 
"$HOME/chezmoi.tmp/init.ps1" "$@"
