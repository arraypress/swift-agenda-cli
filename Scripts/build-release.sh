#!/bin/bash
#
#  build-release.sh
#  agenda
#
#  Created by David Sherlock on 2026.
#
#  Builds the release artefact for the Homebrew tap: a stripped, ad-hoc signed
#  arm64 binary with its licence and shell completions, plus the sha256 the
#  formula needs.
#
#  WHY there is no notarization here, unlike Sidewatch. Gatekeeper only assesses
#  files carrying com.apple.quarantine, and that attribute is set by browsers and
#  by Homebrew *casks* — not by formulae or curl. A formula-installed binary is
#  never assessed, so ad-hoc signing is sufficient. (Verifiable: `jq` from
#  homebrew-core is ad-hoc signed with no team identifier, `spctl` calls it
#  "rejected", and it runs fine.) Ship this as a .dmg or a cask and that stops
#  being true — then Sidewatch's notarize.sh is the model.
#

set -euo pipefail

TOOL="agenda"
# Taken from the remote rather than written down. A copied script with a
# stale repo name produces a formula whose download URL 404s, and nothing
# catches that until somebody tries to install it.
REPO="$(basename -s .git "$(git config --get remote.origin.url)")"
VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "usage: Scripts/build-release.sh <version>   e.g. 0.1.0" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
STAGE="$DIST/$TOOL-$VERSION"
ARCHIVE="$TOOL-$VERSION-macos-arm64.tar.gz"

cd "$ROOT"
rm -rf "$DIST"
mkdir -p "$STAGE/completions"

echo "==> Building $TOOL $VERSION (arm64, release)"
swift build -c release --arch arm64

# Redirected: if SwiftPM ever writes a warning to stdout, an unguarded capture
# silently turns BIN into a path plus prose.
BUILD_DIR="$(swift build -c release --arch arm64 --show-bin-path 2>/dev/null)"
BIN="$BUILD_DIR/$TOOL"
[ -x "$BIN" ] || { echo "✗ no binary at $BIN" >&2; exit 1; }
cp "$BIN" "$STAGE/$TOOL"

# SwiftPM emits a .bundle beside the binary for any dependency declaring
# `resources:`. Bundle.module resolves it relative to the executable, so a
# tarball containing only the binary traps the moment the resource is needed —
# and neither --version nor --help touches one, which is how that ships.
for bundle in "$BUILD_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    echo "==> Bundling $(basename "$bundle")"
    cp -R "$bundle" "$STAGE/"
done

# Strip debug symbols and the local symbol table. Roughly halves the binary, and
# nothing here has debugging value to a user. ArgumentParser's Mirror-based
# parsing survives it — verified by running a real subcommand below.
echo "==> Stripping"
strip -rSTx "$STAGE/$TOOL"

# Re-sign after stripping: mutating a Mach-O invalidates its ad-hoc signature,
# and arm64 refuses to exec a binary whose signature does not match. Skipping
# this produces "killed: 9" with no further explanation.
echo "==> Re-signing (ad-hoc)"
codesign --force --sign - "$STAGE/$TOOL"
codesign --verify --strict "$STAGE/$TOOL"

# ── Assertions ───────────────────────────────────────────────────────────────
# Each of these has a matching way to ship something wrong silently.

echo "==> Verifying"

# A fat or x86_64 slice would install and run, just not as advertised.
ARCHS="$(lipo -archs "$STAGE/$TOOL")"
[ "$ARCHS" = "arm64" ] || { echo "✗ expected arm64 only, got: $ARCHS" >&2; exit 1; }

# Catches strip/sign damage, which is otherwise invisible until a user runs it.
REPORTED="$("$STAGE/$TOOL" --version)"

# Tagging v0.2.0 while CommandConfiguration still says 0.1.0 is an easy mistake
# and produces a release whose binary disagrees with its own filename.
[ "$REPORTED" = "$VERSION" ] || {
    echo "✗ version mismatch: tag says $VERSION, binary reports $REPORTED" >&2
    echo "  update CommandConfiguration(version:) to match." >&2
    exit 1
}

# Exercises real argument parsing, not just --version.
"$STAGE/$TOOL" --help >/dev/null

# Exercises the resource bundle, which --version and --help never reach. This
# is the check that catches a tarball missing its resources.
# agenda reads only from the network, so there is no offline conversion to
# smoke-test. --describe still exercises the full command tree, which is the
# closest offline equivalent.
"$STAGE/$TOOL" describe --json >/dev/null

# ── Extras ───────────────────────────────────────────────────────────────────

echo "==> Generating shell completions"
for shell in bash zsh fish; do
    case "$shell" in
        bash) name="$TOOL.bash" ;;
        zsh)  name="_$TOOL" ;;
        fish) name="$TOOL.fish" ;;
    esac
    "$STAGE/$TOOL" --generate-completion-script "$shell" > "$STAGE/completions/$name"
done

# MIT requires the notice accompany substantial portions of the software, and a
# bare binary in a tarball carries none.
cp "$ROOT/LICENSE" "$STAGE/LICENSE"

echo "==> Packaging"
tar -czf "$DIST/$ARCHIVE" -C "$DIST" "$TOOL-$VERSION"

SHA="$(shasum -a 256 "$DIST/$ARCHIVE" | cut -d' ' -f1)"
SIZE="$(du -h "$DIST/$ARCHIVE" | cut -f1 | tr -d ' ')"

cat <<EOF

Built $DIST/$ARCHIVE ($SIZE)

  arch:    $ARCHS
  version: $REPORTED
  sha256:  $SHA

Formula fields:
  url    "https://github.com/arraypress/$REPO/releases/download/v$VERSION/$ARCHIVE"
  sha256 "$SHA"
EOF
