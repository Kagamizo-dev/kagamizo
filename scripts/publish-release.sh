#!/usr/bin/env bash
# Create or update a GitHub release whose tag follows the commit being built, so
# the asset URL stays the same while the content moves.
# Usage: publish-release.sh <tag> <title> <--prerelease|--latest> <asset-file>
# Needs GH_TOKEN, REPO (owner/name), GITHUB_SHA in the environment.
set -euo pipefail

tag=$1
title=$2
kind=$3
asset=$4

notes="Flash the .iso straight to a USB stick (EtchDroid / dd). Live and ephemeral: nothing is written to the laptop. Passed: flake checks + UEFI boot test. Built from commit $GITHUB_SHA."

if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
  # Keep the URL, move the tag to the commit this ISO was built from.
  gh api -X PATCH "repos/$REPO/git/refs/tags/$tag" -f sha="$GITHUB_SHA" -F force=true >/dev/null
else
  gh release create "$tag" --repo "$REPO" --target "$GITHUB_SHA" --title "$title" "$kind" --notes "$notes"
fi
gh release upload "$tag" "$asset" --repo "$REPO" --clobber
gh release edit "$tag" --repo "$REPO" --title "$title" --notes "$notes" "$kind"
