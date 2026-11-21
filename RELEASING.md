# Releasing DockStay

Requirements include Swift 6/Xcode, Python 3, GitHub CLI, a Developer ID Application signing identity, a working `notarytool` Keychain profile, and access to the DockStay Sparkle Ed25519 signing key. Keep private keys, passwords, and local credential files outside Git.

## One-time updater setup

DockStay distributes updates through [liquorice-head/dockstay-macos](https://github.com/liquorice-head/dockstay-macos). The release assets and appcast must be downloadable anonymously. The app uses no GitHub credentials.

1. Run `swift package resolve`. Sparkle is pinned in `Package.swift` and `Package.resolved`.
2. On the signing machine, run `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account DockStay -p` to display the existing public key. Verify that it matches `SUPublicEDKey` in `Resources/Info.plist`. Use the same private key for future releases. On a new signing machine, securely restore that key to the DockStay account in Keychain before generating the appcast.
3. `SUFeedURL` in `Resources/Info.plist` points to `https://github.com/liquorice-head/dockstay-macos/releases/latest/download/appcast.xml`. Every stable release must include `appcast.xml` and its signed ZIP as assets. Keep this URL working for installed clients even if source code moves later.
4. The build script uses the committed public feed URL and public key by default. For a test feed, override both together with `UPDATE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY`.

Sparkle is embedded with its license, preserving symlinks and executable modes. The build script signs its helper executables, XPC services, updater app, and framework before signing DockStay. Both update checking and installation are manual; background checks, silent installs, and profiling are disabled in `Info.plist`. See [Sparkle's setup guide](https://sparkle-project.org/documentation/) and [publishing guide](https://sparkle-project.org/documentation/publishing/).

## Each release

1. Ensure the working tree is clean and update the version/build in `Resources/Info.plist` when making a new release. Commit all release source changes.
2. Run `swift test` and `git diff --check`.
3. Build an Apple Silicon app into a separate output directory.

   ```sh
   BUILD_OUTPUT_DIR="$PWD/dist/VERSION" \
     CODE_SIGN_IDENTITY='Developer ID Application: YOUR IDENTITY' \
     bash scripts/build.sh
   ```

4. Verify the `arm64` architecture with `lipo -archs dist/VERSION/DockStay.app/Contents/MacOS/DockStay`, and verify all nested signatures with `codesign --verify --deep --strict dist/VERSION/DockStay.app`. Confirm `SUFeedURL` and `SUPublicEDKey` match the public repository and signing key.
5. Create a submission archive, submit it using stored credentials, and wait for the existing submission to be accepted:

   ```sh
   ditto -c -k --keepParent dist/VERSION/DockStay.app dist/VERSION/submission.zip
   xcrun notarytool submit dist/VERSION/submission.zip \
     --keychain-profile YOUR_PROFILE --output-format json
   xcrun notarytool info SUBMISSION_ID --keychain-profile YOUR_PROFILE
   ```

   Do not resubmit while processing is still in progress. If rejected, fetch the notarization log and fix the reported issue before continuing.

6. Staple and validate the Apple ticket, then assess the final app with Gatekeeper:

   ```sh
   xcrun stapler staple dist/VERSION/DockStay.app
   xcrun stapler validate dist/VERSION/DockStay.app
   codesign --verify --strict dist/VERSION/DockStay.app
   spctl --assess --type execute --verbose=2 dist/VERSION/DockStay.app
   ```

7. Re-create the final ZIP from the stapled app as `DockStay-VERSION-arm64.zip`. Extract it to a temporary directory and verify the signature, stapled ticket, executable mode, architecture, and version again.
8. Stage a copy of the stapled app in a temporary folder with an `Applications` symlink pointing to `/Applications`. Use `hdiutil create -srcfolder STAGING_DIR -volname DockStay -format UDZO dist/VERSION/DockStay-VERSION-arm64.dmg`. Sign the DMG with the same Developer ID identity and `--timestamp`, submit it for notarization, then staple and validate its ticket. Mount it read-only and verify the app and Applications symlink. Generate `SHA256SUMS.txt` for the final DMG and ZIP after stapling.
9. Run `bash scripts/generate-appcast.sh liquorice-head/dockstay-macos VERSION` with the numeric version, such as `0.1.3`. This signs the final ZIP using the Sparkle key in Keychain and generates `dist/VERSION/appcast.xml`. Keep `dist/appcast/` between releases to retain previous feed entries. On another machine, restore the previous public `appcast.xml` to that directory first. Review the feed's version, minimum system version, signature, archive length, and version-specific GitHub download URL.
10. Push the exact source commit. Create a draft GitHub release for `vVERSION`, targeting that full commit SHA, and upload the final DMG, ZIP, checksum file, and appcast. Release notes must state the requirements and any unverified hardware behavior.
11. Download the draft assets to a fresh directory and verify their checksums before publishing the release. After publication, verify the stable feed URL and version-specific ZIP URL work without authentication.

Before advertising working updates, test a real update between two Developer ID signed, notarized builds with increasing `CFBundleVersion`: install the older build in Applications, use **Check for Updates…**, cancel once, then install and relaunch. Verify the display selection and disabled blocking state survive. Also test an unavailable feed and an archive with a bad signature; neither may replace the app. This end-to-end test requires the public feed and signing key, and is separate from unit/build checks.

CI artifacts are ad-hoc signed development builds. Publish the separately signed and notarized release ZIP, not a CI artifact. Build outputs and notarization receipts remain in ignored `dist/`.
