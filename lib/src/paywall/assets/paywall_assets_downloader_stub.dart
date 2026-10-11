import 'package:inappify_sdk/models/paywall_asset.dart';

/// Browser-safe asset cache implementation.
///
/// Browser HTTP caching remains authoritative, so paywall widgets use the
/// original network URL and no local file-system path is created.
Future<void> downloadAllAssets(List<PaywallAsset> assets) async {}

Future<String?> getLocalAssetPath(String url) async => null;

Future<void> clearCache() async {}

Future<int> getCacheSize() async => 0;

Future<bool> isAssetCached(String url) async => false;

int getCachedAssetCount() => 0;
