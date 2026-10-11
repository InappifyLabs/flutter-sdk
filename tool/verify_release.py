#!/usr/bin/env python3
"""Validate public beta metadata without reading private/local configuration."""
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
version = re.search(r"^version:\s*(\S+)", (ROOT / "pubspec.yaml").read_text(), re.M)[1]
assert re.fullmatch(r"\d+\.\d+\.\d+(?:-beta\.\d+)?", version), "Invalid SDK version"
assert f"const goV2SdkVersion = '{version}';" in (ROOT / "lib/src/platform/mobile/go_v2_protocol.dart").read_text()
assert f'com.github.InappifyLabs:kotlin-sdk:v{version}' in (ROOT / "android/build.gradle").read_text()
assert re.search(rf"s\.version\s*=\s*'{re.escape(version)}'", (ROOT / "ios/inappify_sdk.podspec").read_text())
assert re.search(rf":tag\s*=>\s*'v{re.escape(version)}'", (ROOT / "ios/inappify_sdk.podspec").read_text())
if os.environ.get("GITHUB_REF_TYPE") == "tag":
    assert os.environ["GITHUB_REF_NAME"] == f"v{version}", "Tag does not match package"
for relative in ["lib", "android/src", "ios/Classes"]:
    for source in (ROOT / relative).rglob("*"):
        if source.suffix in {".dart", ".kt", ".java", ".swift"}:
            assert "/app/v1/" not in source.read_text(), f"Old mobile route: {source}"
print(f"Release metadata consistent: {version} / v{version}")
