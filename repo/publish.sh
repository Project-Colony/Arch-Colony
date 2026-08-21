#!/usr/bin/env bash
# Assemble the signed [colony] database and publish it as a GitHub release.
#
# This PUBLISHES. Everything it uploads becomes publicly downloadable and will be
# installed by every Arch Colony machine. Read what is in repo/out/ before running.

set -euo pipefail

ROOT="$(dirname "$(realpath "$0")")/.."
OUT="$ROOT/repo/out"
REPO_NAME=colony
TAG=repo
GH_REPO="${COLONY_GH_REPO:-Project-Colony/Arch-Colony}"

: "${COLONY_SIGNING_KEY:?not set — run repo/genkey.sh first, then export it}"
command -v gh >/dev/null || { echo "gh missing: pacman -S github-cli" >&2; exit 1; }

cd "$OUT"

shopt -s nullglob
pkgs=(*.pkg.tar.zst)
shopt -u nullglob
(( ${#pkgs[@]} )) || { echo "nothing in $OUT — run repo/build.sh first" >&2; exit 1; }

echo "==> building the signed database"
rm -f "$REPO_NAME".db* "$REPO_NAME".files*
repo-add --sign --key "$COLONY_SIGNING_KEY" --new --prevent-downgrade \
	"$REPO_NAME.db.tar.zst" "${pkgs[@]}"

# repo-add leaves colony.db and colony.files as symlinks. Release assets cannot be
# symlinks, and pacman fetches exactly those names, so materialise them.
#
# FOUR names, not two: `repo-add --sign` symlinks colony.db.sig ->
# colony.db.tar.zst.sig as well. Handling them in pairs — remove the link, copy
# the target, then copy the target's .sig over the link's .sig — asks cp to copy
# a file onto itself, because the destination is still a symlink pointing at the
# source. cp refuses, set -e fires, and the script dies before uploading
# anything. That is why this repository has been HTTP 404 since it was written:
# not a hosting problem, a bug three lines long.
#
# Each name is handled on its own, so a half-finished earlier run recovers
# instead of skipping the leftovers.
for name in "$REPO_NAME.db" "$REPO_NAME.db.sig" "$REPO_NAME.files" "$REPO_NAME.files.sig"; do
	[[ -L "$name" ]] || continue
	target=$(readlink "$name")
	rm -f "$name"
	cp -f "$target" "$name"
done

# Deduplicated, because these globs overlap: *.sig also matches colony.db.sig
# and colony.db.tar.zst.sig, which "$REPO_NAME".db* matches too. Passing a name
# twice makes the second upload fail with HTTP 422 "ReleaseAsset.name already
# exists" — after the release has been created and some assets are already up,
# so the repository is left half-published rather than untouched.
mapfile -t assets < <(printf '%s\n' \
	*.pkg.tar.zst *.sig "$REPO_NAME".db* "$REPO_NAME".files* | sort -u)

echo "==> the following will be published to $GH_REPO (tag: $TAG)"
ls -1sh -- "${assets[@]}"
read -rp "publish? [y/N] " answer
[[ $answer == [yY] ]] || { echo "aborted"; exit 1; }

if ! gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
	gh release create "$TAG" --repo "$GH_REPO" \
		--title "[colony] repository" \
		--notes "Rolling pacman repository for Arch Colony. Assets are replaced in place; there is no per-release history here."
fi

gh release upload "$TAG" --repo "$GH_REPO" --clobber -- "${assets[@]}"

# Prune what repo/out no longer has. repo/build.sh deliberately removes older
# builds of a package locally; without the same pruning here the release keeps
# every version ever published. The database stops referencing them, so pacman
# will not install them by name — but they stay downloadable and signed, and a
# stale signed package left lying about is precisely what --prevent-downgrade
# exists to stop. Deletion comes after the upload, so a failure mid-run leaves
# the repository over-complete rather than incomplete.
stale=()
while IFS= read -r existing; do
	[[ -n $existing ]] || continue
	printf '%s\n' "${assets[@]}" | grep -qxF -- "$existing" || stale+=("$existing")
done < <(gh release view "$TAG" --repo "$GH_REPO" --json assets --jq '.assets[].name')

if (( ${#stale[@]} )); then
	echo "==> removing ${#stale[@]} superseded asset(s)"
	for s in "${stale[@]}"; do
		echo "    $s"
		gh release delete-asset "$TAG" "$s" --repo "$GH_REPO" --yes
	done
fi

echo
echo "Published. On a test machine:"
echo "  pacman-key --recv-keys $COLONY_SIGNING_KEY && pacman-key --lsign-key $COLONY_SIGNING_KEY"
echo "  add [colony] to pacman.conf, then: pacman -Sy colony-mirrorlist"
