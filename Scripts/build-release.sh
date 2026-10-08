#!/bin/bash
#
#  build-release.sh
#  agenda
#
#  Created by David Sherlock on 2026.
#
#  Builds the release artefact for the Homebrew tap:
#
#      Scripts/build-release.sh <version>
#
#  The steps are CLIKit's, shared by the whole fleet: build, bundle, strip,
#  sign, check, complete, package (Scripts/build-cli-release.sh in the CLIKit
#  this package resolves). What is this tool's own lives beside this file —
#  Scripts/smoke.sh for its release checks, Scripts/stage.sh for anything
#  extra the archive carries — and the shared script sources both.
#

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
swift package resolve >/dev/null

SHARED=".build/checkouts/swift-cli-kit/Scripts/build-cli-release.sh"
# A path dependency during development has no checkout; it is the sibling.
[ -f "$SHARED" ] || SHARED="../swift-cli-kit/Scripts/build-cli-release.sh"
[ -f "$SHARED" ] || { echo "✗ no build-cli-release.sh — this needs CLIKit 0.9.1 or later" >&2; exit 1; }

exec bash "$SHARED" "$@"
