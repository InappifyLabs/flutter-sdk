import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/local/local_storage.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('preserves legacy preference keys and awaits writes', () async {
    await LocalStorage.saveToken(token: 'token');
    await LocalStorage.saveAppUserIdentifier(appUserIdentifier: 'customer-1');
    await LocalStorage.saveCustomerInfo(
      customerInfo: CustomerInfo(originalAppUserId: 'customer-1'),
    );
    await LocalStorage.saveOfferings(offerings: OfferingsModel());
    await LocalStorage.saveDateTimeForCustomerInfo();
    await LocalStorage.saveForceVersion(forceVersion: 7);
    await LocalStorage.saveAppId(appId: 23);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('token'), 'token');
    expect(preferences.getString('appUserIdentifier'), 'customer-1');
    expect(preferences.getString('customerInfo'), isNotEmpty);
    expect(preferences.getString('offerings'), isNotEmpty);
    expect(preferences.getString('dateTimeCustomerInfo'), isNotEmpty);
    expect(preferences.getInt('forceVersion'), 7);
    expect(preferences.getInt('appId'), 23);
  });

  test('reads values through the same migration-compatible schema', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'token': 'token',
      'appUserIdentifier': 'customer-1',
      'forceVersion': 7,
      'appId': 23,
    });

    expect(await LocalStorage.getToken(), 'token');
    expect(await LocalStorage.getAppUserIdentifier(), 'customer-1');
    expect(await LocalStorage.getForceVersion(), 7);
    expect(await LocalStorage.getAppId(), 23);
  });
}
