import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/authentication_result.dart';
import 'package:inappify_sdk/models/checkout_result.dart';
import 'package:inappify_sdk/models/otp_challenge.dart';
import 'package:inappify_sdk/request_cancellation.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart';

void main() {
  group('documented Web request contracts', () {
    test(
      'configure carries browser targeting without inventing credentials',
      () {
        const request = InappifyConfigureRequest(
          apiKey: 'public-web-app-key',
          country: 'IR',
          appVersion: '1.0.0',
        );

        expect(request.toMap(), <String, Object?>{
          'apiKey': 'public-web-app-key',
          'appUserIdentifier': null,
          'market': null,
          'marketKey': null,
          'country': 'IR',
          'appVersion': '1.0.0',
          'mobileProtocol': 'goV2',
          'enableSubscriptionRecoveryWithoutPayload': true,
        });
      },
    );

    test(
      'identity ticket and OTP values use the documented argument names',
      () {
        expect(
          const InappifyIdentityTicketRequest(
            identityTicket: 'single-use-ticket',
          ).toMap(),
          <String, Object?>{'identityTicket': 'single-use-ticket'},
        );
        expect(
          const InappifyOtpRequest(phone: '09121234567').toMap(),
          <String, Object?>{
            'phone': '09121234567',
            'captchaKey': null,
            'captchaAnswer': null,
          },
        );
        expect(
          const InappifyOtpVerificationRequest(
            challengeId: 'challenge-1',
            code: '123456',
          ).toMap(),
          <String, Object?>{'challengeId': 'challenge-1', 'code': '123456'},
        );
      },
    );

    test('offering and entitlement requests preserve Web SDK defaults', () {
      expect(
        const InappifyTargetingContextRequest(
          country: 'DE',
          appVersion: '2.5.0',
        ).toMap(),
        <String, Object?>{'country': 'DE', 'appVersion': '2.5.0'},
      );
      expect(
        InappifyCurrentOfferingRequest(
          placementIdentifier: 'home_banner',
        ).toMap(),
        <String, Object?>{
          'placementIdentifier': 'home_banner',
          'forceRefresh': false,
          'context': null,
        },
      );
      expect(
        const InappifyEntitlementCheckRequest(identifier: 'premium').toMap(),
        <String, Object?>{'identifier': 'premium', 'forceRefresh': true},
      );
    });

    test('attribute requests retain values and deletion keys', () {
      final values = InappifyAttributesRequest(
        attributes: <Attribute>[
          Attribute(key: 'language', value: 'fa'),
          Attribute(key: 'theme', value: 'dark'),
        ],
      );

      expect(values.toMap(), <String, Object?>{
        'attributes': <Object?>[
          <String, Object?>{'key': 'language', 'value': 'fa'},
          <String, Object?>{'key': 'theme', 'value': 'dark'},
        ],
        'idempotencyKey': null,
      });
      expect(
        InappifyDeleteAttributesRequest(keys: <String>['theme']).toMap(),
        <String, Object?>{
          'keys': <String>['theme'],
        },
      );
      expect(
        const InappifyReservedAttributeCapabilityRequest(
          key: r'$email',
        ).toMap(),
        <String, Object?>{'key': r'$email'},
      );
    });

    test('payment-return polling uses the documented safe defaults', () {
      expect(
        const InappifyPaymentReturnRequest(checkoutId: 'checkout-1').toMap(),
        <String, Object?>{
          'checkoutId': 'checkout-1',
          'timeoutMs': 60000,
          'intervalMs': 1500,
        },
      );
    });

    test('request cancellation is idempotent and stays off the wire', () async {
      final cancellation = InappifyRequestCancellation();
      var notifications = 0;
      final subscription = cancellation.whenCancelled.listen((_) {
        notifications += 1;
      });

      cancellation.cancel();
      cancellation.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(cancellation.isCancelled, isTrue);
      expect(notifications, 1);
      expect(
        InappifyRefreshRequest(force: true, cancellation: cancellation).toMap(),
        <String, Object?>{'force': true},
      );
      await subscription.cancel();
    });
  });

  group('documented Web response contracts', () {
    test('authentication result never exposes session credentials', () {
      final result = InappifyAuthenticationResult.fromMap(<String, Object?>{
        'isAnonymous': false,
        'type': 'Authenticated',
        'authenticatedAt': '2026-08-11T10:00:00Z',
        'accessToken': 'must-not-cross-the-platform-contract',
        'refreshToken': 'must-not-cross-the-platform-contract',
      });

      expect(result.isAnonymous, isFalse);
      expect(result.type, 'Authenticated');
      expect(result.authenticatedAt, '2026-08-11T10:00:00Z');
      expect(result.toMap(), isNot(contains('accessToken')));
      expect(result.toMap(), isNot(contains('refreshToken')));
    });

    test('OTP challenge accepts the documented challenge identifier', () {
      final challenge = InappifyOtpChallenge.fromMap(<String, Object?>{
        'challengeId': 'challenge-1',
        'expiresAt': '2026-08-11T10:01:00Z',
      });

      expect(challenge.challengeId, 'challenge-1');
      expect(challenge.expiresAt, '2026-08-11T10:01:00Z');
    });

    test('checkout result requires authoritative checkout state', () {
      final result = InappifyCheckoutResult.fromMap(<String, Object?>{
        'checkout': <String, Object?>{'id': 'checkout-1', 'status': 'Paid'},
        'nextAction': <String, Object?>{'type': 'none', 'url': null},
      });

      expect(result.checkout.id, 'checkout-1');
      expect(result.isPaid, isTrue);
      expect(result.nextAction.type, 'none');
    });

    test('callback-only payment data cannot masquerade as checkout state', () {
      expect(
        () => InappifyCheckoutResult.fromMap(<String, Object?>{
          'status': 'Paid',
          'callbackQuery': 'status=Paid',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
