import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/src/bootstrap/inappify_sdk_runtime.dart';

void main() {
  late InappifySdkPlatform originalPlatform;
  late _RecoveryPlatform platform;

  setUp(() async {
    originalPlatform = InappifySdkPlatform.instance;
    platform = _RecoveryPlatform();
    await InappifySdkRuntime.coordinator.resetForTesting();
    InappifySdkPlatform.instance = platform;
  });

  tearDown(() async {
    await Future<void>.delayed(Duration.zero);
    await InappifySdkRuntime.coordinator.resetForTesting();
    InappifySdkPlatform.instance = originalPlatform;
    await platform.dispose();
  });

  test(
    'recovery configures anonymous transport before requesting one ticket',
    () async {
      platform.configureResults.addAll(<InappifySdkResult<void>>[
        InappifySdkResult<void>.failure(
          const InappifyFailure(
            code: InappifyFailureCode.sessionRecoveryRequired,
            message: 'Recovery required.',
          ),
          snapshot: _webSnapshot(InappifySessionState.recoveryRequired),
        ),
        InappifySdkResult<void>.success(
          snapshot: _webSnapshot(InappifySessionState.anonymous),
        ),
      ]);
      platform.exchangeResult =
          InappifySdkResult<InappifyAuthenticationResult>.success(
            data: const InappifyAuthenticationResult(
              isAnonymous: false,
              type: 'Authenticated',
            ),
            snapshot: _webSnapshot(InappifySessionState.authenticated),
          );

      final result = await InappifySdk.configureAuthenticatedWebSessionResult(
        apiKey: 'public-web-key-recovery',
        identityTicketProvider: () async {
          platform.order.add('ticket');
          return 'one-time-ticket';
        },
      );

      expect(result.isSuccess, isTrue);
      expect(platform.configureCalls, 2);
      expect(platform.exchangeCalls, 1);
      expect(platform.receivedTickets, <String>['one-time-ticket']);
      expect(platform.order, <String>[
        'configure',
        'configure',
        'ticket',
        'exchange',
      ]);
      expect(InappifySdk.sessionState, InappifySessionState.authenticated);
    },
  );

  test(
    'transient configure failure never requests an Identity Ticket',
    () async {
      platform.configureResults.add(
        InappifySdkResult<void>.failure(
          const InappifyFailure(
            code: InappifyFailureCode.network,
            message: 'Network unavailable.',
            isRetryable: true,
          ),
          snapshot: _webSnapshot(
            InappifySessionState.temporarilyUnavailable,
            customerId: 'last-authoritative-customer',
          ),
        ),
      );
      var providerCalls = 0;

      final result = await InappifySdk.configureAuthenticatedWebSessionResult(
        apiKey: 'public-web-key-transient',
        identityTicketProvider: () async {
          providerCalls += 1;
          return 'must-not-be-created';
        },
      );

      expect(result.failure?.code, InappifyFailureCode.network);
      expect(providerCalls, 0);
      expect(platform.exchangeCalls, 0);
      expect(
        result.snapshot?.customerInfo?.originalAppUserId,
        'last-authoritative-customer',
      );
    },
  );

  test('an already authenticated session does not consume a ticket', () async {
    platform.configureResults.add(
      InappifySdkResult<void>.success(
        snapshot: _webSnapshot(InappifySessionState.authenticated),
      ),
    );
    var providerCalls = 0;

    final result = await InappifySdk.configureAuthenticatedWebSessionResult(
      apiKey: 'public-web-key-authenticated',
      identityTicketProvider: () async {
        providerCalls += 1;
        return 'must-not-be-created';
      },
    );

    expect(result.isSuccess, isTrue);
    expect(providerCalls, 0);
    expect(platform.exchangeCalls, 0);
  });

  test(
    'a restored session for another host user exchanges a fresh ticket',
    () async {
      platform.configureResults.add(
        InappifySdkResult<void>.success(
          snapshot: _webSnapshot(
            InappifySessionState.authenticated,
            customerId: 'previous-host-user',
          ),
        ),
      );
      platform.exchangeResult =
          InappifySdkResult<InappifyAuthenticationResult>.success(
            data: const InappifyAuthenticationResult(isAnonymous: false),
            snapshot: _webSnapshot(
              InappifySessionState.authenticated,
              customerId: 'current-host-user',
            ),
          );

      final result = await InappifySdk.configureAuthenticatedWebSessionResult(
        apiKey: 'public-web-key-account-switch',
        expectedCustomerIdentifier: 'current-host-user',
        identityTicketProvider: () async => 'fresh-account-switch-ticket',
      );

      expect(result.isSuccess, isTrue);
      expect(platform.exchangeCalls, 1);
      expect(platform.receivedTickets, <String>['fresh-account-switch-ticket']);
    },
  );

  test('an exchanged session for the wrong host user is rejected', () async {
    platform.configureResults.add(
      InappifySdkResult<void>.success(
        snapshot: _webSnapshot(InappifySessionState.anonymous),
      ),
    );
    platform.exchangeResult =
        InappifySdkResult<InappifyAuthenticationResult>.success(
          data: const InappifyAuthenticationResult(isAnonymous: false),
          snapshot: _webSnapshot(
            InappifySessionState.authenticated,
            customerId: 'unexpected-host-user',
          ),
        );

    final result = await InappifySdk.configureAuthenticatedWebSessionResult(
      apiKey: 'public-web-key-identity-mismatch',
      expectedCustomerIdentifier: 'expected-host-user',
      identityTicketProvider: () async => 'fresh-ticket',
    );

    expect(result.failure?.code, InappifyFailureCode.identityMismatch);
    expect(platform.exchangeCalls, 1);
  });

  test(
    'concurrent authenticated configure calls consume only one ticket',
    () async {
      platform.configureResults.add(
        InappifySdkResult<void>.success(
          snapshot: _webSnapshot(InappifySessionState.anonymous),
        ),
      );
      platform.exchangeResult =
          InappifySdkResult<InappifyAuthenticationResult>.success(
            data: const InappifyAuthenticationResult(isAnonymous: false),
            snapshot: _webSnapshot(InappifySessionState.authenticated),
          );
      final ticketPending = Completer<String>();
      var providerCalls = 0;

      final first = InappifySdk.configureAuthenticatedWebSessionResult(
        apiKey: 'public-web-key-concurrent',
        identityTicketProvider: () {
          providerCalls += 1;
          return ticketPending.future;
        },
      );
      final second = InappifySdk.configureAuthenticatedWebSessionResult(
        apiKey: 'public-web-key-concurrent',
        identityTicketProvider: () async => 'second-ticket-must-not-be-used',
      );
      await Future<void>.delayed(Duration.zero);

      expect(providerCalls, 1);
      expect(platform.configureCalls, 1);
      ticketPending.complete('shared-ticket');

      expect((await first).isSuccess, isTrue);
      expect((await second).isSuccess, isTrue);
      expect(platform.exchangeCalls, 1);
      expect(platform.receivedTickets, <String>['shared-ticket']);
    },
  );

  test(
    'ambiguous ticket exchange is reconciled without retrying the ticket',
    () async {
      platform.configureResults.add(
        InappifySdkResult<void>.success(
          snapshot: _webSnapshot(InappifySessionState.anonymous),
        ),
      );
      platform.exchangeResult =
          InappifySdkResult<InappifyAuthenticationResult>.failure(
            const InappifyFailure(
              code: InappifyFailureCode.network,
              message: 'Post-exchange refresh failed.',
              isRetryable: true,
              details: <String, Object?>{'outcomeMayHaveCommitted': true},
            ),
            snapshot: _webSnapshot(InappifySessionState.authenticated),
          );
      platform.customerResult = InappifySdkResult<CustomerInfo>.success(
        data: CustomerInfo(originalAppUserId: 'authenticated-customer'),
        snapshot: _webSnapshot(
          InappifySessionState.authenticated,
          customerId: 'authenticated-customer',
        ),
      );

      final result = await InappifySdk.configureAuthenticatedWebSessionResult(
        apiKey: 'public-web-key-ambiguous',
        identityTicketProvider: () async => 'single-use-ticket',
      );

      expect(result.isSuccess, isTrue);
      expect(platform.exchangeCalls, 1);
      expect(platform.customerCalls, 1);
      expect(platform.receivedTickets, <String>['single-use-ticket']);
    },
  );

  test(
    'ambiguous exchange reconciliation still verifies the host identity',
    () async {
      platform.configureResults.add(
        InappifySdkResult<void>.success(
          snapshot: _webSnapshot(InappifySessionState.anonymous),
        ),
      );
      platform.exchangeResult =
          InappifySdkResult<InappifyAuthenticationResult>.failure(
            const InappifyFailure(
              code: InappifyFailureCode.network,
              message: 'Post-exchange refresh failed.',
              isRetryable: true,
              details: <String, Object?>{'outcomeMayHaveCommitted': true},
            ),
            snapshot: _webSnapshot(InappifySessionState.authenticated),
          );
      platform.customerResult = InappifySdkResult<CustomerInfo>.success(
        data: CustomerInfo(originalAppUserId: 'unexpected-host-user'),
        snapshot: _webSnapshot(
          InappifySessionState.authenticated,
          customerId: 'unexpected-host-user',
        ),
      );

      final result = await InappifySdk.configureAuthenticatedWebSessionResult(
        apiKey: 'public-web-key-ambiguous-identity-mismatch',
        expectedCustomerIdentifier: 'expected-host-user',
        identityTicketProvider: () async => 'single-use-ticket',
      );

      expect(result.failure?.code, InappifyFailureCode.identityMismatch);
      expect(platform.exchangeCalls, 1);
      expect(platform.customerCalls, 1);
      expect(platform.receivedTickets, <String>['single-use-ticket']);
    },
  );
}

InappifySdkSnapshot _webSnapshot(
  InappifySessionState state, {
  String? customerId,
}) {
  return InappifySdkSnapshot(
    accessToken: null,
    apiKey: 'public-web-key',
    customerInfo: customerId == null
        ? null
        : CustomerInfo(originalAppUserId: customerId),
    storeInfo: 'web',
    sdkVersion: '0.1.0-beta.3',
    sessionState: state,
    persistenceMode: InappifySessionPersistenceMode.durable,
  );
}

class _RecoveryPlatform extends InappifySdkPlatform {
  final List<InappifySdkResult<void>> configureResults =
      <InappifySdkResult<void>>[];
  InappifySdkResult<InappifyAuthenticationResult>? exchangeResult;
  InappifySdkResult<CustomerInfo>? customerResult;
  final List<String> order = <String>[];
  final List<String> receivedTickets = <String>[];
  int configureCalls = 0;
  int exchangeCalls = 0;
  int customerCalls = 0;

  final StreamController<InappifyPlatformEvent> _events =
      StreamController<InappifyPlatformEvent>.broadcast(sync: true);

  @override
  Stream<InappifyPlatformEvent> get events => _events.stream;

  @override
  Future<InappifyBackendCapabilities> getCapabilities() async {
    return InappifyBackendCapabilities(
      backendKind: InappifyBackendKind.webJavaScript,
      protocolVersion: InappifyBackendCapabilities.currentProtocolVersion,
      ownsSession: true,
      supportedOperations: Set<InappifyOperation>.unmodifiable(
        InappifyOperation.values,
      ),
      sdkVersion: '0.1.0-beta.3',
    );
  }

  @override
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) async {
    configureCalls += 1;
    order.add('configure');
    return configureResults.removeAt(0);
  }

  @override
  Future<InappifySdkResult<InappifyAuthenticationResult>>
  exchangeIdentityTicket(InappifyIdentityTicketRequest request) async {
    exchangeCalls += 1;
    order.add('exchange');
    receivedTickets.add(request.identityTicket);
    return exchangeResult!;
  }

  @override
  Future<InappifySdkResult<CustomerInfo>> getCustomerInfo(
    InappifyRefreshRequest request,
  ) async {
    customerCalls += 1;
    return customerResult!;
  }

  Future<void> dispose() => _events.close();
}
