#!/bin/sh
# Installs the OpenNotch.app CI built for a commit (default: the head of PR #1) into /Applications.
# Usage: Scripts/install-ci-build.sh [--open] [commit]
set -eu

repo=rabbive/OpenNotch
app=/Applications/OpenNotch.app

fail() {
    echo "install-ci-build: $*" >&2
    exit 1
}

open_after=false
commit=
for arg in "$@"; do
    case $arg in
        --open) open_after=true ;;
        -h | --help) sed -n '2,3s/^# //p' "$0"; exit 0 ;;
        -*) fail "unknown option $arg" ;;
        *) commit=$arg ;;
    esac
done

command -v gh >/dev/null || fail "needs the GitHub CLI (brew install gh, then gh auth login)"
commit=${commit:-$(gh pr view 1 --repo "$repo" --json headRefOid --jq .headRefOid)}
sha=$(gh api "repos/$repo/commits/$commit" --jq .sha)

run=$(gh api -X GET "repos/$repo/actions/runs" -f head_sha="$sha" \
    --jq '[.workflow_runs[] | select(.path == ".github/workflows/ci.yml")][0].id // empty')
[ -n "$run" ] || fail "no CI run found for $sha"
state=$(gh api "repos/$repo/actions/runs/$run/jobs" \
    --jq '.jobs[] | select(.name == "macOS 27, Xcode 27") | .conclusion // .status')
[ "$state" = success ] ||
    fail "the macOS 27 CI job for $sha is '${state:-missing}', not success, so nothing was installed. See https://github.com/$repo/actions/runs/$run"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gh run download "$run" --repo "$repo" --name "OpenNotch-$sha" --dir "$tmp"
ditto -x -k "$tmp/OpenNotch.zip" "$tmp"
[ -d "$tmp/OpenNotch.app" ] || fail "the CI artifact has no OpenNotch.app"

# OpenNotch saves its state after every change and does nothing at quit, so SIGTERM is as safe as Quit.
if pkill -x OpenNotch; then
    tries=0
    while pgrep -x OpenNotch >/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -le 50 ] || fail "the running OpenNotch did not quit"
        sleep 0.1
    done
    echo "Quit the running OpenNotch."
fi

rm -rf "$app"
ditto "$tmp/OpenNotch.app" "$app"
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
if xattr -p com.apple.quarantine "$app" >/dev/null 2>&1; then
    fail "could not clear com.apple.quarantine on $app"
fi

echo "Installed OpenNotch from commit $sha into $app"
echo "CI run: https://github.com/$repo/actions/runs/$run"
if $open_after; then
    open "$app"
else
    echo "Not opened. Run: open $app"
fi
