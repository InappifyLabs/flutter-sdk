import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/mobile_v2.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:inappify_sdk/session_state.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_snapshot.dart';

/// Mutable mirror used by the synchronous compatibility façade.
///
/// Persistence remains the responsibility of the selected SDK backend. This
/// object only mirrors the latest complete snapshot for existing Flutter code
/// that reads static fields synchronously.
class InappifySdkState {
  String? accessToken = '';
  String? apiKey = '';
  CustomerInfo? customerInfo;
  OfferingsModel? offerings;
  String? storeInfo;
  int? forceVersion = 1;
  int? appId;
  String country = 'IR';
  String versionName = '';
  int? versionCode;
  String? sdkVersion;
  InappifySessionState sessionState = InappifySessionState.unconfigured;
  InappifySessionPersistenceMode persistenceMode =
      InappifySessionPersistenceMode.unknown;
  bool failedToLoadOfferings = false;
  bool failedToLoadCustomerInfo = false;
  int? revision, storePlatform;
  bool? isConfigured, isAuthenticated, isLogoutPending;
  String? appUserIdentifier, market;
  InappifyMobileProtocol? mobileProtocol;

  InappifySdkSnapshot get snapshot => InappifySdkSnapshot(
    accessToken: accessToken,
    apiKey: apiKey,
    customerInfo: customerInfo,
    offerings: offerings,
    storeInfo: storeInfo,
    forceVersion: forceVersion,
    appId: appId,
    country: country,
    versionName: versionName,
    versionCode: versionCode,
    sdkVersion: sdkVersion,
    sessionState: sessionState,
    persistenceMode: persistenceMode,
    failedToLoadOfferings: failedToLoadOfferings,
    failedToLoadCustomerInfo: failedToLoadCustomerInfo,
    revision: revision,
    storePlatform: storePlatform,
    isConfigured: isConfigured,
    isAuthenticated: isAuthenticated,
    isLogoutPending: isLogoutPending,
    appUserIdentifier: appUserIdentifier,
    market: market,
    mobileProtocol: mobileProtocol,
  );

  /// Atomically replaces the mirrored values from one backend response.
  void apply(InappifySdkSnapshot next) {
    accessToken = next.accessToken;
    apiKey = next.apiKey;
    customerInfo = next.customerInfo;
    offerings = next.offerings;
    storeInfo = next.storeInfo;
    forceVersion = next.forceVersion;
    appId = next.appId;
    country = next.country;
    versionName = next.versionName;
    versionCode = next.versionCode;
    sdkVersion = next.sdkVersion;
    sessionState = next.sessionState;
    persistenceMode = next.persistenceMode;
    failedToLoadOfferings = next.failedToLoadOfferings;
    failedToLoadCustomerInfo = next.failedToLoadCustomerInfo;
    revision = next.revision;
    storePlatform = next.storePlatform;
    isConfigured = next.isConfigured;
    isAuthenticated = next.isAuthenticated;
    isLogoutPending = next.isLogoutPending;
    appUserIdentifier = next.appUserIdentifier;
    market = next.market;
    mobileProtocol = next.mobileProtocol;
  }
}
