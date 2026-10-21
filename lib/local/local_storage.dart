import 'package:inappify_sdk/src/logging/sdk_logger.dart';
import 'dart:convert';

import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence used exclusively by the legacy Dart backend.
///
/// Preference keys are migration-sensitive and must remain stable until a
/// separately tested storage migration is introduced.
class LocalStorage {
  static Future<void> saveAppUserIdentifier(
      {required String appUserIdentifier}) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('appUserIdentifier', appUserIdentifier);
    } catch (e) {
      SdkLogger.error('Inappify storage write failed: ${e.runtimeType}');
    }
  }

  static Future<String?> getAppUserIdentifier() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString('appUserIdentifier');
    } catch (e) {
      SdkLogger.error('Inappify storage read failed: ${e.runtimeType}');
      return null;
    }
  }

  static Future<void> saveToken({required String token}) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
    } catch (e) {
      SdkLogger.error('Inappify storage write failed: ${e.runtimeType}');
    }
  }

  static Future<String?> getToken() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString('token');
    } catch (e) {
      SdkLogger.error('Inappify storage read failed: ${e.runtimeType}');
      return null;
    }
  }

  static Future<void> saveCustomerInfo(
      {required CustomerInfo customerInfo}) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('customerInfo', jsonEncode(customerInfo.toJson()));
    } catch (e) {
      SdkLogger.error('Inappify storage write failed: ${e.runtimeType}');
    }
  }

  static Future<CustomerInfo?> getCustomerInfo() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? customerInfoData = prefs.getString('customerInfo');
      if (customerInfoData?.isNotEmpty ?? false) {
        return CustomerInfo.fromJson(jsonDecode(customerInfoData!));
      }

      return null;
    } catch (e) {
      SdkLogger.error('Inappify storage read failed: ${e.runtimeType}');
      return null;
    }
  }

  static Future<void> clearCustomerInfo() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('customerInfo');
    } catch (e) {
      SdkLogger.error('Inappify storage clear failed: ${e.runtimeType}');
    }
  }

  static Future<void> saveOfferings(
      {required OfferingsModel? offerings}) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('offerings', jsonEncode(offerings?.toJson()));
    } catch (e) {
      SdkLogger.error('Inappify storage write failed: ${e.runtimeType}');
    }
  }

  static Future<OfferingsModel?> getOfferings() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? offeringsData = prefs.getString('offerings');
      if (offeringsData?.isNotEmpty ?? false) {
        return OfferingsModel.fromJson(jsonDecode(offeringsData!));
      }

      return null;
    } catch (e) {
      SdkLogger.error('Inappify storage read failed: ${e.runtimeType}');
      return null;
    }
  }

  static Future<void> saveDateTimeForCustomerInfo() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'dateTimeCustomerInfo',
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      SdkLogger.error('Inappify storage write failed: ${e.runtimeType}');
    }
  }

  static Future<DateTime?> getSavedDateTime() async {
    final prefs = await SharedPreferences.getInstance();
    final dateString = prefs.getString('dateTimeCustomerInfo');
    if (dateString != null) {
      return DateTime.parse(dateString);
    }
    return null;
  }

  static Future<void> saveForceVersion({required int forceVersion}) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt('forceVersion', forceVersion);
    } catch (e) {
      SdkLogger.error('Inappify storage write failed: ${e.runtimeType}');
    }
  }

  static Future<int?> getForceVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final forceVersion = prefs.getInt('forceVersion');
    return forceVersion;
  }

  static Future<void> saveAppId({required int appId}) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt('appId', appId);
    } catch (e) {
      SdkLogger.error('Inappify storage write failed: ${e.runtimeType}');
    }
  }

  static Future<int?> getAppId() async {
    final prefs = await SharedPreferences.getInstance();
    final appId = prefs.getInt('appId');
    return appId;
  }
}
