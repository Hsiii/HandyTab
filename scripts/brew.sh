#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/.build/dist"
APP_NAME="HandyTab"
APP_FILENAME="${APP_NAME}.app"
CASK_TOKEN="handytab"

VERSION=""
REPOSITORY=""
HOMEPAGE=""
NOTARIZE=0
APPLE_ID="${HANDYTAB_NOTARY_APPLE_ID:-${APPLE_ID:-}}"
APPLE_TEAM_ID="${HANDYTAB_NOTARY_TEAM_ID:-${APPLE_TEAM_ID:-}}"
APPLE_PASSWORD="${HANDYTAB_NOTARY_PASSWORD:-${APPLE_APP_SPECIFIC_PASSWORD:-}}"
NOTARY_KEYCHAIN_PROFILE="${HANDYTAB_NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_KEYCHAIN="${HANDYTAB_NOTARY_KEYCHAIN:-}"
NOTARY_TIMEOUT_SECONDS="${HANDYTAB_NOTARY_TIMEOUT_SECONDS:-2700}"

usage() {
    cat <<'EOF'
Usage: scripts/brew.sh --version <version> [options]

Options:
  --repo <owner/name>  GitHub repository that hosts release archives.
  --homepage <url>     Homepage for the generated cask. Defaults to the repo URL.
  --notarize           Submit the signed app to Apple and staple the accepted ticket.

Environment fallbacks:
  GITHUB_REPOSITORY, GITHUB_SERVER_URL, HANDYTAB_VERSION,
  HANDYTAB_NOTARY_APPLE_ID, HANDYTAB_NOTARY_TEAM_ID,
  HANDYTAB_NOTARY_PASSWORD, HANDYTAB_NOTARY_KEYCHAIN_PROFILE,
  HANDYTAB_NOTARY_KEYCHAIN, HANDYTAB_NOTARY_TIMEOUT_SECONDS
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --repo)
            REPOSITORY="${2:-}"
            shift 2
            ;;
        --homepage)
            HOMEPAGE="${2:-}"
            shift 2
            ;;
        --notarize)
            NOTARIZE=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    VERSION="${HANDYTAB_VERSION:-}"
fi

VERSION="${VERSION#v}"

if [[ -z "$VERSION" ]]; then
    echo "--version is required" >&2
    exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
    echo "Invalid version: $VERSION" >&2
    echo "Use a semantic version like 1.2.3." >&2
    exit 1
fi

if [[ -z "$REPOSITORY" ]]; then
    REPOSITORY="${GITHUB_REPOSITORY:-}"
fi

if [[ -z "$REPOSITORY" ]]; then
    origin_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$origin_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
        REPOSITORY="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
fi

if [[ -z "$REPOSITORY" ]]; then
    echo "Unable to determine GitHub repository. Pass --repo owner/name." >&2
    exit 1
fi

server_url="${GITHUB_SERVER_URL:-https://github.com}"

if [[ -z "$HOMEPAGE" ]]; then
    HOMEPAGE="${server_url}/${REPOSITORY}"
fi

archive_name="${APP_NAME}-${VERSION}.zip"
archive_path="${DIST_DIR}/${archive_name}"
cask_path="${DIST_DIR}/${CASK_TOKEN}.rb"
download_url="${server_url}/${REPOSITORY}/releases/download/v#{version}/${APP_NAME}-#{version}.zip"

mkdir -p "$DIST_DIR"
"$ROOT_DIR/scripts/dmg.sh" --version "$VERSION" --skip-style >/dev/null

app_path="$ROOT_DIR/.build/apple/${APP_FILENAME}"
if [[ ! -d "$app_path" ]]; then
    echo "Missing built app at $app_path." >&2
    exit 1
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
    signing_identity="${HANDYTAB_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
    if [[ "$signing_identity" == "-" ]]; then
        echo "Notarization requires HANDYTAB_CODE_SIGN_IDENTITY to name a Developer ID Application identity." >&2
        exit 1
    fi

    if [[ -z "$NOTARY_KEYCHAIN_PROFILE" && ( -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_PASSWORD" ) ]]; then
        echo "Notarization requires either HANDYTAB_NOTARY_KEYCHAIN_PROFILE or Apple ID, team ID, and password credentials." >&2
        exit 1
    fi

    if ! [[ "$NOTARY_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [[ "$NOTARY_TIMEOUT_SECONDS" -lt 1 ]]; then
        echo "HANDYTAB_NOTARY_TIMEOUT_SECONDS must be a positive integer." >&2
        exit 1
    fi

    notary_auth_args=()
    if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
        notary_auth_args+=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
        if [[ -n "$NOTARY_KEYCHAIN" ]]; then
            notary_auth_args+=(--keychain "$NOTARY_KEYCHAIN")
        fi
    else
        notary_auth_args=(
            --apple-id "$APPLE_ID"
            --team-id "$APPLE_TEAM_ID"
            --password "$APPLE_PASSWORD"
        )
    fi

    notary_archive_path="${DIST_DIR}/${APP_NAME}-${VERSION}-notary.zip"
    rm -f "$notary_archive_path"
    ditto --norsrc -c -k --keepParent "$app_path" "$notary_archive_path"

    xcrun notarytool submit "$notary_archive_path" \
        "${notary_auth_args[@]}" \
        --wait \
        --timeout "${NOTARY_TIMEOUT_SECONDS}s"
    xcrun stapler staple "$app_path"
    rm -f "$notary_archive_path"
fi

rm -f "$archive_path"
ditto --norsrc -c -k --keepParent "$app_path" "$archive_path"

sha256_value="$(shasum -a 256 "$archive_path" | awk '{print $1}')"

cat > "$cask_path" <<EOF
cask "${CASK_TOKEN}" do
  version "${VERSION}"
  sha256 "${sha256_value}"

  url "${download_url}"
  name "${APP_NAME}"
  desc "Open a favorite browser tab with a hand wave or trackpad tap"
  homepage "${HOMEPAGE}"

  depends_on macos: :sonoma

  app "${APP_FILENAME}"

  zap trash: [
    "~/.handytab_config.json",
    "~/Library/LaunchAgents/dev.hsichen.handytab.plist",
    "~/Library/Logs/HandyTab",
  ]
end
EOF

printf 'archive=%s\n' "$archive_path"
printf 'sha256=%s\n' "$sha256_value"
printf 'cask=%s\n' "$cask_path"
