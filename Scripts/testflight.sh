#!/usr/bin/env bash
#
# Scripts/testflight.sh — one-command TestFlight release for Moodbound.
#
# Reads ASC API credentials from ~/.asc/config.json (key_id, issuer_id,
# private_key_path). Bumps CFBundleVersion in Project.swift, regenerates
# the Tuist workspace, archives, exports, uploads, and polls ASC until
# the build is processed.
#
# Usage:
#   Scripts/testflight.sh              # bump build number by 1, release
#   Scripts/testflight.sh --build 7    # set specific build number
#   Scripts/testflight.sh --skip-bump  # reuse current build number
#   Scripts/testflight.sh --dry-run    # archive + export but skip upload
#
# Prerequisites:
#   - tuist, xcodebuild, jq installed (brew install tuist jq)
#   - ~/.asc/config.json populated with key_id, issuer_id, private_key_path
#   - ~/.private_keys/AuthKey_XXXX.p8 readable (chmod 600)
#   - ExportOptions.plist in repo root
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG_PATH="${HOME}/.asc/config.json"
PROJECT_FILE="${REPO_ROOT}/Project.swift"
EXPORT_OPTIONS="${REPO_ROOT}/ExportOptions.plist"
ARCHIVE_PATH="${REPO_ROOT}/build/moodbound.xcarchive"
EXPORT_DIR="${REPO_ROOT}/build/export"
IPA_PATH="${EXPORT_DIR}/moodbound.ipa"
SCHEME="moodbound"
WORKSPACE="${REPO_ROOT}/moodbound.xcworkspace"

# ----- args -----------------------------------------------------------

BUILD_OVERRIDE=""
SKIP_BUMP=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build)
            BUILD_OVERRIDE="$2"
            shift 2
            ;;
        --skip-bump)
            SKIP_BUMP=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

# ----- load config ----------------------------------------------------

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "error: $CONFIG_PATH not found. Populate it with key_id, issuer_id, private_key_path." >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq not found. Install with: brew install jq" >&2
    exit 1
fi

KEY_ID="$(jq -r '.key_id // empty' "$CONFIG_PATH")"
ISSUER_ID="$(jq -r '.issuer_id // empty' "$CONFIG_PATH")"
PRIVATE_KEY_PATH="$(jq -r '.private_key_path // empty' "$CONFIG_PATH")"
APP_ID="$(jq -r '.app_id // empty' "$CONFIG_PATH")"
BUNDLE_ID="$(jq -r '.bundle_id // "dev.tuist.Moodbound"' "$CONFIG_PATH")"

if [[ -z "$KEY_ID" || -z "$ISSUER_ID" || -z "$PRIVATE_KEY_PATH" ]]; then
    echo "error: key_id, issuer_id, and private_key_path are all required in $CONFIG_PATH" >&2
    exit 1
fi

if [[ ! -r "$PRIVATE_KEY_PATH" ]]; then
    echo "error: private key not readable: $PRIVATE_KEY_PATH" >&2
    exit 1
fi

# ----- bump build number ---------------------------------------------

CURRENT_BUILD=$(sed -n 's/.*"CFBundleVersion": *\.string("\([0-9]*\)").*/\1/p' "$PROJECT_FILE" | head -1)
if [[ -z "$CURRENT_BUILD" ]]; then
    echo "error: could not parse CFBundleVersion from $PROJECT_FILE" >&2
    exit 1
fi

if [[ -n "$BUILD_OVERRIDE" ]]; then
    NEW_BUILD="$BUILD_OVERRIDE"
elif [[ "$SKIP_BUMP" == "1" ]]; then
    NEW_BUILD="$CURRENT_BUILD"
else
    NEW_BUILD=$((CURRENT_BUILD + 1))
fi

if [[ "$NEW_BUILD" != "$CURRENT_BUILD" ]]; then
    echo "Bumping CFBundleVersion $CURRENT_BUILD -> $NEW_BUILD"
    # macOS sed in-place. -i '' is required.
    sed -i '' "s/\"CFBundleVersion\": *\.string(\"${CURRENT_BUILD}\")/\"CFBundleVersion\": .string(\"${NEW_BUILD}\")/" "$PROJECT_FILE"
else
    echo "Using existing CFBundleVersion $NEW_BUILD"
fi

MARKETING_VERSION=$(sed -n 's/.*"CFBundleShortVersionString": *\.string("\([0-9.]*\)").*/\1/p' "$PROJECT_FILE" | head -1)
echo "Release: $MARKETING_VERSION ($NEW_BUILD)"

# ----- generate, archive, export -------------------------------------

echo "Regenerating Tuist project..."
tuist generate --no-open

echo "Archiving..."
rm -rf "$ARCHIVE_PATH"
xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive

echo "Exporting IPA..."
rm -rf "$EXPORT_DIR"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates

if [[ ! -f "$IPA_PATH" ]]; then
    echo "error: expected IPA at $IPA_PATH but it wasn't produced" >&2
    exit 1
fi

echo "IPA ready: $IPA_PATH"

if [[ "$DRY_RUN" == "1" ]]; then
    echo "Dry run: skipping upload and polling."
    exit 0
fi

# ----- upload to App Store Connect ------------------------------------

echo "Uploading to App Store Connect via altool..."
xcrun altool \
    --upload-app \
    --type ios \
    --file "$IPA_PATH" \
    --apiKey "$KEY_ID" \
    --apiIssuer "$ISSUER_ID"

echo "Upload submitted. Polling ASC for processing..."

# ----- poll processing state ------------------------------------------
#
# Uses a short Python helper (stdlib only) to mint an ES256 JWT for the
# App Store Connect API and poll the builds endpoint. We need this
# because bash alone can't produce an ECDSA signature. Python is in PATH
# on macOS.

python3 - "$KEY_ID" "$ISSUER_ID" "$PRIVATE_KEY_PATH" "$BUNDLE_ID" "$MARKETING_VERSION" "$NEW_BUILD" <<'PY'
import base64
import hashlib
import json
import subprocess
import sys
import time
import urllib.request
import urllib.parse

key_id, issuer_id, private_key_path, bundle_id, marketing_version, build_number = sys.argv[1:7]

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

def make_jwt() -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 15 * 60,
        "aud": "appstoreconnect-v1",
    }
    header_b64 = b64url(json.dumps(header, separators=(",", ":")).encode())
    payload_b64 = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{header_b64}.{payload_b64}".encode()

    # Use openssl dgst -sha256 -sign to produce a DER ECDSA signature, then
    # convert to JOSE (r || s) 64-byte format.
    der = subprocess.check_output(
        ["openssl", "dgst", "-sha256", "-sign", private_key_path],
        input=signing_input,
    )
    # Parse DER SEQUENCE { INTEGER r, INTEGER s }
    if der[0] != 0x30:
        raise SystemExit("unexpected DER signature")
    # handle long form length
    idx = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    if der[idx] != 0x02:
        raise SystemExit("expected INTEGER for r")
    r_len = der[idx + 1]
    r = der[idx + 2 : idx + 2 + r_len].lstrip(b"\x00")
    idx2 = idx + 2 + r_len
    if der[idx2] != 0x02:
        raise SystemExit("expected INTEGER for s")
    s_len = der[idx2 + 1]
    s = der[idx2 + 2 : idx2 + 2 + s_len].lstrip(b"\x00")
    r_padded = b"\x00" * (32 - len(r)) + r
    s_padded = b"\x00" * (32 - len(s)) + s
    signature_b64 = b64url(r_padded + s_padded)
    return f"{header_b64}.{payload_b64}.{signature_b64}"

def asc_get(path: str, params: dict) -> dict:
    token = make_jwt()
    url = "https://api.appstoreconnect.apple.com" + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())

# Resolve app id by bundle id if needed.
print(f"Resolving app for bundle {bundle_id}...")
apps = asc_get("/v1/apps", {"filter[bundleId]": bundle_id, "limit": "5"})
if not apps.get("data"):
    raise SystemExit(f"No app found for bundle id {bundle_id}")
app_id = apps["data"][0]["id"]
print(f"  app id: {app_id}")

deadline = time.time() + 25 * 60  # 25 minutes
poll_interval = 30

while time.time() < deadline:
    builds = asc_get(
        "/v1/builds",
        {
            "filter[app]": app_id,
            "filter[version]": build_number,
            "limit": "5",
            "sort": "-uploadedDate",
            "fields[builds]": "version,processingState,uploadedDate,expired",
        },
    )
    rows = builds.get("data", [])
    if not rows:
        print(f"  build {build_number} not yet visible to ASC API, waiting...")
    else:
        for row in rows:
            attrs = row.get("attributes", {})
            state = attrs.get("processingState", "UNKNOWN")
            uploaded = attrs.get("uploadedDate", "?")
            print(f"  build {build_number}: {state} (uploaded {uploaded})")
            if state == "VALID":
                print("Build processed and available on TestFlight.")
                sys.exit(0)
            if state in ("INVALID", "FAILED"):
                raise SystemExit(f"Build {build_number} entered terminal state: {state}")
    time.sleep(poll_interval)

raise SystemExit("Timed out waiting for ASC to process build.")
PY

echo "TestFlight release complete: $MARKETING_VERSION ($NEW_BUILD)"
