#!/usr/bin/env bash
# Runs colony-mirrorlist.install's post_upgrade against pacman.conf files shaped
# like the ones installed machines hold. Needs no root and touches nothing
# outside a temporary directory.
#
# What a pass proves: the stanza the installer appended before pkgrel 6 gains
# exactly one line, right after its header, and pacman reads it as
# DatabaseRequired. A SigLevel the administrator chose, in the stanza or in the
# file it includes, a commented-out stanza and a file with no stanza are left
# byte for byte. A second run changes nothing.

set -euo pipefail

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
PKG="$ROOT/packages/colony-mirrorlist"
LINE='SigLevel = Required DatabaseRequired'

TEST=$(mktemp -d /tmp/colony-migration.XXXXXX)
trap 'rm -rf "$TEST"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# pacman refuses a configuration whose Include is missing, so the stanza points
# at a mirrorlist this test owns instead of /etc/pacman.d/colony-mirrorlist.
printf 'Server = file:///nonexistent/colony\n' > "$TEST/colony-mirrorlist"

# What installed machines hold: the shipped stanza without the line this
# migration adds. Built from colony-repo.conf rather than copied into this
# script, so the two cannot drift apart.
grep -qx "$LINE" "$PKG/colony-repo.conf" || fail "colony-repo.conf no longer carries '$LINE'"
old_stanza() {
	grep -vx "$LINE" "$PKG/colony-repo.conf" \
		| sed "s|^Include = /etc/pacman.d/colony-mirrorlist$|Include = $TEST/colony-mirrorlist|"
}

# The parts of the pacman.conf `pacman` ships that the migration reads.
stock() {
	cat <<'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Server = file:///nonexistent/core

[extra]
Server = file:///nonexistent/extra
EOF
}

# The way pacman calls it: sourced, then the function, with new and old versions.
migrate() {
	# shellcheck disable=SC1091
	( . "$PKG/colony-mirrorlist.install"; _pacman_conf=$1; post_upgrade 20260819-6 20260819-5 )
}

expect_added() {
	local name=$1 conf="$TEST/$1.conf" before="$TEST/$1.before" out n
	cp "$conf" "$before"
	out=$(migrate "$conf")
	[[ $out == *"added '$LINE'"* ]] || fail "$name: expected a message, got: '$out'"

	n=$(grep -n '^[[:space:]]*\[colony\][[:space:]]*$' "$before" | cut -d: -f1)
	[[ $(diff "$before" "$conf") == "${n}a$((n + 1))"$'\n'"> $LINE" ]] \
		|| fail "$name: expected exactly '$LINE' after line $n:"$'\n'"$(diff "$before" "$conf")"
	pacman-conf --config "$conf" --repo=colony SigLevel | grep -qx DatabaseRequired \
		|| fail "$name: pacman does not read DatabaseRequired for [colony]"

	cp "$conf" "$before"
	out=$(migrate "$conf")
	[[ -z $out ]] || fail "$name: second run said: '$out'"
	cmp -s "$before" "$conf" || fail "$name: second run changed the file"
	echo "ok    $name"
}

expect_untouched() {
	local name=$1 conf="$TEST/$1.conf" before="$TEST/$1.before" want=${2:-} out
	cp "$conf" "$before"
	out=$(migrate "$conf")
	[[ $out == "$want"* ]] || fail "$name: expected '${want:-no output}', got: '$out'"
	[[ -n $want || -z $out ]] || fail "$name: expected no output, got: '$out'"
	cmp -s "$before" "$conf" || fail "$name: the file changed"
	echo "ok    $name"
}

# Appended at the end, as shellprocess_cleanup.conf has always done.
{ stock; old_stanza; } > "$TEST/appended.conf"
expect_added appended

# Declared before [core] by hand, as colony-mirrorlist's header suggests, with
# the stray whitespace pacman tolerates around a header.
{ printf '[options]\nArchitecture = auto\n\n  [colony]\t \nInclude = %s\n\n' "$TEST/colony-mirrorlist"
  stock | sed '1,/^$/d'; } > "$TEST/before-core.conf"
expect_added before-core

{ stock; old_stanza; echo 'SigLevel = Optional TrustAll'; } > "$TEST/own-siglevel.conf"
expect_untouched own-siglevel

printf 'Server = file:///nonexistent/colony\nSigLevel = PackageRequired\n' > "$TEST/signed-mirrorlist"
{ stock; old_stanza | sed "s|$TEST/colony-mirrorlist|$TEST/signed-mirrorlist|"; } > "$TEST/siglevel-in-include.conf"
expect_untouched siglevel-in-include

{ stock; old_stanza | sed 's/^\[colony\]$/#[colony]/; s/^Include/#Include/'; } > "$TEST/commented.conf"
expect_untouched commented

stock > "$TEST/no-stanza.conf"
expect_untouched no-stanza

# pacman also reads a [colony] declared in an Include'd file. That file is not
# the migration's to edit, so it says what to do instead.
{ old_stanza; } > "$TEST/elsewhere.d"
{ stock; printf 'Include = %s\n' "$TEST/elsewhere.d"; } > "$TEST/elsewhere.conf"
expect_untouched elsewhere "colony-mirrorlist: [colony] is declared outside"

# Not a pacman.conf pacman can read: nothing to do, and no error out of a scriptlet.
printf '[options]\nInclude = /nonexistent/file\n\n[colony]\nServer = file:///x\n' > "$TEST/unparsable.conf"
expect_untouched unparsable

out=$(migrate "$TEST/does-not-exist.conf") || fail "missing pacman.conf: post_upgrade failed"
[[ -z $out ]] || fail "missing pacman.conf: said '$out'"
echo "ok    missing-file"

echo
echo "PASS - the SigLevel line is added where it is missing, an administrator's"
echo "       SigLevel is left alone, and a second run changes nothing."
