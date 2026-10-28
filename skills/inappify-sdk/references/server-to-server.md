# PWA server-to-server integration

Verified against the local Laravel backend on 2026-10-28. This describes source
behavior, not production deployment. The user confirmed the production API origin
as `https://api.inappify.com` on 2026-10-28. Use it for production examples and give
complete endpoint URLs when asked where to send a request; use a different origin
only when the host explicitly targets another environment. The general server APIs
also serve trusted backends for other platforms.

Production ticket issuance URL:
`https://api.inappify.com/api/web/v1/server/identity-tickets` (POST).

Contents: credentials; identity tickets; subscribers and attributes; offerings;
promotional entitlements; assigned discount codes; errors/retries; source map.

## Trust boundaries and credentials

| Caller/purpose | Route family | Credential |
| --- | --- | --- |
| Host backend issuing PWA login tickets | `/api/web/v1/server/identity-tickets` | Secret project API key |
| Host backend managing customers/offers/promotions/codes | `/api/v1/...` | Secret project API key |
| Browser starting a session | `/api/web/v1/sessions` | Public Web App Key in `app_key` |
| Browser exchanging tickets, reading access, checking out, delivering consumables | `/api/web/v1/...` session routes | Web session access token owned by SDK |

A project secret is not a browser access token or public app key. There is no
secret-key checkout, payment-verification, or consumable-acknowledgement endpoint
in the inspected server routes. Use the supported Web SDK flow for these; a
promotional grant is not a substitute for a purchase. See [Web integration](web.md).

The host backend must authenticate its caller and derive the customer ID from the
authenticated account. Never trust a browser-supplied user ID as identity proof or
expose an unrestricted proxy for these operations. Keep secrets in backend
configuration, outside PWA bundles, service-worker caches, browser storage, logs,
and responses. Tickets must also stay out of logs and caches.

Send server requests over HTTPS with:

```http
Authorization: Bearer <secret-project-api-key>
Accept: application/json
Content-Type: application/json
```

The key determines the project; a request's project ID cannot switch tenants.
New secrets use `sk_<selector>.<secret>` and are returned as `data.secret_key` only
on creation. Later listings are masked. Provision narrowly scoped keys through
project settings; key management is an account operation, not PWA startup.

| Method and path | Required ability | Success HTTP |
| --- | --- | --- |
| POST `/api/web/v1/server/identity-tickets` | `web:identity-ticket:create` | 201 |
| GET `/api/v1/subscribers/{user}` | `customers:read` | 200 existing / 201 created |
| DELETE `/api/v1/subscribers/{user}` | `customers:delete` | 200 |
| POST `/api/v1/subscribers/{user}/attributes` | `customers:attributes:write` | 200 |
| GET `/api/v1/subscribers/{user}/offerings` | `offerings:read` | 200 |
| POST `/api/v1/subscribers/{user}/offerings/{offering}/override` | `offerings:override:write` | 201 |
| DELETE `/api/v1/subscribers/{user}/offerings/override` | `offerings:override:delete` | 200 |
| POST `/api/v1/subscribers/{user}/entitlements/{entitlement}/promotional` | `entitlements:promotional:grant` | 201 |
| POST `/api/v1/subscribers/{user}/entitlements/{entitlement}/revoke_promotionals` | `entitlements:promotional:revoke` | 200 |
| POST `/api/v1/services/generate-discount` | `discount:generate` | 200 |

Legacy `customers:manage` covers only the three customer abilities. Existing `*`
keys cover all abilities, but `*` is not a manageable ability for new keys.
Missing, malformed, unknown, expired, revoked, or deleted keys fail authentication.
When project-owner identity enforcement is enabled, verified owner email, mobile,
and identity profile are also required; this is separate from customer login.

### Identifiers

`{user}` is the external `app_user_identifier`, not a database ID or legacy customer
token. Subscriber services resolve project-scoped aliases to their canonical owner.
URL-encode each path segment once. Prefer path-safe IDs; do not assume an encoded
slash will pass through every web server.

Subscriber IDs are required UTF-8 strings, max 100 characters, without control
characters or leading/trailing Unicode separators. Reserved anonymous prefixes
accept only valid SDK anonymous IDs. Ticket `user_id` rejects anonymous prefixes
entirely. Do not fabricate anonymous IDs. Use the same stable host ID across mobile,
PWA tickets, and subscriber calls when they should share customer access.

## Identity tickets: authenticated host account to PWA

Prerequisites: global `web_api.enabled` (`WEB_API_ENABLED`), enabled app Web config,
enabled external auth, and a Public Web App Key belonging to the secret's project.
The ticket request itself requires no Origin or Web session; approved browser
origins and browser feature settings apply separately to the session flow.
General `/api/v1` server routes are not gated by `web-api.enabled`.

### Issue on the host backend

```http
POST https://api.inappify.com/api/web/v1/server/identity-tickets
Authorization: Bearer <secret-project-api-key>
Accept: application/json
Content-Type: application/json

{"app_key":"<public-web-app-key>","provider":"customer_backend","user_id":"user-542"}
```

| Field | Contract |
| --- | --- |
| `app_key` | Required string max 100; Public Web App Key, not app identifier |
| `provider` | Required string max 50; letters, digits, `_`, `-`; stable identity namespace |
| `user_id` | Required string max 100; validated host account ID; anonymous IDs forbidden |

201 response (opaque ticket and timestamp shown illustratively):

```json
{"status":true,"data":{"identity_ticket":"iwt_<selector>.<secret>","expires_at":"2026-10-28T10:01:00+00:00"}}
```

Tickets expire one minute after issuance and allow one successful exchange.
Issuance stores app/project/issuer/provider/subject; it does not log in a browser or
create the target customer. Each call creates another ticket; `Idempotency-Key`
does not deduplicate this route.

Example inside an authenticated Laravel **host** route. Configuration names here
are host-defined examples, not built-in InAppify settings. Set
`services.inappify.origin` to `https://api.inappify.com` for production:

```php
public function identityTicket(\Illuminate\Http\Request $request)
{
    $user = $request->user();
    abort_unless($user, 401);

    $upstream = \Illuminate\Support\Facades\Http::acceptJson()->asJson()
        ->withToken(config('services.inappify.secret_key'))
        ->connectTimeout(5)->timeout(15)
        ->post(rtrim(config('services.inappify.origin'), '/')
            .'/api/web/v1/server/identity-tickets', [
                'app_key' => config('services.inappify.public_web_app_key'),
                'provider' => 'customer_backend',
                'user_id' => (string) $user->getAuthIdentifier(),
            ]);

    // Map failures without forwarding upstream credentials or payloads.
    abort_unless($upstream->status() === 201
        && $upstream->json('status') === true
        && is_string($upstream->json('data.identity_ticket')), 502);

    return response()->json([
        'identity_ticket' => $upstream->json('data.identity_ticket'),
        'expires_at' => $upstream->json('data.expires_at'),
    ])->header('Cache-Control', 'no-store');
}
```

Protect the host route with its normal authentication, cookie-auth CSRF protection
where applicable, and rate limiting. Exclude it from service-worker offline caching.
Have Flutter's `identityTicketProvider` fetch it only when the SDK needs a fresh
ticket, returning its `identity_ticket` string. Set `expectedCustomerIdentifier` to
the same authenticated host ID. See [web.md](web.md) for
`configureAuthenticatedWebSessionResult` and direct JS `logIn` examples.

### Exchange is owned by the browser SDK

Protocol: `POST /api/web/v1/auth/external/exchange` takes
`{"identity_ticket":"..."}` (required string max 150) under the current Web
session's Bearer access token. The project secret is not accepted as a Web token.
Let the SDK establish the appropriate anonymous session and exchange the ticket;
do not add raw exchange calls beside its session owner.

Exchange locks the session and ticket in a transaction; it checks hash, consumption,
expiry, project/app pairing, and anonymous session state. Success returns
`data.customer.is_anonymous=false`, session information, replacement access/refresh
tokens and expiry timestamps, and configuration. Old session tokens are revoked.
Tokens remain inside the SDK; do not mirror them in host code.

Identity lookup uses project + provider + subject hash. Without a mapping, it reuses
a same-project customer with matching `app_user_identifier`, or renames the anonymous
customer. Keep provider and project-wide host IDs stable. Changing provider is not
an account-switch mechanism. Merging into an existing customer fails if the anonymous
source has payments or entitlements; a clean source can transfer attributes/session
references and an alias. Never delete financial evidence to force a merge.

| Exchange error | HTTP | Action |
| --- | --- | --- |
| `IDENTITY_TICKET_INVALID` / `IDENTITY_TICKET_EXPIRED` | 401 | Obtain a fresh ticket through the authenticated backend |
| `IDENTITY_TICKET_ALREADY_USED` | 409 | Reconcile SDK state; do not replay |
| `IDENTITY_APP_MISMATCH` | 403 | Correct project/app/public-key pairing |
| `SESSION_ALREADY_AUTHENTICATED` | 409 | Follow SDK account lifecycle; do not exchange twice |
| `CUSTOMER_MERGE_CONFLICT` | 409 | Preserve purchase evidence and resolve explicitly |

Failed exchange transactions roll back ticket consumption. A timeout still leaves
successful commit uncertain: reconcile SDK state before issuing/exchanging another
ticket. Issuance's `WEB_APP_NOT_FOUND` 404 covers missing app, disabled app/external
auth, and cross-project pairing. Global disable returns `WEB_API_DISABLED` 503.

## Subscribers and attributes

### Get or create

`GET /api/v1/subscribers/{user}` deliberately creates a missing customer: 201 on
creation, 200 for an existing customer/alias owner. It is not a pure existence check
or evidence of paid access. Creation uses a transaction and project-row lock.

`data` fields: `originalAppUserId`, `firstSeen`, `requestDate`,
`latestExpirationDate`, `entitlements`, `transactions`, `attributes`.
Entitlements are an **array**, including inactive records, with `identifier`,
`isActive`, `isSandbox`, `periodType`, `purchaseDate`, `expirationDate`,
`ownershipType`. Several entries may share an identifier. Transactions are at most
the ten latest payments having bank information, not a complete ledger. Attributes
are `{key,value}` entries. Do not forward the whole server response to the browser.

This Laravel projection is not Flutter's entitlement maps or the Web SDK's richer
CustomerInfo model. Dates use `Y-m-d H:i:s` without timezone offsets; do not append
`Z` or interpret them as milliseconds. Null expiry alone does not prove active or
lifetime access. `isActive` projects the stored flag; expiry-sensitive authorization
must also account for expiration and backend expiration lifecycle. Neither any
transaction entry nor an inactive entitlement establishes access.

### Set/delete attributes

`POST /api/v1/subscribers/{user}/attributes` requires an existing customer (404
otherwise). Body is an operation **list**, unlike the SDK attribute map:

```json
{"attributes":[{"key":"plan","value":"pro"},{"key":"language","value":null},{"key":"$email","value":"user@example.com"}]}
```

Accepts 1–20 operations. Keys: max 40, distinct after normalization; custom keys
use letters/digits/`_`/`-`. Values: nullable strings max 250. Null/empty deletes,
otherwise upserts; send `value` explicitly. At most 20 resulting stored attributes.
The transaction locks the customer; omitted keys stay unchanged.

Reserved keys: `$email`, `$apnsTokens`, `$fcmTokens`, `$idfa`, `$idfv`, `$ip`,
`$phoneNumber`, `$campaign`, `$keyword`, `$displayName`. Names without `$` normalize
to these reserved forms, so `email` plus `$email` is a duplicate-key error.
Non-empty `$email` must be valid. Unknown `$...` keys are invalid.

200 returns `{"status":true,"data":{"app_user_id":"...","attributes":[...]}}`,
with resulting attributes sorted by key. Reapplying explicit values is
state-idempotent; serialize competing updates for the same keys.

### Delete

`DELETE /api/v1/subscribers/{user}` resolves aliases and deletes the customer's
payments through its relationship, then the customer, transactionally. 200 returns
`data: {"app_user_id":"<requested-id>","deleted":true}`; missing customer is 404.
This is destructive account deletion, not logout/cancellation/recovery. A later GET
can create a customer again.

## Offerings and per-app overrides

All offering routes require `X-InAppify-App-ID: <app-identifier-key>`: the app's
`identifier_key`, not numeric ID or Public Web App Key. Missing/empty header: 422;
unknown or cross-project app: 404. All get or create the customer, including reads
and reset. A missing offering can leave that customer created before the 404.

All return `data: {"current_offering_id":"<identifier-or-null>","offerings":[...]}`.
Despite the name, current ID is a string identifier. Offerings include `identifier`,
`is_default`/`isDefault`, `server_description`/`serverDescription`, `metadata`,
`paywall`, `packages`. Packages include identifier, entitlement, type, description,
discount, name, and product identifier/name/trial days/prices. Prices include integer
`price`/`amount`, currency and original amount when discounted. Preserve units and
package context; the server still validates checkout amounts.

Empty offerings are removed; trial-duration filtering and app products affect
visibility. This response omits Web catalog `rules`/`forceVersion` and is not the
complete SDK catalog.

- GET selects a visible override, else visible default, else null; it does not run
  the SDK targeting resolver.
- POST `.../offerings/{offering}/override`: no required body; offering must belong
  to the project and have a package product for the app. Transaction/customer lock
  protects an upsert per customer + app. Repeating it replaces the same record.
- DELETE `.../offerings/override`: no required body; removes only this customer's
  override for this app, in a transaction under a customer lock.

Current limitation: `ServerOfferingService` reads the override, but browser
`OfferingController` calls `WebOfferingService` directly, which does not read it.
Do not promise automatic changes to Web SDK `getCurrentOffering`, its cache, or
checkout targeting. A host consuming server selection needs an explicit integration
and must still use an original SDK Package and authoritative checkout validation.

## Promotional entitlement grants and revocation

Use an existing project entitlement identifier, not product/package ID. No app
header is required. Both routes get or create the customer before entitlement
lookup; a missing entitlement can thus create the customer before returning 404.

`POST .../entitlements/{entitlement}/promotional` body:

```json
{"end_time_ms":1794000000000}
```

The number is illustrative: send a Unix epoch **millisecond integer in the future**
relative to server time. 201 returns subscriber information including inactive
entitlements. This route neither verifies a receipt nor accepts a client price.

Do not interpret `end_time_ms` as an exact expiry assignment. The service converts
remaining time to `max(1, ceil(days))`; the helper adds remaining days of an existing
active promotional record (at least one), replaces it, and creates access from now
for the combined days. **Repeated calls can extend access again. This is not an
idempotent endpoint or an exact expiry setter; Idempotency-Key is not implemented.**

The helper uses a transaction and locks an existing active promotional row, but
does not lock the customer row. Do not assume it prevents concurrent first-grant
races. Serialize host grants per customer/entitlement, keep a durable business
operation record, and reconcile uncertain outcomes before retrying. A host operation
ID alone cannot provide upstream exactly-once delivery across an unknown commit.
The helper also dispatches a subscription-purchased SMS job after commit; fake
queues/SMS in tests and never exercise it against real users for verification.

`POST .../entitlements/{entitlement}/revoke_promotionals`: no required body, 200
subscriber response. It locks the customer, deletes all promotional records for
that entitlement and refreshes customer status. Normal paid purchases remain.
Repeating leaves the same promotional state, but a missing customer is first
created. This is not a refund API.

## Assigned discount codes

`POST /api/v1/services/generate-discount` body:

```json
{"discount_identifier_key":"welcome_offer","app_user_identifier":"user-542"}
```

Both inputs are trimmed required strings. Discount identifier max 100; user ID
max 150 here (this request does not use the subscriber ID rule). Discount must
already exist in the key's project and be active. This assigns a code, not a new
discount definition or final checkout amount.

200: `{"status":true,"data":{"code":"DC-ABC123"}}` (illustrative). Existing
discount + user assignments are reused, soft-deleted codes restored and inactive
codes reactivated. A new code is active with `max_redemptions=1` and
`redemptions_count=0`. Reuse does not reset redemptions or guarantee eligibility.
Transactions, row locks and duplicate-key recovery support assignment reuse.
Missing/inactive discount currently throws an unhandled RuntimeException here;
do not invent a stable discount-specific 404/422 error contract.

Validate the code and create checkout through the Web SDK using selected
offering/package context. Issuance is not redemption or proof of payment.

## Response, errors, and retry policy

Success uses `{"status":true,"data":...}`. Explicit business errors usually use
`{"status":false,"message":"...","code":"..."}` with optional `code`.
Laravel FormRequest failures can instead contain `message`/`errors` without
`status`. Do not assume a universal error envelope or parse localized messages as
stable codes.

| HTTP / code | Meaning/action |
| --- | --- |
| 401, message only for project keys | Missing/invalid/expired/revoked credential; fix backend key |
| 403 `API_KEY_ABILITY_DENIED` | Key lacks the route's exact permission |
| 403 `PROJECT_OWNER_IDENTITY_REQUIRED` | Complete project-owner verification when enforced |
| 404 | Missing scoped resource; ticket path also hides app/project mismatch |
| 422 | Invalid fields/IDs, missing app header, attribute limit, or past grant time |
| 429 | Respect Retry-After when present; bounded backoff |
| 503 `WEB_API_DISABLED` | Web feature disabled in deployment |
| 5xx / connection loss | A mutation may have committed; reconcile before retry |

Current shared project-api budgets: 120/minute per key, 300/minute per key + IP,
20,000/day per key. These are shared across the routes, not independent per
endpoint. Deployment/proxy limits can add restrictions.

There is no generic server-route Idempotency-Key contract. Browser checkout
idempotency does not extend to promotional grants or identity exchange. Remember
that subscriber/offering GETs can create customers. Do not repeat a DELETE after
a new operation recreated the same external ID without checking current intent.

## Source map and validation

Recheck these repository-relative sources after backend changes; no fixed local
checkout path is required to use this skill:

- Routes/envelopes: `bootstrap/app.php`, `routes/api.php`, `routes/webApi.php`,
  `app/Helpers/Custom/responseHelper.php`.
- Auth/scopes/limits: `app/Http/Middleware/AuthenticateProjectApiKey.php`,
  `app/Services/Projects/ProjectApiKeyService.php`, `app/Models/Projects/ApiKey.php`,
  `app/Services/Identity/ProjectIdentityGate.php`, `app/Providers/AppServiceProvider.php`.
- Tickets: `app/Http/Controllers/WebApi/V1/IdentityController.php`,
  `app/Http/Requests/WebApi/V1/CreateIdentityTicketRequest.php`,
  `app/Http/Requests/WebApi/V1/ExchangeIdentityTicketRequest.php`,
  `app/Services/WebApi/WebIdentityService.php`, `app/Services/WebApi/WebAppResolver.php`.
- Subscriber/offerings/promotions: `app/Http/Controllers/Api/ApiServices/V1/`,
  `app/Http/Requests/ApiServices/V1/`, `app/Services/ApiServices/V1/`,
  `app/Rules/AppUserIdentifier.php`, `app/Models/Projects/Customers/CustomerRepository.php`,
  `app/Helpers/Customers/CustomerHelper.php`, `app/Services/WebApi/WebOfferingService.php`,
  `app/Http/Controllers/WebApi/V1/OfferingController.php`.
- Discounts: `app/Http/Requests/Projects/GenerateDiscountRequest.php`,
  `app/Services/ApiServices/AssignDiscountCodeService.php`.
- Existing tests: `tests/Feature/WebApi/ExternalIdentityTest.php`,
  `tests/Feature/WebApi/ProjectApiKeySecurityTest.php`,
  `tests/Feature/ApiServices/SubscriberApiTest.php`,
  `tests/Feature/ApiServices/SubscriberOfferingAndEntitlementApiTest.php`.

For host tests, fake upstream HTTP and queue/SMS delivery. Verify host identity
sets the ticket subject, secrets stay off the client, attribute operations use a
list, app identifiers are distinct from keys, and uncertain exchange/promotion
results do not cause blind retries. Compilation alone does not prove deployment.
