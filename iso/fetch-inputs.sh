#!/usr/bin/env bash
# Download the build inputs iso/pins.env names, at exactly the pinned commits.
#
#   ./iso/fetch-inputs.sh DIR
#
# Leaves DIR/archinstall (a checkout of the pinned commit) and DIR/themes.json
# (checked against its pinned sha256). DIR must not exist yet: reusing an old
# download would build from whatever it happens to hold.

set -euo pipefail

HERE="$(dirname "$(realpath "$0")")"
# shellcheck source=iso/pins.env
. "$HERE/pins.env"

DIR=${1:?usage: fetch-inputs.sh DIR}
[[ ! -e $DIR ]] || { echo "$DIR already exists" >&2; exit 1; }
mkdir -p "$DIR"

echo "==> archinstall at $ARCHINSTALL_COMMIT"
# A fetch by commit rather than a clone of a branch or tag: the commit id is the
# content's own hash, so what lands here is what the pin says or nothing.
git init -q "$DIR/archinstall"
git -C "$DIR/archinstall" fetch -q --depth 1 \
	https://github.com/archlinux/archinstall.git "$ARCHINSTALL_COMMIT"
git -C "$DIR/archinstall" checkout -q --detach FETCH_HEAD

echo "==> themes.json from Project-Colony-Resources at $RESOURCES_COMMIT"
curl -fsSL --proto '=https' -o "$DIR/themes.json" \
	"https://raw.githubusercontent.com/Project-Colony/Project-Colony-Resources/$RESOURCES_COMMIT/generated/themes.json"
( cd "$DIR" && echo "$THEMES_SHA256  themes.json" | sha256sum --check --quiet --strict - ) \
	|| { echo "themes.json does not match THEMES_SHA256 in iso/pins.env" >&2; exit 1; }
