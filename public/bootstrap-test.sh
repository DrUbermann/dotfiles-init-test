#!/bin/sh

## prompt for password without echoing it
printf 'Password: '
stty -echo
read -r _password
stty echo
printf '\n'

_creds=$(printf ':%s' "$_password" | base64)
#_header="--header Authorization: Basic $_creds"
_url="https://dotfiles-init-test.drubermann.workers.dev/.init_script.sh"

if command -v curl >/dev/null 2>&1; then
    _cmd="curl -fsLS"
elif command -v wget >/dev/null 2>&1; then
  _cmd="wget -q"
else
    printf 'curl or wget not found.\n'
fi
 
 $_cmd --header "Authorization: Basic $_creds" "$_url" | sh
