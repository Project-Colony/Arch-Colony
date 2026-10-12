# ADR-0010 - Signing and publishing in CI

**Status**: accepted - 2026-10-12. Supersedes the publication part of
[ADR-0008](0008-chaine-de-confiance.md); its choice of key, of a separate
signing subkey and of GitHub releases as hosting stands.

## Context

ADR-0008 said CI would publish `[colony]`. It never did. Every package, every
database and every image was built, signed and uploaded from the maintainer's
machine, by two scripts that asked `publish? [y/N]` before uploading. That
machine held the certification primary key and the signing subkey in its
everyday keyring, and the same session ran `mkarchiso` as root, parsed
archinstall from GitHub and compiled every package. Anything that ran there
could read both keys.

The organisation's rule is the opposite: nothing is released by hand, and a
signing key never shares a job with code that builds
([releases.md](https://github.com/Project-Colony/Project-Colony-Resources/blob/main/design/releases.md)).
Its shared workflow signs with ed25519 and names each signature
`<asset>.sig`, which is exactly the name pacman and `gpg --verify` read an
OpenPGP signature from. releases.md therefore makes OpenPGP the contract for
distribution artefacts, and this repository cannot call that workflow.

## Decision

**release-please drives releases**, as everywhere else in the organisation.
Merging its pull request tags `vX.Y.Z`; the tag runs
`.github/workflows/release.yml`.

**The workflow keeps the shared workflow's isolation contract without its
format.** The jobs that build (the packages, the source bundle, the image)
hold no key. Two jobs sign: one signs the new packages, the `[colony]`
database and the offline repository the image carries; the other signs the
image and its checksum. Neither checks out the repository nor builds anything:
they download artefacts, import the key into a temporary GnuPG home, sign, and
upload. A final job, without the key, checks every signature against
`colony.gpg` at the tag before it uploads anything.

**Only the signing subkey is in CI.** It is the secret
`ARCH_COLONY_GPG_SIGNING_SUBKEY` of the repository's `release` environment,
exported with `gpg --export-secret-subkeys <subkey>!`. The signing jobs refuse
a secret that carries the primary key's secret part, or a key that is not a
subkey of `5CD2 FCA1 3E69 1C65 A354  780D 80C1 18F7 74E6 C43F`. The primary key
only certifies and revokes subkeys. It never enters CI, and is to be kept
offline, as ADR-0008 already planned.

**[colony] grows by verification, not by reconstruction.** A release builds
only the packages newer than what `[colony]` serves, refuses one older than
that, and adds them to the published database after checking its signature.
The packages and their signatures are uploaded before the databases that list
them, so a machine that syncs in between sees a consistent repository.

**Images are named by build date and never replaced.** An image name already
published fails the release instead of replacing what people have written
checksums down for. The image goes on the `vX.Y.Z` release with its signature,
checksum, package list, `colony.gpg` and a source bundle; `[colony]` stays on
the rolling `repo` release.

**A smoke test gates publication.** The repository's trust chain is tested on
the very databases about to be published, the image is booted in a KVM
virtual machine to a working live system, and installed from there with no
network through the installer's own pages; the installed system's first boot
must run the firewall it got from the medium.

## Consequences

**What it fixes.** No signing key is on a machine that also builds. A
compromised dependency of calamares, Colony Firewall Control or paru can no
longer reach the key it is being built next to. Publication can no longer skip
a step or depend on what was lying in a local `repo/out`.

**What it costs.** A compromised subkey now means a compromised GitHub
environment secret, which the subkey's revocation path in
[SECURITY.md](../../SECURITY.md) handles without users changing the key they
trust. Re-signing everything after a subkey change goes through CI too: bump
`pkgrel` of every package and release.

**What it needs from the maintainer.** The secret, before the first release
can be signed; until then the workflow stops at the first signing job with a
message saying so, and nothing is published. `repo/genkey.sh` remains as the
offline tool that created the key, never run in CI.

**What it leaves open.** The image carries Arch Linux packages unchanged. Each
release names them with their exact versions and points at the sources Arch
Linux publishes. Whether Arch Colony also mirrors their complete source next
to each image, or offers it in writing, is the maintainer's decision and is
not settled here.
