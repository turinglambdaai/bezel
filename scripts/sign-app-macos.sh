#!/usr/bin/env bash
# sign-app-macos.sh — codesign + notarization helper for a packaged Bezel
# application on macOS.
#
# Signs every binary in the application folder with a "Developer ID
# Application" certificate (hardened runtime, timestamped), then — when a
# notarytool profile is given — submits the folder for notarization and
# staples the ticket. Adjust the folder layout to a .app bundle when your
# distribution uses one; the codesign step is identical.
#
# Usage:
#   ./scripts/sign-app-macos.sh dist/MyApp "Developer ID Application: ACME Inc (TEAMID)"
#   NOTARY_PROFILE=acme-notary ./scripts/sign-app-macos.sh dist/MyApp "Developer ID Application: ACME Inc (TEAMID)"
#
# The profile is created once with:
#   xcrun notarytool store-credentials acme-notary --apple-id ... --team-id ...

set -euo pipefail

app_dir="${1:?usage: sign-app-macos.sh <app-dir> <identity>}"
identity="${2:?usage: sign-app-macos.sh <app-dir> <identity>}"
profile="${NOTARY_PROFILE:-}"

# App bundles (.app from `raco bezel package`) are signed as bundles:
# innermost first, then the bundle seal. Plain folders are signed file
# by file (deepest first).
app_bundles=$(find "$app_dir" -name '*.app' -maxdepth 3 -type d || true)

if [[ -n "$app_bundles" ]]; then
    while IFS= read -r bundle; do
        echo "Signing bundle: $bundle (inside-out)"
        find "$bundle" -type f \( -name '*.dylib' -o -name '*.so' -perm -111 \) | sort -r |
        while IFS= read -r file; do
            codesign --force --timestamp --options runtime --sign "$identity" "$file"
        done
        codesign --force --timestamp --options runtime --sign "$identity" "$bundle"
        codesign --verify --strict "$bundle"
        echo "  signed: $bundle"
    done <<< "$app_bundles"
    notary_target=$(head -n1 <<< "$app_bundles")
else
    notary_target="$app_dir"
    targets=$(find "$app_dir" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -111 \) | sort -r)
    echo "Signing with: $identity"
    while IFS= read -r file; do
        codesign --force --timestamp --options runtime --sign "$identity" "$file"
        codesign --verify --strict "$file"
        echo "  signed: $file"
    done <<< "$targets"
fi

if [[ -n "$profile" ]]; then
    echo "Notarizing $notary_target (profile: $profile)"
    archive="$(mktemp -d)/app.zip"
    ditto -c -k --keepParent "$notary_target" "$archive"
    xcrun notarytool submit "$archive" --keychain-profile "$profile" --wait
    xcrun stapler staple "$notary_target"
    spctl -a -t execute -vv "$notary_target" || true
    echo "Notarization + stapling complete."
else
    echo "NOTARY_PROFILE not set — skipping notarization."
fi
