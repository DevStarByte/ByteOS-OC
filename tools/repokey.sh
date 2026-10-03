#!/bin/sh
# Make the key pair that signs the package databases (run once, on a PC).
#   tools/repokey.sh [private-key-file]
# The private key (default ~/.config/byteos/repo-key.pem) stays on your PC:
# never commit it. The public key is written to etc/pacman.d/byteos.pub,
# which ByteOS ships and pacman checks the signatures against.
set -e
key=${1:-$HOME/.config/byteos/repo-key.pem}
here=$(dirname "$0")/..
if [ -e "$key" ]; then echo "$key already exists; not overwriting it" >&2; exit 1; fi
mkdir -p "$(dirname "$key")"
umask 077
openssl ecparam -name prime256v1 -genkey -noout -out "$key"
mkdir -p "$here/etc/pacman.d"
openssl ec -in "$key" -pubout -outform DER 2>/dev/null | base64 -w 64 > "$here/etc/pacman.d/byteos.pub"
echo "private key: $key   (back it up; anyone with it can sign packages)"
echo "public key:  etc/pacman.d/byteos.pub"
