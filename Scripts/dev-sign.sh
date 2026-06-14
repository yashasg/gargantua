#!/usr/bin/env bash
# dev-sign.sh — codesign the local debug binary with a STABLE identity so the
# macOS Keychain stops re-prompting on every rebuild.
#
# Why this exists:
#   `swift build` ad-hoc-signs the binary with a fresh signature each build.
#   The Cloud AI key's Keychain ACL is tied to the requesting app's code
#   signature, so every rebuild looks like a new, untrusted app and macOS
#   re-asks "Gargantua wants to use … com.gargantua.cloud-ai". "Always Allow"
#   never sticks because the next build's signature differs.
#
#   Signing the debug binary with a constant identity (your Apple Development
#   cert, or a one-time self-signed code-signing cert) gives it a stable
#   "designated requirement". Click "Always Allow" once after the first
#   dev-sign and the grant persists across rebuilds.
#
# Usage:
#   swift build && Scripts/dev-sign.sh && .build/debug/Gargantua
#
#   DEV_SIGN_IDENTITY="Apple Development: You (TEAMID)" Scripts/dev-sign.sh
#   Scripts/dev-sign.sh path/to/other/binary   # sign a specific binary
#
# Identity resolution: $DEV_SIGN_IDENTITY if set, else the first
# "Apple Development" identity in your keychain.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${1:-$REPO_ROOT/.build/debug/Gargantua}"

die() {
    printf 'dev-sign: %s\n' "$1" >&2
    exit 1
}

[ -f "$BINARY" ] || die "no binary at $BINARY (run 'swift build' first)"

# Resolve a stable signing identity.
IDENTITY="${DEV_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi

if [ -z "$IDENTITY" ]; then
    die "no stable signing identity found.

Set one explicitly:
  DEV_SIGN_IDENTITY=\"Apple Development: You (TEAMID)\" Scripts/dev-sign.sh

…or create a one-time self-signed code-signing certificate (no Apple account
needed): Keychain Access → Certificate Assistant → Create a Certificate →
Name it e.g. 'Gargantua Dev', Identity Type 'Self Signed Root', Certificate
Type 'Code Signing' → then re-run with DEV_SIGN_IDENTITY='Gargantua Dev'.

Available identities:
$(security find-identity -v -p codesigning 2>/dev/null | sed 's/^/  /')"
fi

echo "dev-sign: signing $(basename "$BINARY") with → $IDENTITY"
codesign --force --sign "$IDENTITY" "$BINARY"
codesign --verify --verbose=1 "$BINARY" >/dev/null 2>&1 \
    && echo "dev-sign: ok. On first launch click 'Always Allow' once — it sticks across rebuilds now."
