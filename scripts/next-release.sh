#!/usr/bin/env bash
#
# Decide the version a CI release should carry.
#
#   scripts/next-release.sh [--part patch|minor|major|build-only] [--build-number N]
#
# Prints three KEY=VALUE lines (version=, build=, tag=) so a caller can append
# them straight to $GITHUB_OUTPUT. The build number always moves past every
# number already seen in app/AppDSH.xcconfig, releases/*.json and the
# v<version>-build<build> tags: App Store Connect refuses a number it accepted
# before, and the same rule keeps the GitHub tags unambiguous.

set -euo pipefail
cd "$(dirname "$0")/.."

XCCONFIG=app/AppDSH.xcconfig
part=patch
requested_build=

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --part)         shift; [ $# -gt 0 ] || die "--part needs a value"; part="$1" ;;
        --build-number) shift; [ $# -gt 0 ] || die "--build-number needs a value"; requested_build="$1" ;;
        -h|--help)      awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
        *)              die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

case "$part" in
    patch|minor|major|build-only) ;;
    *) die "--part must be patch, minor, major or build-only (got '$part')" ;;
esac

current=$(sed -n 's/^MARKETING_VERSION = //p' "$XCCONFIG" | tr -d ' ')
build=$(sed -n 's/^CURRENT_PROJECT_VERSION = //p' "$XCCONFIG" | tr -d ' ')
[ -n "$current" ] && [ -n "$build" ] || die "cannot read the version out of $XCCONFIG"

# The highest build number recorded anywhere. A release that failed halfway
# through still left its tag or manifest behind, and the next one has to clear it.
highest=$build
for manifest in releases/*-build*.json; do
    [ -f "$manifest" ] || continue
    b=$(sed -n 's/.*"build": *\([0-9][0-9]*\).*/\1/p' "$manifest" | head -1)
    if [ -n "$b" ] && [ "$b" -gt "$highest" ]; then
        highest=$b
    fi
done
for tag in $(git tag -l 'v*-build*' 2>/dev/null); do
    b=${tag##*-build}
    case "$b" in ''|*[!0-9]*) continue ;; esac
    if [ "$b" -gt "$highest" ]; then
        highest=$b
    fi
done

if [ -n "$requested_build" ]; then
    case "$requested_build" in ''|*[!0-9]*) die "--build-number must be a positive integer" ;; esac
    [ "$requested_build" -gt "$highest" ] || die "--build-number must be greater than ${highest}"
    next_build=$requested_build
else
    next_build=$((highest + 1))
fi

IFS=. read -r major minor patch <<<"$current"
if [ "$part" = "build-only" ]; then
    version=$current
else
    case "$part" in
        patch) patch=$((patch + 1)) ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        major) major=$((major + 1)); minor=0; patch=0 ;;
    esac
    version="${major}.${minor}.${patch}"
fi

tag="v${version}-build${next_build}"
if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1; then
    die "tag ${tag} already exists; bump again or pass --build-number"
fi

printf 'version=%s\nbuild=%s\ntag=%s\n' "$version" "$next_build" "$tag"
