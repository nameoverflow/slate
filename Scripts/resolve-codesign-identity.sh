#!/bin/sh
set -eu

MODE="${1:-auto}"
LOCAL_CERT_NAME="${2:-Slate Local Code Signing}"
FALLBACK_LOCAL_CERT_NAME="${3:-Talus Local Code Signing}"

if [ "$MODE" != "auto" ] && [ "$MODE" != "dist" ]; then
    printf '%s\n' "$MODE"
    exit 0
fi

IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"

pick_first() {
    pattern="$1"
    printf '%s\n' "$IDENTITIES" | grep -F "$pattern" | head -n 1 | awk '{print $2}' || true
}

# 1. Official Apple Developer ID Application (valid for both local use and distribution)
dev_id="$(pick_first '"Developer ID Application:')"
if [ -n "$dev_id" ]; then
    printf '%s\n' "$dev_id"
    exit 0
fi

# For external distribution without Developer ID, use clean ad-hoc (-)
if [ "$MODE" = "dist" ]; then
    printf '%s\n' "-"
    exit 0
fi

# 2. Apple Development certificate (if Xcode is signed in)
apple_dev="$(pick_first '"Apple Development:')"
if [ -n "$apple_dev" ]; then
    printf '%s\n' "$apple_dev"
    exit 0
fi

# 3. Persistent local self-signed certificate (keeps macOS Screen Recording TCC across rebuilds)
local_id="$(pick_first "\"$LOCAL_CERT_NAME\"")"
if [ -n "$local_id" ]; then
    printf '%s\n' "$local_id"
    exit 0
fi

if [ -n "$FALLBACK_LOCAL_CERT_NAME" ]; then
    fallback_id="$(pick_first "\"$FALLBACK_LOCAL_CERT_NAME\"")"
    if [ -n "$fallback_id" ]; then
        printf '%s\n' "$fallback_id"
        exit 0
    fi
fi

# 4. Fallback to ad-hoc signing
printf '%s\n' "-"
