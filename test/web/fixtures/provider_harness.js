// Test transport only: the client, cache policies, events and limiter are the
// unmodified, published Web SDK. No live Inappify services are contacted.
(() => {
  const sdk = globalThis.InAppifySDK
  const nativeFetch = globalThis.fetch
  const nativeNow = performance.now.bind(performance)
  let state
  let held = null
  let client
  const response = (data, status = 200) => new Response(JSON.stringify({ status: status === 200, data,
    ...(status === 200 ? {} : { code: 'TEST_UNAVAILABLE' }),
  }), { status, headers: { 'Content-Type': 'application/json' } })
  const session = () => ({
    access_token: `test-access-${state.session++}`,
    access_token_expires_at: new Date(Date.now() + 3600000).toISOString(),
    refresh_token: `test-refresh-${state.session}`,
    refresh_token_expires_at: new Date(Date.now() + 86400000).toISOString(),
    customer: { is_anonymous: state.customerId.startsWith('$InaAnonymousId_') },
    configuration: {
      app: { id: 42, platform: 3, store_platform: 3 },
      authentication: { anonymous: true, external: true },
      features: { offerings: true, attributes: true, checkout: true },
      attributes: { writable: ['language'], writable_reserved: ['$email'] },
    },
  })
  const transport = async (input, init = {}) => {
    const url = typeof input === 'string' ? input : input.url
    if (!url.startsWith('https://api.inappify.com/api/web/v1/')) return nativeFetch(input, init)
    const resource = new URL(url).pathname.replace('/api/web/v1/', '')
    state.requests.push(resource)
    if (resource === 'sessions') return response(session())
    if (resource === 'auth/external/exchange') { state.customerId = 'account-b'; return response(session()) }
    if (resource === 'sessions/logout') { state.customerId = '$InaAnonymousId_second'; return response(session()) }
    if (resource === 'customerInfo') {
      const info = { originalAppUserId: state.customerId,
        entitlements: [], transactions: [], attributes: [{ key: 'language', value: state.language }] }
      if (state.holdNext) {
        state.holdNext = false
        await new Promise((resolve) => { held = resolve })
      }
      init.signal?.throwIfAborted()
      if (state.failInfo) return response({}, 503)
      return response({ customerInfo: info })
    }
    if (resource === 'offerings') {
      if (state.failOfferings) return response({}, 503)
      return response({ offerings: [{ identifier: `offering-${++state.offeringReads}`,
        isDefault: true, packages: [] }], rules: [], forceVersion: 1 })
    }
    if (resource === 'customer/attributes/sync' || resource === 'customer/attributes') {
      const { attributes } = JSON.parse(init.body)
      if (Array.isArray(attributes)) {
        for (const attribute of attributes) if (attribute.key === 'language') state.language = attribute.value
      } else if ('language' in attributes) state.language = attributes.language
      return response({ attributes: { language: state.language } })
    }
    return response({}, 404)
  }
  globalThis.__inappifyFlutterWebSdk = {
    version: sdk.SDK_VERSION,
    InAppify: {
      prototype: sdk.InAppify.prototype,
      configure: async (options) => {
        state.configureCount++
        client = await sdk.InAppify.configure({ ...options, storage: new sdk.MemoryStorage(),
          prefetchOfferings: false, fetch: transport })
        const on = client.on.bind(client)
        client.on = (name, callback) => on(name, (payload) => {
          state.emitted.push(name)
          callback(payload)
        })
        const getInfo = client.getCustomerInfo.bind(client)
        client.getCustomerInfo = (...args) => {
          state.calls.push({ method: 'getCustomerInfo', policy: args[0],
            options: args[1] !== undefined, signal: args[1]?.signal instanceof AbortSignal })
          return getInfo(...args)
        }
        const sync = client.syncAttributesAndOfferingsIfNeeded.bind(client)
        client.syncAttributesAndOfferingsIfNeeded = (...args) => {
          state.calls.push({ method: 'syncAttributesAndOfferingsIfNeeded' })
          return sync(...args)
        }
        return client
      },
    },
  }
  globalThis.__inappifyProviderTest = {
    reset: () => {
      state = { customerId: '$InaAnonymousId_first', language: 'en', session: 0,
        requests: [], calls: [], emitted: [], configureCount: 0, offeringReads: 0,
        failInfo: false, failOfferings: false, now: 0, holdNext: false }
      held = null
      Object.defineProperty(performance, 'now', { configurable: true, value: () => state.now })
    },
    set: (values) => Object.assign(state, values),
    read: () => ({ ...state, held: held !== null }),
    clear: () => { state.requests.length = 0; state.calls.length = 0; state.emitted.length = 0 },
    release: () => { const release = held; held = null; release?.() },
    restore: () => {
      Object.defineProperty(performance, 'now', { configurable: true, value: nativeNow })
      globalThis.fetch = nativeFetch
    },
  }
})()
