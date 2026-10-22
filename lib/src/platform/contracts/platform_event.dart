import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_snapshot.dart';
import 'package:inappify_sdk/models/purchase_attempt.dart';

/// Asynchronous state changes emitted by JavaScript or native SDKs.
enum InappifyPlatformEventType {
  stateChanged,
  customerInfoChanged,
  offeringsChanged,
  authenticationChanged,
  sessionStateChanged,
  purchaseUpdated,
}

/// Event emitted outside the direct lifetime of a platform method call.
///
/// This is the extension point for browser redirect callbacks and a future
/// native EventChannel. [requestId] correlates purchase updates with the
/// request envelope that started the operation.
@immutable
class InappifyPlatformEvent {
  const InappifyPlatformEvent({
    required this.type,
    this.requestId,
    this.snapshot,
    this.data = const <String, Object?>{},
    this.purchaseAttempt,
  });

  final InappifyPlatformEventType type;
  final String? requestId;
  final InappifySdkSnapshot? snapshot;
  final Map<String, Object?> data;

  /// Present on new Android purchase/recovery events; absent on legacy events.
  final InappifyPurchaseAttempt? purchaseAttempt;
}
