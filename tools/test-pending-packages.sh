#!/usr/bin/env bash
# tools/pending-packages.sh against a made-up repository: which packages it
# names for a build, and that it refuses a downgrade.

set -euo pipefail

HERE="$(dirname "$(realpath "$0")")"
TEST=$(mktemp -d)
trap 'rm -rf "$TEST"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# pkg DIR [EPOCH:]PKGVER-PKGREL PKGNAME...
pkg() {
	local dir=$1 version=$2 name epoch=
	shift 2
	[[ $version == *:* ]] && { epoch=${version%%:*}; version=${version#*:}; }
	mkdir -p "$TEST/packages/$dir"
	{
		printf 'pkgbase = %s\n' "$dir"
		[[ -n $epoch ]] && printf '\tepoch = %s\n' "$epoch"
		printf '\tpkgver = %s\n\tpkgrel = %s\n' "${version%-*}" "${version##*-}"
		for name; do printf '\npkgname = %s\n' "$name"; done
	} > "$TEST/packages/$dir/.SRCINFO"
}

pkg unchanged 20260819-1 unchanged
pkg rebuilt 20260819-2 rebuilt
pkg added 1.0.0-1 added
pkg split 0.2.2-1 split split-ebpf
pkg epoch 1:0.1-1 epoch
cat > "$TEST/published" <<'EOF'
unchanged 20260819-1
rebuilt 20260819-1
split 0.2.2-1
epoch 2.0-1
EOF

echo "==> names what is newer or missing, and nothing else"
got=$("$HERE/pending-packages.sh" "$TEST/published" "$TEST/packages" | sort | tr '\n' ' ')
want="added epoch rebuilt split "
[[ $got == "$want" ]] || fail "expected '$want', got '$got'"
echo "    $got"

echo "==> refuses a version older than the published one"
pkg older 2.0-1 older
echo "older 1:1.0-1" >> "$TEST/published"
if "$HERE/pending-packages.sh" "$TEST/published" "$TEST/packages" >/dev/null 2>"$TEST/err"; then
	fail "a downgrade was accepted"
fi
grep -q 'older 2.0-1 is older than the published 1:1.0-1' "$TEST/err" \
	|| fail "the refusal does not name the package: $(cat "$TEST/err")"
sed 's/^/    /' "$TEST/err"

echo
echo "PASS"
