import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:inappify_sdk/models/paywall_asset.dart';

/// File-system-backed paywall asset cache for Dart IO runtimes.
///
/// Browser builds never import this implementation. Cache filenames are
/// deterministic URL hashes and no remote URL content is written to logs.
abstract final class PaywallAssetsDownloaderIo {
  static const String _cacheFolderName = 'paywall_assets';
  static final Map<String, String> _urlToPathCache = {};
  static final Map<String, bool> _downloadInProgress = {};

  /// Download all assets from paywall data
  static Future<void> downloadAllAssets(List<PaywallAsset> assets) async {
    try {
      debugPrint('Starting download of ${assets.length} assets');

      // Filter only asset type assets (images, etc.)
      final downloadableAssets = assets
          .where((asset) => asset.type == 'assets')
          .toList();

      if (downloadableAssets.isEmpty) {
        debugPrint('No downloadable assets found');
        return;
      }

      // Create cache directory if it doesn't exist
      await _ensureCacheDirectory();

      // Download all assets concurrently
      final futures = downloadableAssets.map((asset) => _downloadAsset(asset));
      await Future.wait(futures);

      debugPrint('All assets downloaded successfully');
    } catch (error) {
      debugPrint('Paywall asset caching failed: ${error.runtimeType}');
    }
  }

  /// Download a single asset
  static Future<void> _downloadAsset(PaywallAsset asset) async {
    if (asset.url == null || asset.url!.isEmpty) {
      debugPrint('Asset ${asset.id} has no URL');
      return;
    }

    final url = asset.url!;

    // Check if already downloaded
    if (_urlToPathCache.containsKey(url)) {
      debugPrint('Asset ${asset.id} already cached');
      return;
    }

    // Check if download is in progress
    if (_downloadInProgress[url] == true) {
      debugPrint('Asset ${asset.id} download already in progress');
      return;
    }

    try {
      _downloadInProgress[url] = true;
      debugPrint('Downloading paywall asset ${asset.id}.');

      // Download the asset
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      // Read the response
      final bytes = await _consolidateHttpClientResponseBytes(response);

      // Save to local storage
      final localPath = await _saveAssetToLocal(url, bytes);

      // Cache the path
      _urlToPathCache[url] = localPath;

      debugPrint('Paywall asset ${asset.id} cached.');
    } catch (error) {
      debugPrint('Paywall asset download failed: ${error.runtimeType}');
    } finally {
      _downloadInProgress[url] = false;
    }
  }

  /// Get local path for an asset URL
  static Future<String?> getLocalAssetPath(String url) async {
    // Check memory cache first
    if (_urlToPathCache.containsKey(url)) {
      final path = _urlToPathCache[url]!;
      final file = File(path);
      if (await file.exists()) {
        return path;
      } else {
        // Remove from cache if file doesn't exist
        _urlToPathCache.remove(url);
      }
    }

    // Check disk cache
    final cacheKey = _generateCacheKey(url);
    final cacheDir = await _getCacheDirectory();
    final file = File('${cacheDir.path}/$cacheKey');

    if (await file.exists()) {
      _urlToPathCache[url] = file.path;
      return file.path;
    }

    return null;
  }

  /// Save asset to local storage
  static Future<String> _saveAssetToLocal(String url, Uint8List bytes) async {
    final cacheKey = _generateCacheKey(url);
    final cacheDir = await _getCacheDirectory();
    final file = File('${cacheDir.path}/$cacheKey');

    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Generate cache key from URL
  static String _generateCacheKey(String url) {
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Ensure cache directory exists
  static Future<void> _ensureCacheDirectory() async {
    final cacheDir = await _getCacheDirectory();
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
  }

  /// Get cache directory
  static Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/$_cacheFolderName');
  }

  /// Clear all cached assets
  static Future<void> clearCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      _urlToPathCache.clear();
      _downloadInProgress.clear();
      debugPrint('Cache cleared successfully');
    } catch (error) {
      debugPrint('Paywall cache clear failed: ${error.runtimeType}');
    }
  }

  /// Get cache size
  static Future<int> getCacheSize() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (!await cacheDir.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      return totalSize;
    } catch (error) {
      debugPrint('Paywall cache size read failed: ${error.runtimeType}');
      return 0;
    }
  }

  /// Check if asset is cached
  static Future<bool> isAssetCached(String url) async {
    final localPath = await getLocalAssetPath(url);
    return localPath != null;
  }

  /// Get cached asset count
  static int getCachedAssetCount() {
    return _urlToPathCache.length;
  }

  /// Consolidate HTTP client response bytes
  static Future<Uint8List> _consolidateHttpClientResponseBytes(
    HttpClientResponse response,
  ) async {
    final List<int> bytes = [];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  }
}

Future<void> downloadAllAssets(List<PaywallAsset> assets) {
  return PaywallAssetsDownloaderIo.downloadAllAssets(assets);
}

Future<String?> getLocalAssetPath(String url) {
  return PaywallAssetsDownloaderIo.getLocalAssetPath(url);
}

Future<void> clearCache() => PaywallAssetsDownloaderIo.clearCache();

Future<int> getCacheSize() => PaywallAssetsDownloaderIo.getCacheSize();

Future<bool> isAssetCached(String url) {
  return PaywallAssetsDownloaderIo.isAssetCached(url);
}

int getCachedAssetCount() => PaywallAssetsDownloaderIo.getCachedAssetCount();
