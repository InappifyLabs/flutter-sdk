# Web integration

The browser adapter delegates an entire session to the external `@inappifylabs/web-sdk` JavaScript provider. Flutter exposes typed customer, offering, authentication and checkout models; the JavaScript instance owns browser transport, credentials, refresh and persistence. The Kotlin SDK is used only on Android.

The Flutter package version is `0.1.0-beta.0`. The reviewed Web provider baseline is **`@inappifylabs/web-sdk@0.1.0-beta.3`**, an independent version. Do not replace it with `0.1.0-beta.0` merely to match the Flutter package. Capability negotiation accepts provider versions `0.1.0-beta.3` and later beta builds of `0.1.0`, stable `0.1.0`, or a higher numeric release. Missing, malformed or earlier provider versions are rejected.

## Install the browser bridge before Flutter starts

Flutter's build does not bundle bare npm imports and the plugin does not download or vendor a JavaScript SDK. Your host web build must resolve and bundle the provider. Add its exact baseline to the host's npm dependencies:

```sh
npm install --save-exact @inappifylabs/web-sdk@0.1.0-beta.3
```

The package includes [web/inappify_web_sdk_entry.mjs](../web/inappify_web_sdk_entry.mjs). Copy or include it in your host's bundler input; its import must be processed by the host bundler. It installs this narrow, credential-free boundary:

```js
import {
  InAppify,
  SDK_VERSION,
  isInAppifyError,
} from '@inappifylabs/web-sdk'

globalThis.__inappifyFlutterWebSdk = Object.freeze({
  InAppify,
  version: SDK_VERSION,
  isInAppifyError,
})
```

The shipped entry uses a non-writable property and leaves an already installed bridge intact. Bundle that entry as a self-hosted ESM file, for example `inappify-provider.js`. Replace the generated Flutter bootstrap script tag in `web/index.html` with an ordered loader such as:

```html
<script type="module">
  await import('./inappify-provider.js');
  const bootstrap = document.createElement('script');
  bootstrap.src = './flutter_bootstrap.js';
  document.body.appendChild(bootstrap);
</script>
```

Here `inappify-provider.js` means your built output, not the unbundled source containing a bare npm import. Avoid a second bootstrap script that starts Flutter before this import completes. The host's Content Security Policy must permit its chosen bundled script and the Inappify/paywall services it uses.

For hosts already using the official global bundle, the bridge can also discover `globalThis.InAppifySDK`, or the compatibility global `globalThis.InAppify`, if the export includes Configure and a supported SDK version. ESM is the explicit integration path. The bridge passes a bound browser `fetch` to provider Configure.

A missing/incompatible provider makes Web lifecycle unavailable. There is no mobile Dart/Dio browser fallback and no automatic switch to another session owner halfway through a configured session. Install the bridge before the first Inappify operation.

## Anonymous and authenticated sessions

Configure uses the **Public Web App Key**, not a mobile app key or server/project secret. The adapter passes `apiKey`, optional country/app version and fixed base URL `https://api.inappify.com/api/web/v1` to the provider. This is the independent Web API contract; mobile operations use `/app/v2/` and do not call this Web route.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<bool> initializeAnonymousWeb(String publicWebAppKey) async {
  final result = await InappifySdk.configureResult(
    apiKey: publicWebAppKey,
    country: 'IR',
    appVersion: '1.0.0',
  );
  return result.isSuccess;
}
```

A stable authenticated `appUserIdentifier` in Web Configure is rejected. `loginResult` with a plain user identifier is unsupported on Web. Authenticate by exchanging a short-lived Identity Ticket issued by your trusted backend for its current logged-in user, or by the provider's OTP flow. Do not issue tickets in browser code or include a server secret in the application.

For authenticated application startup, prefer the combined helper:

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<bool> initializeAuthenticatedWeb({
  required String publicWebAppKey,
  required String userId,
  required Future<String> Function() fetchFreshIdentityTicket,
}) async {
  final result = await InappifySdk.configureAuthenticatedWebSessionResult(
    apiKey: publicWebAppKey,
    expectedCustomerIdentifier: userId,
    identityTicketProvider: fetchFreshIdentityTicket,
    country: 'IR',
    appVersion: '1.0.0',
  );
  return result.isSuccess;
}
```

`fetchFreshIdentityTicket` is your application's authenticated backend call, made just before returning a fresh one-time ticket. The helper restores a matching authenticated provider session when possible, checks the expected customer, and requests a ticket only when establishment/recovery is needed. Temporary network/timeout/storage failures preserve the last authoritative mirror and return failure; they do not imply logout. An ambiguous exchange is reconciled by a safe refresh without blindly reusing the same one-time ticket.

For an explicit flow after Configure, use `loginWithIdentityTicketResult(identityTicket: ticket)` or `exchangeIdentityTicketResult(identityTicket: ticket)`. The alias is provided for readability. OTP exposes `createOtpCaptchaResult`, `requestOtpResult(phone: ..., captchaKey: ..., captchaAnswer: ...)` and `verifyOtpResult(challengeId: ..., code: ...)`. Render the typed challenge and use the challenge IDs returned by the service. `logoutResult()` delegates the session transition to the provider and clears the pending checkout mirror after success.

## Session state

Listen to token-free provider lifecycle updates and cancel your subscription when the owning UI/controller is released:

```dart
import 'dart:async';
import 'package:inappify_sdk/inappify_sdk.dart';

StreamSubscription<InappifySessionStateChange> observeWebSession(
  void Function(InappifySessionStateChange change) onChange,
) => InappifySdk.sessionStateChanges.listen(onChange);
```

`temporarilyUnavailable` preserves the previous identity while recovery is retried. `recoveryRequired` means the authenticated transport needs a fresh establishment path. Use `sessionState` and the result's snapshot rather than inferring authentication from a nullable CustomerInfo. `snapshot.persistenceMode` reports `durable`, `memory` or `unknown`; a memory session does not promise restoration after reload.

Access/refresh tokens, Identity Tickets and raw JavaScript error details are not exposed through the Flutter snapshot. `snapshot.apiKey` may contain the public Web key. The Flutter package does not guarantee browser storage behavior independently of its provider; IndexedDB, Web Locks and credential rotation remain provider responsibilities.

## Checkout and payment return

Fetch offerings and use product, offering and package identifiers from the selected catalog. `createCheckout` preserves authoritative price, checkout expiry/status and next action, and does not navigate the browser:

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<InappifyCheckoutResult?> createWebPayment({
  required String offeringIdentifier,
  required String productIdentifier,
  required String packageIdentifier,
  required String attemptId,
}) async {
  final result = await InappifySdk.createCheckout(
    offeringIdentifier: offeringIdentifier,
    productIdentifier: productIdentifier,
    packageIdentifier: packageIdentifier,
    idempotencyKey: attemptId,
  );
  return result.isSuccess ? result.data : null;
}
```

Use the server's price without recalculating it. If `nextAction.type == 'redirect'`, your host navigation code opens `nextAction.url`. Preserve `checkout.id` before leaving. The Flutter checkout model rejects non-HTTP URL schemes but permits HTTP, HTTPS and relative URLs; the provider's configured destination policy and the host's navigation policy remain responsible for acceptable origins. The mobile `isPaymentUrlAllowed` helper is not a Web operation. `purchaseResult` is also supported, but projects the richer response into `PurchaseResult` (`DONE` for Paid, otherwise `NEEDTOPAY`, plus checkout ID/status/action); the adapter calls provider purchase with `redirect: false`.

The Web adapter passes the offering/package/product, idempotency key, country/app version, `isCrypto` and optional discount code to the provider. Reuse an attempt key only when reconciling/retrying the same logical checkout. Native lost-purchase options and nonzero numeric `discount` are rejected. `packageIdentifier` can be inferred for `purchaseResult` only if exactly one cached package matches that offering/product; supplying it explicitly is clearer.

The adapter saves an unresolved checkout ID in `sessionStorage` under `inappify_checkout_id`. Storage failure does not turn a created checkout into a false failure, so retain the ID in your own return flow when needed. Paid, Failed, Expired and Cancelled results clear the stored ID; identity changes also clear it. This ID is a correlation value, not proof of payment.

On the return page, reestablish the appropriate session, then poll the backend:

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<bool> verifyWebPaymentReturn({String? checkoutId}) async {
  final result = await InappifySdk.handlePaymentReturnResult(
    checkoutId: checkoutId,
    timeoutMs: 60000,
    intervalMs: 1500,
  );
  if (!result.isSuccess || result.data?.isPaid != true) return false;
  await InappifySdk.getCustomerInfoResult(forceRefresh: true);
  return true;
}
```

When omitted, the checkout ID is read from pending `sessionStorage`; no pending ID produces a typed failure. `getCheckoutStatus(checkoutId: ...)` performs one authoritative query without polling. `getPendingCheckoutIdResult()` reads the stored correlation. Query-string status, a redirect URL, browser closure or a cancelled poll must never grant access on their own.

An `InappifyRequestCancellation` can cancel supported JS network calls through `AbortController`. Cancellation of observation does not prove that a checkout or identity mutation did not commit. Reconcile uncertain state using the existing checkout or fresh customer state.

## Supported scope and limitations

Web supports customer/offerings/current offering, targeting context, custom/reserved attributes, discount validation, entitlement checks, session authentication and checkout operations advertised by its capability contract. `setIp` is unsupported; check optional reserved-attribute capability with `canSetReservedAttributeResult`.

The mobile V2 helpers `recover`, `setNetworkEnabled`, policy-based mobile fetches, mobile store restoration and consumable delivery confirmation are not Web methods. Use the provider-backed Web operations above. Bazaar/Myket billing and native `productType`/store receipt processing remain Android responsibilities; they do not become Web payments by passing a marketplace argument. The Flutter HTTP trace stream has no Web HTTP backend; use typed failures and provider-compatible browser diagnostics without logging credentials.

## Implementation references

- [ESM bridge entry](../web/inappify_web_sdk_entry.mjs), [browser registration](../lib/inappify_sdk_web.dart)
- [JavaScript boundary and event subscriptions](../lib/src/platform/web/javascript_inappify_bridge.dart)
- [Web lifecycle, checkout and capability guard](../lib/src/platform/web/web_inappify_platform.dart)
- [Typed payload conversion](../lib/src/platform/web/web_payload_codec.dart)
- [Session state and ticket provider types](../lib/session_state.dart), [public facade](../lib/inappify_sdk.dart)

See [API reference](API_REFERENCE.md) and [Security and cache](SECURITY_AND_CACHE.md).
