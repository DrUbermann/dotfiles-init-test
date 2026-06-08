#!/bin/sh
echo starting
## prompt for password without echoing it
printf 'Password: ' > /dev/tty
stty -echo < /dev/tty
read -r _password < /dev/tty
stty echo < /dev/tty
printf '\n' > /dev/tty

_creds=$(printf ':%s' "$_password" | base64)
#_header="--header Authorization: Basic $_creds"
_url="https://dotfiles-init-test.drubermann.workers.dev/.init_script.sh"
echo ok
if command -v curl >/dev/null 2>&1; then
    _cmd="curl -fsLS"
elif command -v wget >/dev/null 2>&1; then
  _cmd="wget -q"
else
    printf 'curl or wget not found.\n'
fi
echo $_cmd --header "Authorization: Basic $_creds" "$_url"
wget -q --header "Authorization: Basic $_creds" "$_url"
