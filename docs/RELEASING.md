# Releasing

Flutter package/mobile version `0.1.0-beta.0` is tagged `v0.1.0-beta.0`. Android pins the independently published Kotlin SDK's exact corresponding tag. The JavaScript provider version is independent and must not be reset to the Flutter version.

1. Update `pubspec.yaml`, `goV2SdkVersion`, Android's exact JitPack dependency and version metadata, the podspec version/source tag, relevant expectations, and current installation snippets. Use `major.minor.patch-beta.N` for this beta series.
2. Run `python3 tool/verify_release.py`, all Flutter tests and static analysis, Android bridge tests, and example builds. On macOS compile the iOS simulator example. Verify the actual resolved native AAR and its release digest; do not substitute a local Maven build when claiming public availability.
3. Review the tracked file list and the new repository's documentation. Exclude build output, package locks, credentials, private host applications, and local configuration. Keep license and third-party notices accurate.
4. Commit the reviewed source. Create a new annotated tag `v<package-version>` and push `main` and that tag with a normal atomic push. Never move a previously published tag.
5. Check CI for the exact release commit. Create a GitHub **prerelease** with current behavior and validation notes. A GitHub release and Git dependency are separate from pub.dev publishing.
6. Resolve the Git tag from an independent consumer and verify that the Flutter package version and Android Kotlin dependency match. Record any device/backend checks separately from compilation.

This repository is distributed through GitHub/Git for the initial beta. It is not an announcement of a pub.dev release. Public consumers install the Git URL and tag shown in the [getting started guide](GETTING_STARTED.md).
