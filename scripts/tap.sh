#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CASK_TOKEN="handytab"

VERSION=""
SOURCE_REPOSITORY=""
TAP_REPOSITORY=""
OUTPUT_DIR=""
HOMEPAGE=""
NOTARIZE=0

usage() {
    cat <<'EOF'
Usage: scripts/tap.sh --version <version> [options]

Options:
  --source-repo <owner/name>
                        GitHub repository that hosts HandyTab releases.
  --tap-repo <owner/name>
                        GitHub repository for the tap. Defaults to <owner>/homebrew-tap.
  --output <path>       Tap checkout to update. Defaults to ../../homebrew-tap.
  --homepage <url>      Homepage for the generated cask. Defaults to the source repo URL.
  --notarize            Sign, notarize, and staple the app before generating the cask.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --source-repo)
            SOURCE_REPOSITORY="${2:-}"
            shift 2
            ;;
        --tap-repo)
            TAP_REPOSITORY="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="${2:-}"
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
    echo "--version is required" >&2
    exit 1
fi

if [[ -z "$SOURCE_REPOSITORY" ]]; then
    origin_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$origin_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
        SOURCE_REPOSITORY="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
fi

if [[ -z "$SOURCE_REPOSITORY" ]]; then
    echo "--source-repo is required" >&2
    exit 1
fi

owner="${SOURCE_REPOSITORY%%/*}"

if [[ -z "$TAP_REPOSITORY" ]]; then
    TAP_REPOSITORY="${owner}/homebrew-tap"
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$ROOT_DIR/../../homebrew-tap"
fi

if [[ -z "$HOMEPAGE" ]]; then
    HOMEPAGE="https://github.com/${SOURCE_REPOSITORY}"
fi

brew_args=(
    --version "$VERSION"
    --repo "$SOURCE_REPOSITORY"
    --homepage "$HOMEPAGE"
)
if [[ "$NOTARIZE" -eq 1 ]]; then
    brew_args+=(--notarize)
fi

package_output="$("$ROOT_DIR/scripts/brew.sh" "${brew_args[@]}")"
printf '%s\n' "$package_output"

archive_path=""
cask_path=""
while IFS= read -r line; do
    case "$line" in
        archive=*)
            archive_path="${line#archive=}"
            ;;
        cask=*)
            cask_path="${line#cask=}"
            ;;
    esac
done <<<"$package_output"

if [[ -z "$archive_path" || -z "$cask_path" ]]; then
    echo "Failed to generate release archive or cask." >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR/Casks"
cp "$cask_path" "$OUTPUT_DIR/Casks/${CASK_TOKEN}.rb"

if [[ -f "$OUTPUT_DIR/Casks/comux.rb" ]]; then
    cat > "$OUTPUT_DIR/README.md" <<EOF
# homebrew-tap

Homebrew casks maintained by [Hsiii](https://github.com/Hsiii).

## Install

\`\`\`bash
brew install --cask ${owner}/tap/comux
brew install --cask ${owner}/tap/handytab
\`\`\`

## Casks

- [Comux](https://github.com/Hsiii/Comux) — Codex account limits in the macOS menu bar.
- [HandyTab](${HOMEPAGE}) — Open a favorite browser tab with a hand wave or trackpad tap.
EOF
elif [[ ! -f "$OUTPUT_DIR/README.md" ]]; then
    cat > "$OUTPUT_DIR/README.md" <<EOF
# homebrew-tap

Homebrew tap for [HandyTab](${HOMEPAGE}).

## Install

\`\`\`bash
brew install --cask ${owner}/tap/handytab
\`\`\`
EOF
fi

printf 'tap_dir=%s\n' "$OUTPUT_DIR"
printf 'tap_repo=%s\n' "$TAP_REPOSITORY"
printf 'cask=%s\n' "$OUTPUT_DIR/Casks/${CASK_TOKEN}.rb"
