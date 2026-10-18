# Releasing

Flutter package/mobile version `0.1.1` is tagged `v0.1.1`. Android pins the independently published Kotlin SDK's exact corresponding tag. The JavaScript provider version is independent and must not be reset to the Flutter version.

1. Publish and validate the corresponding Kotlin SDK tag on GitHub/JitPack before publishing Flutter. Update `pubspec.yaml`, `goV2SdkVersion`, Android's exact JitPack dependency and version metadata, the podspec version/source tag, relevant expectations, and current installation snippets. Use `major.minor.patch` for stable releases and `major.minor.patch-beta.N` for beta releases.
2. Run `python3 tool/verify_release.py`, all Flutter tests and static analysis, Android bridge tests, and example builds. On macOS compile the iOS simulator example. Verify the actual resolved native AAR and its release digest; do not substitute a local Maven build when claiming public availability.
3. Review the tracked file list and the new repository's documentation. Exclude build output, package locks, credentials, private host applications, and local configuration. Keep license and third-party notices accurate.
4. Commit the reviewed source. Create a new annotated tag `v<package-version>` and push `main` and that tag with a normal atomic push. Never move a previously published tag.
5. Check CI for the exact release commit. Create a GitHub stable release with **prerelease disabled**, current behavior and validation notes. Use prerelease status only for beta versions. A GitHub release and Git dependency are separate from pub.dev publishing.
6. Resolve the Git tag from an independent consumer and verify that the Flutter package version and Android Kotlin dependency match. Record any device/backend checks separately from compilation.

## Publish to pub.dev

Use Flutter 3.44.0 / Dart 3.12.0 or newer. Ensure `LICENSE` contains Apache-2.0,
review the installation instructions, and run `flutter pub publish --dry-run`.
This preflight checks the package layout and publication contents; it does not
run the project test suites. Commit the reviewed package before publishing.

Run `flutter pub publish` and authenticate with the Google Account that will own
the package. Review and confirm the upload. After publication, consumers can use
`inappify_sdk: ^0.1.1`. The first upload can subsequently be transferred to a
verified publisher through pub.dev.

GitHub tags remain available for Git consumers. Pub.dev uploads are made from the
reviewed source tree; never move an existing Git tag when preparing publication.
