#!/usr/bin/env bash
# Generate the Arch Colony package signing key.
#
# Run this ONCE, ever. See docs/decisions/0008-chaine-de-confiance.md.
# GnuPG will prompt for a passphrase — use a strong one and store it in a password
# manager. There is no recovery if it is lost.

set -euo pipefail

KEY_UID="Arch Colony Repository <colony@archcolony.org>"
ROOT="$(dirname "$(realpath "$0")")/.."
KEYRING_DIR="$ROOT/packages/colony-keyring"
REVOCATION="$ROOT/repo/colony-revocation.asc"

if gpg --list-secret-keys "$KEY_UID" &>/dev/null; then
    echo "A secret key for '$KEY_UID' already exists. Refusing to create a second one." >&2
    echo "If you really mean to start over, delete it manually first." >&2
    exit 1
fi

echo "==> Creating the primary certification key (no expiry)"
# --batch keeps gpg off /dev/tty for its own prompts; the passphrase still comes
# from gpg-agent's pinentry, so it is never visible to this script.
gpg --batch --quick-generate-key "$KEY_UID" rsa4096 cert never

FPR=$(gpg --list-secret-keys --with-colons "$KEY_UID" | awk -F: '/^fpr:/ {print $10; exit}')
echo "==> Primary key: $FPR"

# A separate signing subkey is what makes the future migration to an offline primary
# key painless: the subkey can be revoked and replaced without users changing the key
# they trust.
echo "==> Adding a signing subkey (3 years)"
gpg --batch --quick-add-key "$FPR" rsa4096 sign 3y

echo "==> Exporting the public key into the colony-keyring package"
mkdir -p "$KEYRING_DIR"
gpg --export --output "$KEYRING_DIR/colony.gpg" "$FPR"
printf '%s:4:\n' "$FPR" > "$KEYRING_DIR/colony-trusted"
: > "$KEYRING_DIR/colony-revoked"

echo "==> Generating a revocation certificate"
# --gen-revoke is a prompt sequence, not a flag-driven command: confirm, reason
# code 0 (unspecified), empty description terminated by a blank line, confirm.
# Fed on fd 0 so the passphrase still comes from pinentry rather than from here.
printf 'y\n0\n\ny\n' | gpg --no-tty --command-fd 0 --yes --output "$REVOCATION" --gen-revoke "$FPR"

cat <<EOF

Done. Fingerprint: $FPR

Two things to do NOW, before writing any other code:

  1. Back up the private key to an offline medium:

       gpg --export-secret-keys --armor $FPR > /path/to/usb/colony-secret.asc

     Then unplug it. This file is the project. Losing it means every user has to
     re-establish trust by hand.

  2. Move repo/colony-revocation.asc off this machine too — it is the only way to
     announce a compromise, and it is useless if it burns with the key.

Then add to your shell environment so the build scripts find the key:

       export COLONY_SIGNING_KEY=$FPR
EOF
