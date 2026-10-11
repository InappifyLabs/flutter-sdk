import 'dart:io';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_platform.dart';
import 'package:inappify_sdk/src/platform/mobile/native_required_platform.dart';

// Android must always use the native SDK; it must never silently switch to Dart.
InappifySdkPlatform? createGoFallback() =>
    Platform.isIOS ? GoV2Platform() : null;
InappifySdkPlatform createFallback() =>
    Platform.isIOS ? GoV2Platform() : NativeRequiredPlatform();
