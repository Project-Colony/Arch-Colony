#!/usr/bin/env bash
# Name the packages whose version [colony] does not serve yet.
#
#   tools/pending-packages.sh PUBLISHED [PACKAGES_DIR]
#
# PUBLISHED lists what the repository serves, one "name version" per line, the
# way `pacman -Sl colony | cut -d' ' -f2,3` prints it. Prints the directory name,
# under PACKAGES_DIR (default packages/), of every package that is newer than
# the published one or not published at all. The release workflow builds exactly
# that list.
#
# A version equal to the published one is left alone: the repository already
# serves those bytes, signed, and a rebuild under the same file name would swap
# them for different bytes nobody could tell apart.
#
# An older version fails the run. repo-add would write it into the database and
# every machine would be offered a downgrade. Its --prevent-downgrade flag never
# guarded against that here: the old publishing script deleted the database
# before calling it, so there was nothing left to compare with.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
PUBLISHED=${1:?usage: pending-packages.sh PUBLISHED [PACKAGES_DIR]}
PACKAGES=${2:-$ROOT/packages}

command -v vercmp >/dev/null || { echo "vercmp missing: pacman -S pacman" >&2; exit 1; }

declare -A served=()
while read -r name version; do
	[[ -n $name ]] && served[$name]=$version
done < "$PUBLISHED"

shopt -s nullglob
srcinfos=("$PACKAGES"/*/.SRCINFO)
shopt -u nullglob
(( ${#srcinfos[@]} )) || { echo "no .SRCINFO under $PACKAGES" >&2; exit 1; }

failed=0
for srcinfo in "${srcinfos[@]}"; do
	dir=$(basename "$(dirname "$srcinfo")")
	# .SRCINFO rather than the PKGBUILD: it is data, not code to source, and CI
	# fails a pull request whose .SRCINFO does not match its PKGBUILD.
	version=$(awk -F' = ' '
		/^\tepoch = /  { e = $2 ":" }
		/^\tpkgver = / { v = $2 }
		/^\tpkgrel = / { r = $2 }
		END { print e v "-" r }' "$srcinfo")

	pending=0
	# One directory can build several packages (colony-firewall-control and its
	# -ebpf). It is pending as soon as one of them is.
	while read -r name; do
		published=${served[$name]:-}
		if [[ -z $published ]]; then
			pending=1
			continue
		fi
		order=$(vercmp "$version" "$published")
		if (( order > 0 )); then
			pending=1
		elif (( order < 0 )); then
			echo "$name $version is older than the published $published: refusing a downgrade" >&2
			failed=1
		fi
	done < <(sed -n 's/^pkgname = //p' "$srcinfo")
	if (( pending )); then
		echo "$dir"
	fi
done
exit "$failed"
