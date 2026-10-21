# Offerings, placements and targeting

Android uses the server selection through Kotlin. The public API is:

```dart
final offerings = await InappifySdk.getOfferings();
final current = await InappifySdk.getCurrentOffering();
final home = await InappifySdk.getCurrentOffering(placementIdentifier: 'home');
final special = await InappifySdk.getOffering('special_offer');
```

Selection follows placement, current Offering, then default Offering. Missing
selections return null. `offerings.current`, `offerings.getOffering(id)` and
`offerings.getCurrentOfferingForPlacement(id)` select from the returned collection.
The default Offering is the project fallback; current may differ due to server
experiments or targeting. Android does not evaluate server rules in Dart.

Update attributes and request a fresh selection when needed:

```dart
await InappifySdk.setAttributes({'family': 'yes'});
final refreshed = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
final selected = await InappifySdk.getCurrentOffering(placementIdentifier: 'home');
```

Android flushes its durable attribute queue, then fetches fresh offerings. Native
quota: five admitted calls per rolling minute, including failed admitted calls.
Excess calls return current-customer cache or a RATE_LIMITED_NO_CACHE failure.
This quota does not limit normal reads or automatic refresh. Automatic Offering
refresh occurs on foreground reads/transitions when missing or five minutes old,
with a thirty-second failure backoff. Do not pre-warm with getOfferings in Android
Application.onCreate; configure handles SDK prefetch.

There is no public manual targeting context or forceRefresh parameter. Country
and host version are collected by Android; the server resolves targeting.

Web keeps its existing JavaScript selection/rendering contract. Model evaluation
helpers remain for that implementation; they do not switch Android into local
rule evaluation. Use showPaywall only where the current Flutter renderer supports
the supplied Paywall schema. Native store purchase remains independent of UI.
