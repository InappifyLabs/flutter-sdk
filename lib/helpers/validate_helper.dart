import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/models/attribute.dart';

class ValidateHelper {
  static bool isValidAttribute({
    required Attribute attribute,
  }) {
    try {
      final regex = RegExp(r'^(?!\$)[a-zA-Z0-9_-]+$');
      return regex.hasMatch(attribute.key ?? '') &&
          (attribute.key?.isNotEmpty ?? false) &&
          ((attribute.key?.length ?? 0) <= 40) &&
          ((attribute.value?.length ?? 0) <= 250);
    } catch (e) {
      debugPrint('Inappify attribute validation failed: ${e.runtimeType}');
      return false;
    }
  }

  static bool isValidEmail({
    required String email,
  }) {
    try {
      final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
      return email.isEmpty || regex.hasMatch(email);
    } catch (e) {
      debugPrint('Inappify email validation failed: ${e.runtimeType}');
      return false;
    }
  }

  static bool validateStringData({
    required String data,
  }) {
    try {
      return data.isEmpty || data.length <= 250;
    } catch (e) {
      debugPrint('Inappify string validation failed: ${e.runtimeType}');
      return false;
    }
  }
}
