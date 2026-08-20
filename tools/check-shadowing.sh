#!/usr/bin/env bash
# ADR-0002, made executable.
#
# Fails if any package under packages/ carries the name of — or claims to provide —
# a package from [core], [extra] or [multilib]. The point of a rule is that it holds
# when nobody is watching.

set -euo pipefail

ROOT="$(dirname "$(realpath "$0")")/.."

echo "==> reading upstream package names"
# One repository at a time, and never swallowing stderr. `pacman -Sl core extra
# multilib` still prints core and extra on stdout when multilib is missing, and exits
# non-zero — but bash does not inspect the status of a process substitution and
# pipefail does not reach into one. The guard below would pass, the script would
# announce "clean", and a package named lib32-glibc or steam would sail through
# ADR-0002. A check that reports clean on a violation is worse than no check.
upstream=()
for r in core extra multilib; do
	# The status is captured from pacman itself, in its own assignment. Piping into
	# a process substitution would hide it: mapfile succeeds even when it reads
	# nothing, so `mapfile < <(pacman ...) || fail` never fires — bash does not
	# inspect a process substitution's status and pipefail does not reach into one.
	if ! listing=$(pacman -Sl "$r" 2>&1); then
		echo "cannot list repository '$r':" >&2
		printf '  %s\n' "$listing" >&2
		echo "Is it enabled in pacman.conf, and has 'pacman -Sy' run?" >&2
		exit 1
	fi
	mapfile -t names < <(printf '%s\n' "$listing" | awk '{print $2}')
	(( ${#names[@]} )) || { echo "repository '$r' returned no packages" >&2; exit 1; }
	upstream+=("${names[@]}")
done

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
