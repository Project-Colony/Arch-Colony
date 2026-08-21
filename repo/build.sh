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

	# The chroot only ever sees [core] and [extra]; [colony] is not in devtools'
	# pacman.conf and has no business being there, since it would make the build
	# depend on what we happen to have published. So a package that depends on
	# another Colony package cannot resolve it — colony-firewall-defaults needs
	# colony-firewall-control, and pkgctl stopped at "Could not resolve all
	# dependencies".
	#
	# --install-to-chroot takes files rather than names, which is the right shape
	# here: it builds against exactly the artefact in repo/out, the one that is
	# about to be published, and not against whatever a repository might serve.
	# Transitively, because one level is not enough: colony-firewall-defaults
	# wants colony-firewall-control, which wants colony-firewall-control-ebpf.
	# Injecting only the first leaves pacman with an unsatisfiable file and it
	# fails exactly as if nothing had been injected at all.
	inject=()
	declare -A seen=()
	queue=()
	if srcinfo=$(cd "$dir" && makepkg --printsrcinfo 2>/dev/null); then
		mapfile -t queue < <(printf '%s\n' "$srcinfo" |
			awk -F' = ' '/^\t(make)?depends = /{sub(/[<>=].*/, "", $2); print $2}' | sort -u)
	fi
	while (( ${#queue[@]} )); do
		want="${queue[0]}"; queue=("${queue[@]:1}")
		[[ -n ${seen[$want]:-} ]] && continue
		seen[$want]=1
		shopt -s nullglob
		have=("$OUT/$want"-[0-9]*.pkg.tar.zst)
		shopt -u nullglob
		(( ${#have[@]} )) || continue          # in [core]/[extra], the chroot has it
		file="${have[-1]}"
		echo "    injecting ${file##*/} (in [colony], not in the chroot)"
		inject+=(--install-to-chroot "$file")
		# Its own dependencies, read from the built package rather than from a
		# PKGBUILD we may not have.
		mapfile -t more < <(bsdtar -xOf "$file" .PKGINFO 2>/dev/null |
			awk -F' = ' '/^depend = /{sub(/[<>=].*/, "", $2); print $2}')
		queue+=("${more[@]}")
	done
	unset seen

	# A clean chroot, so the result does not depend on whatever happens to be
	# installed on this machine.
	( cd "$dir" && pkgctl build --clean "${inject[@]}" )

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
