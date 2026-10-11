import 'package:flutter/foundation.dart';

/// Application version information required by the Inappify backend.
@immutable
class InappifyAppVersionInfo {
  const InappifyAppVersionInfo({
    required this.versionName,
    required this.versionCode,
  });

  final String versionName;
  final int versionCode;

  factory InappifyAppVersionInfo.fromMap(Map<String, dynamic> map) {
    final rawCode = map['versionCode'];
    final versionCode = rawCode is num
        ? rawCode.toInt()
        : int.tryParse(rawCode?.toString() ?? '');

    if (versionCode == null) {
      throw const FormatException('versionCode must be numeric.');
    }

    return InappifyAppVersionInfo(
      versionName: map['versionName']?.toString() ?? '',
      versionCode: versionCode,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'versionName': versionName,
    'versionCode': versionCode,
  };
}
