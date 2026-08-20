#!/usr/bin/env bash
# Build packages in a clean chroot and sign them.
#
#   ./repo/build.sh                     build everything under packages/
#   ./repo/build.sh colony-mirrorlist   build one
#
# Output lands in repo/out/, ready for repo/publish.sh.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
OUT="$ROOT/repo/out"

: "${COLONY_SIGNING_KEY:?not set — run repo/genkey.sh first, then export it}"

command -v pkgctl >/dev/null || { echo "pkgctl missing: pacman -S devtools" >&2; exit 1; }

mkdir -p "$OUT"

pkgs=("$@")
if (( ${#pkgs[@]} == 0 )); then
	mapfile -t pkgs < <(cd "$ROOT/packages" && find . -mindepth 2 -maxdepth 2 -name PKGBUILD -printf '%h\n' | sed 's|^\./||' | sort)
fi

(( ${#pkgs[@]} )) || { echo "no packages found under packages/" >&2; exit 1; }

for p in "${pkgs[@]}"; do
	dir="$ROOT/packages/$p"
	[[ -f "$dir/PKGBUILD" ]] || { echo "no PKGBUILD in $dir" >&2; exit 1; }

	echo "==> building $p"
	# A clean chroot, so the result does not depend on whatever happens to be
	# installed on this machine.
	( cd "$dir" && pkgctl build --clean )

	shopt -s nullglob
	built=("$dir"/*.pkg.tar.zst)
	shopt -u nullglob
	(( ${#built[@]} )) || { echo "$p produced no package" >&2; exit 1; }

	# Debug packages belong in a separate repository, not in the one every user
	# installs from. Drop them rather than shipping symbols to everyone.
	keep=()
	for f in "${built[@]}"; do
		case $(basename "$f") in
			*-debug-*) rm -f "$f" ;;
			*) keep+=("$f") ;;
		esac
	done
	built=("${keep[@]}")

	for f in "${built[@]}"; do
		# Drop older builds of the same package first. Without this a rebuild leaves
		# both versions in repo/out, repo-add indexes what it finds, and publish.sh
		# uploads *.pkg.tar.zst unfiltered — so the stale build ships too. Observed
		# after bumping colony-mirrorlist to pkgrel 2.
		#
		# The stem is the filename minus pkgver-pkgrel-arch, which is unambiguous
		# because an Arch pkgver may not contain a dash.
		base=$(basename "$f")
		stem=${base%-*-*-*.pkg.tar.zst}
		rm -f "$OUT/$stem"-*-*-*.pkg.tar.zst "$OUT/$stem"-*-*-*.pkg.tar.zst.sig

		echo "==> signing $base"
		gpg --detach-sign --no-armor --local-user "$COLONY_SIGNING_KEY" --yes "$f"
		mv -f "$f" "$f.sig" "$OUT/"
	done
done

echo
echo "Built into $OUT:"
# Not `ls | xargs basename` — the repository path contains a space.
for f in "$OUT"/*.pkg.tar.zst; do
	[[ -e $f ]] && basename "$f"
done
