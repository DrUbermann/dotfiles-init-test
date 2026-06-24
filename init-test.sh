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
    #### Create fake wget so get.chezmoi.io script will use ssl_get instead
    mkdir -p "${TMPDIR:-/tmp}/fakepath"
    cat << 'EOF' > "${TMPDIR:-/tmp}/fakepath/wget"
#!/bin/sh

eval "$SSL_GET_DEF"

header=""
output=""
url=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        (-q) shift ;;
        (-O) output="$2"; shift 2 ;;
        (--header) header="$2"; shift 2 ;;
        (*) url="$1"; shift ;;
    esac
done

if [ -n "$header" ]; then
    ssl_get --header "$header" "$url" > "$output"
else
    ssl_get "$url" > "$output"
fi
EOF
    chmod +x "${TMPDIR:-/tmp}/fakepath/wget"
    export PATH="${TMPDIR:-/tmp}/fakepath:$PATH"
    ls
    wget -q -O test.tmp https://get.chezmoi.io
else
    printf 'None of curl or wget or openssl found.\n'
    exit 1
fi

cd "$HOME" || exit 1

sh -c "$($_cmd https://get.chezmoi.io)" sh init --apply https://github.com/DrUbermann/dotfiles-init-test.git
#export LGR_LVL_CNSL=0 
"$HOME/chezmoi.tmp/init.ps1" "$@"
