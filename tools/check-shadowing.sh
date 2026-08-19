#!/usr/bin/env bash
# ADR-0002, made executable.
#
# Fails if any package under packages/ carries the name of — or claims to provide —
# a package from [core], [extra] or [multilib]. The point of a rule is that it holds
# when nobody is watching.

set -euo pipefail

ROOT="$(dirname "$(realpath "$0")")/.."

echo "==> reading upstream package names"
mapfile -t upstream < <(pacman -Sl core extra multilib 2>/dev/null | awk '{print $2}')
(( ${#upstream[@]} )) || { echo "no upstream package list — run pacman -Sy first" >&2; exit 1; }

declare -A is_upstream=()
for name in "${upstream[@]}"; do is_upstream["$name"]=1; done
echo "    ${#upstream[@]} names in core/extra/multilib"

violations=0

while IFS= read -r pkgbuild; do
	dir=$(dirname "$pkgbuild")
	name=$(basename "$dir")

	if [[ -n ${is_upstream[$name]:-} ]]; then
		echo "VIOLATION  $name shadows an upstream package" >&2
		(( ++violations ))
	fi

	# provides= can shadow just as effectively as the name itself.
	while IFS= read -r provided; do
		provided=${provided%%[<=>]*}
		[[ -n $provided ]] || continue
		if [[ -n ${is_upstream[$provided]:-} ]]; then
			echo "VIOLATION  $name provides '$provided', an upstream package" >&2
			(( ++violations ))
		fi
	done < <(sed -n "s/^[[:space:]]*provides=(\(.*\))/\1/p" "$pkgbuild" | tr -d "'\"" | tr ' ' '\n')
done < <(find "$ROOT/packages" -mindepth 2 -maxdepth 2 -name PKGBUILD | sort)

if (( violations )); then
	echo >&2
	echo "$violations violation(s) of ADR-0002." >&2
	echo "A package that shadows the base does not belong in [colony]." >&2
	echo "See docs/decisions/0002-regle-de-non-recouvrement.md" >&2
	exit 1
fi

echo "==> clean: nothing in packages/ shadows core, extra or multilib"
