#!/bin/sh

set -eu

printf '%s\n' "Starting init-test.sh" ################################################################

if command -v curl_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >/dev/null 2>&1; then
    _cmd="curl -fsLS -o -"
elif command -v wget >/dev/null 2>&1; then
    _cmd="wget -q -O -"
elif command -v openssl >/dev/null 2>&1; then
    eval "$SSL_GET_DEF"
    _cmd="ssl_get -q -o -"
    #### Create fake wget so get.chezmoi.io script will use ssl_get instead
    #### Source: Gemini 3.1 Pro
    mkdir -p "${TMPDIR:-/tmp}/fakepath"
    cat << 'EOF' > "${TMPDIR:-/tmp}/fakepath/wget"
    #!/bin/sh
    ## Ensure the parent's environment variable is available
    eval "$SSL_GET_DEF"
    hcount=0
    out=""
    url=""
    quiet=""
    ## Robustly parse standard and squished wget arguments
    while [ "$#" -gt 0 ]; do
        case "$1" in
            (-q|--quiet)
                quiet="-q"; shift ;;
            (-S|--server-response) 
                shift ;;
            (-O) 
                out="$2"; shift 2 ;;
            (-qO) 
                quiet="-q"; out="$2"; shift 2 ;;
            (-O*) 
                out="${1#*-O}"; shift ;;
            (-qO*) 
                quiet="-q"; out="${1#*-qO}"; shift ;;
            (--header)
                hcount=$((hcount + 1))
                eval "h${hcount}=\"\$2\""
                shift 2 ;;
            (--header=*)
                hcount=$((hcount + 1))
                eval "h${hcount}=\"\${1#*=}\""
                shift ;;
            (-*) 
                ## Ignore any other wget flags
                shift ;;
            (*) 
                url="$1"; shift ;;
        esac
    done
    ## Safely reconstruct the arguments for ssl_get using positionals
    set --
    if [ -n "$quiet" ]; then
        set -- "$@" "$quiet"
    fi
    if [ -n "$out" ]; then
        set -- "$@" "-o" "$out"
    fi
    ## Re-inject the parsed headers
    i=1
    while [ "$i" -le "$hcount" ]; do
        eval "val=\"\$h${i}\""
        set -- "$@" "--header" "$val"
        i=$((i + 1))
    done
    if [ -n "$url" ]; then
        set -- "$@" "$url"
    fi
    ssl_get "$@"
EOF
    chmod +x "${TMPDIR:-/tmp}/fakepath/wget"
    export PATH="${TMPDIR:-/tmp}/fakepath:$PATH"
else
    printf 'None of curl or wget or openssl found.\n'
    exit 1
fi

cd "$HOME" || exit 1

sh -c "$($_cmd https://get.chezmoi.io)" sh init --apply https://github.com/DrUbermann/dotfiles-init-test.git

#export LGR_LVL_CNSL=0 
"$HOME/chezmoi.tmp/init.ps1" "$@"
