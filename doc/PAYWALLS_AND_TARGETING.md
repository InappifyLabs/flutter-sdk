# Offerings, targeting and paywalls

## Select the server's offering

Production V2 clients use server targeting. A current-offering query first loads
or refreshes the catalog according to `forceRefresh`, then resolves:

1. The requested placement's offering identifier, if it exists in the catalog.
2. The server's `currentOffering` identifier, if it exists in the catalog.
3. The catalog's first `isDefault == true` offering.
4. Null if none is available.

A success with null is a valid result. A missing placement does not itself imply a
failure. Use the typed SDK getter for a live request, rather than selecting the
first package or calling `defaultOffering()` as a substitute for targeting.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/models/offering_model.dart';

Future<OfferingModel?> loadUpgradeOffering() async {
  final result = await InappifySdk.getCurrentOfferingResult(
    placementIdentifier: 'upgrade',
    forceRefresh: true,
  );
  return result.isSuccess ? result.data : null;
}
```

On mobile, offerings requests use the verified session and send `appVersion`,
`sdkVersion`, `country`, `paywallSchemaVersion: 1` and `paywallRendererVersion: 1`.
They flush pending attributes first. Android gets its SDK version from the native
Kotlin SDK; iOS uses the Dart V2 version. Both are `0.1.1` in this release.
These values are not inferred from a host-written synchronous SDK field. Browser
selection and configuration are owned by the loaded JavaScript SDK; see [Web](WEB.md).

The optional `context` argument on `getCurrentOfferingResult` is retained for API
compatibility. It does not override production mobile server targeting. Android
still strictly decodes a supplied context map; omit it for normal server selection.

## Update targeting inputs

Use write APIs for customer attributes and a context update for country/app
version. A model mutation is not an upload. Custom mobile keys match
`[A-Za-z][A-Za-z0-9_-]{0,39}`. Values are null or at most 500 Unicode code points;
null and empty remove a value, while whitespace remains a value.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/models/offering_model.dart';

Future<InappifySdkResult<OfferingModel>> selectFamilyOffering() async {
  final queued = await InappifySdk.queueAttributes({'family': 'yes'});
  if (!queued.isSuccess) {
    return InappifySdkResult<OfferingModel>.failure(
      queued.failure!,
      snapshot: queued.snapshot,
    );
  }
  return InappifySdk.getCurrentOfferingResult(forceRefresh: true);
}
```

This example is for mobile V2. The fresh offerings request flushes the durable
queue before requesting selection. If the upload fails, the refresh returns a
failure instead of inventing a targeted offering. Attribute writes invalidate
cached offerings. They are write-only; do not expect uploaded `family` to be
reflected in `customerInfo.attributes` or a setter's returned list.

`setTargetingContextResult(country: 'IR', appVersion: '1.2.3')` changes non-null
mobile context fields and invalidates offerings. Follow it with an offering query.
Omit an argument to preserve that field. Do not set `sdkVersion` yourself: it
identifies the backend SDK. For Web, use its supported attribute APIs and backend
version; the mobile queue/policy helpers are not browser APIs.

## Model helpers

`OfferingsModel` preserves `currentOfferingIdentifier`, `placements` and
`usesServerTargeting` in JSON, including an explicit null server selection.
Its `currentOffering(placment: 'upgrade')` retains the historical misspelling.
`resolveOffering(evaluationContext: ..., placement: ...)` is a synchronous helper.
For a server-targeted model it follows placement → current → default and does not
evaluate downloaded local rules.

`defaultOffering()` and the `List<OfferingModel>.current` extension use
`firstWhere` and can throw `StateError` when a non-null list has no default.
They are convenience model helpers, not safe substitutes for
`getCurrentOfferingResult`.

`OfferingEvaluationContext`, `evaluateField`, `evaluateFieldWithContext`,
`evaluateOperator` and `convertVersionToDouble` support explicitly constructed
model-level rules. They do not update a production session or change server
selection. The dotted-version helper retains a historical numeric comparison
format; do not use it to replace server semantic version targeting.

## Build purchase UI from the selected catalog

Choose an Inappify package and SKU from the selected offering. This function
validates nullable identifiers and passes the SKU type supplied by the host's
product configuration:

```dart
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/package_model.dart';
import 'package:inappify_sdk/models/purchase_result.dart';

Future<InappifySdkResult<PurchaseResult>?> buyOfferingPackage({
  required OfferingModel offering,
  required PackageModel package,
  required InappifyProductType productType,
  required String attemptId,
}) {
  final offeringId = offering.identifier;
  final packageId = package.identifier;
  final productId = package.product?.identifier;
  if (offeringId == null || packageId == null || productId == null ||
      !(offering.packages?.contains(package) ?? false)) {
    return Future.value(null);
  }
  return InappifySdk.purchaseResult(
    offeringIdentifier: offeringId,
    packageIdentifier: packageId,
    productIdentifier: productId,
    productType: productType,
    idempotencyKey: attemptId,
  );
}
```

`PackageModel.packageType` is a nullable catalog/display integer, and
`StoreProductModel` does not expose a typed consumable/subscription classification.
Supply the correct `InappifyProductType` yourself for a store purchase. The native
SDK also checks that a new attempt's product belongs to the current offering.
Displayed price is not a local authorization to grant access or inventory.

## Remote paywall renderer

`OfferingModel.paywall` can contain a `Paywall` document. Calling
`offering.showPaywall(context, fontFamily: 'YourBundledFont')` opens a Material
bottom sheet if the paywall field is non-null and returns whether the modal was
requested. It does not return checkout success or wait for the modal to close.
`PaywallModal(paywall: ..., fontFamily: ...)` can also be embedded directly.

The renderer requires nonempty `assets`, nonempty `localizations`, and a `layout`
element. Missing requirements show an explanatory placeholder. It handles layout,
hero-image, text, button, footer, link, packages, tab-control, group, image, card,
list and list-item elements. `package-item` is rendered inside the packages widget;
unknown standalone element types render an empty widget. Styles and strings
reference the document's asset/localization IDs. The modal chooses RTL for a locale
starting with `fa`; localized text helpers also read the localization's RTL flag.
Fonts are selected from the host's supplied `fontFamily`.

**The current remote renderer is display-only for payment actions.** Its
`purchase_product` and `crypto` button branches do not call the purchase SDK and
there is no public purchase-action callback on `showPaywall`/`PaywallModal`.
Close actions close the route; some link/top-button actions navigate or open URLs.
Use a host-owned purchase UI that calls `purchaseResult` and handles the result
explicitly. Showing a server paywall alone does not implement a checkout flow.

Optional `PaywallAssetsDownloader` methods preload supported assets, find a local
path, inspect cache bytes/count and clear the paywall file cache. IO runtimes use
file caching; browsers return network URLs and no local file cache. Clearing these
files is not a purchase journal or session reset. See
[security/cache](SECURITY_AND_CACHE.md) for the trust boundary around remote data.

The paywall models expose JSON `fromJson`/`toJson` methods for document transport:
`Paywall`, `PaywallElement`, `PaywallAsset`, localization/text/style, layout/state,
links/actions, badges/dividers/top buttons and related package display models.
They describe renderer input; they do not establish server signature trust or
prove an arbitrary remote action is supported.
