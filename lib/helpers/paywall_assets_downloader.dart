import 'package:inappify_sdk/models/paywall_asset.dart';
import 'package:inappify_sdk/src/paywall/assets/paywall_assets_downloader_stub.dart'
    if (dart.library.io) 'package:inappify_sdk/src/paywall/assets/paywall_assets_downloader_io.dart'
    as implementation;

/// Cross-platform façade for optional paywall asset caching.
///
/// Native Dart runtimes use a file-system cache. Browser builds intentionally
/// return network URLs so no `dart:io` or `path_provider` type can enter the Web
/// dependency graph.
class PaywallAssetsDownloader {
  /// Preloads cacheable paywall assets supported by the current runtime.
  static Future<void> downloadAllAssets(List<PaywallAsset> assets) {
    return implementation.downloadAllAssets(assets);
  }

  /// Returns a local file path on IO runtimes, or `null` in browsers.
  static Future<String?> getLocalAssetPath(String url) {
    return implementation.getLocalAssetPath(url);
  }

  /// Removes cached paywall files for the active runtime.
  static Future<void> clearCache() => implementation.clearCache();

  /// Returns the cache size in bytes, or zero when no file cache exists.
  static Future<int> getCacheSize() => implementation.getCacheSize();

  /// Returns whether [url] currently has a local cached representation.
  static Future<bool> isAssetCached(String url) {
    return implementation.isAssetCached(url);
  }

  /// Returns the number of assets tracked by the in-memory cache index.
  static int getCachedAssetCount() => implementation.getCachedAssetCount();
}
