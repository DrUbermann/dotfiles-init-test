#!/bin/sh

## prompt for password without echoing it
printf 'Password: ' > /dev/tty
stty -echo < /dev/tty
read -r _password < /dev/tty
stty echo < /dev/tty
printf '\n' > /dev/tty

_creds=$(printf ':%s' "$_password" | openssl enc -base64 | tr -d '\n')
_url="https://dotfiles-init-test.drubermann.workers.dev/.init_script.sh"

if command -v curla >/dev/null 2>&1; then
    _cmd="curl -fsLS -o -"
elif command -v wgeta >/dev/null 2>&1; then
    _cmd="wget -q -O -"
elif command -v openssl >/dev/null 2>&1; then
    . ../chezmoi.tmp/executable_ssl_get.sh
    _cmd="ssl_get -o -"
else
    printf 'curl or wget or openssl not found.\n'
fi

$_cmd --header "Authorization: Basic $_creds" "$_url" | sh
