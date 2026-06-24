#!/bin/sh

set -eu

## prompt for password without echoing it
if ! tty > /dev/null 2>&1; then
    printf '%s\n' "Error: no controlling terminal for user inputs." >&2
    exit 1
fi
printf '\nPassword: ' > /dev/tty
stty -echo < /dev/tty
trap 'stty echo < /dev/tty' EXIT INT TERM
read -r _password < /dev/tty
stty echo < /dev/tty
printf '\n' > /dev/tty

_creds=$(printf ':%s' "$_password" | openssl enc -base64 | tr -d '\n')
_url="https://dotfiles-init-test.drubermann.workers.dev/init-test.sh"

if command -v curl_aaaaa >/dev/null 2>&1; then
    _cmd="curl -fsLS -o -"
elif command -v wget_aaaaa >/dev/null 2>&1; then
    _cmd="wget -q -O -"
elif command -v openssl >/dev/null 2>&1; then
#     SSL_GET_DEF=$(cat << 'EOF'
#     ssl_get() {
#         _sg_out="-"
#         _sg_url=""
#         _sg_hcount=0
#         _sg_max=10
#         _sg_meta="${TMPDIR:-/tmp}/_sg_$$.tmp"

#         while [ $# -gt 0 ]; do
#             case "$1" in
#                 --output|-o)
#                     _sg_out="$2"; shift 2 ;;
#                 --header|-H)
#                     _sg_hcount=$((_sg_hcount + 1))
#                     eval "_sg_h${_sg_hcount}=\"\$2\""
#                     shift 2 ;;
#                 --)
#                     _sg_url="$2"; shift 2 ;;
#                 -*)
#                     printf 'ssl_get: unknown option: %s\n' "$1" >&2
#                     return 1 ;;
#                 *)
#                     _sg_url="$1"; shift ;;
#             esac
#         done

#         [ -z "$_sg_url" ] && { printf 'ssl_get: no URL\n' >&2; return 1; }

#         _sg_dest="$_sg_out"
#         [ "$_sg_out" = "-" ] && _sg_dest="/dev/stdout"

#         _sg_redirects=0
#         _sg_first=1

#         while [ "$_sg_redirects" -lt "$_sg_max" ]; do
#             _sg_host=$(printf '%s' "$_sg_url" | sed 's|^https://||; s|/.*||')
#             _sg_path=$(printf '%s' "$_sg_url" | sed "s|^https://${_sg_host}||")
#             _sg_path="${_sg_path:-/}"

#             {
#                 printf 'GET %s HTTP/1.0\r\n' "$_sg_path"
#                 printf 'Host: %s\r\n'        "$_sg_host"
#                 if [ "$_sg_first" -eq 1 ]; then
#                     _sg_i=1
#                     while [ "$_sg_i" -le "$_sg_hcount" ]; do
#                         eval "printf '%s\r\n' \"\$_sg_h${_sg_i}\""
#                         _sg_i=$((_sg_i + 1))
#                     done
#                 fi
#                 printf 'User-Agent: ssl_get\r\n'
#                 printf 'Connection: close\r\n'
#                 printf '\r\n'
#             } | openssl s_client -quiet \
#                                 -connect "${_sg_host}:443" \
#                                 -servername "$_sg_host" 2>/dev/null \
#             | {
#                 _p_status=""
#                 _p_location=""
#                 while IFS= read -r _p_line; do
#                     _p_line=$(printf '%s' "$_p_line" | tr -d '\r')
#                     [ -z "$_p_line" ] && break
#                     if [ -z "$_p_status" ]; then
#                         _p_status=$(printf '%s' "$_p_line" | awk '{print $2}')
#                     fi
#                     _p_key=$(printf '%s' "$_p_line" \
#                             | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
#                     if [ "$_p_key" = "location" ]; then
#                         _p_location=$(printf '%s' "$_p_line" \
#                                     | cut -d: -f2- | sed 's/^ *//')
#                     fi
#                 done
#                 printf '%s\n%s\n' "$_p_status" "$_p_location" > "$_sg_meta"
#                 if [ "$_p_status" = "200" ]; then
#                     cat
#                 else
#                     cat > /dev/null
#                 fi
#             } > "$_sg_dest"

#             _sg_status=$(sed -n '1p' "$_sg_meta")
#             _sg_location=$(sed -n '2p' "$_sg_meta")
#             rm -f "$_sg_meta"

#             case "$_sg_status" in
#                 200)
#                     [ "$_sg_out" != "-" ] && \
#                         printf 'ssl_get: saved to %s\n' "$_sg_out" >&2
#                     return 0
#                     ;;
#                 301|302|307|308)
#                     [ -z "$_sg_location" ] && {
#                         printf 'ssl_get: redirect with no Location header\n' >&2
#                         return 1
#                     }
#                     printf 'ssl_get: redirect -> %s\n' "$_sg_location" >&2
#                     _sg_url="$_sg_location"
#                     _sg_first=0
#                     ;;
#                 "")
#                     printf 'ssl_get: no response (TLS or network failure?)\n' >&2
#                     return 1
#                     ;;
#                 *)
#                     printf 'ssl_get: HTTP %s\n' "$_sg_status" >&2
#                     return 1
#                     ;;
#             esac

#             _sg_redirects=$((_sg_redirects + 1))
#         done

#         printf 'ssl_get: too many redirects\n' >&2
#         return 1
#         }
# EOF
#     )

    SSL_GET_DEF=$(cat << 'EOF'
    ssl_get() {
        while [ $# -gt 0 ]; do
            case "$1" in
                *)
                    _x="$1"; shift ;;
            esac
        done
    }
EOF
    )

    #eval "$SSL_GET_DEF"
    #ssl_get
    #echo here
    #_cmd="ssl_get -o -"
else
    printf 'None of curl or wget or openssl found.\n'
    exit 1
fi

sh -c "$($_cmd --header "Authorization: Basic $_creds" "$_url")" sh "$@"
