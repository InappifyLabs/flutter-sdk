import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/src/platform/mobile/native_required_platform.dart';

InappifySdkPlatform? createGoFallback() => null;
InappifySdkPlatform createFallback() => NativeRequiredPlatform();
