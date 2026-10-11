import {
  InAppify,
  SDK_VERSION,
  isInAppifyError,
} from '@inappifylabs/web-sdk'

const bridge = Object.freeze({
  InAppify,
  version: SDK_VERSION,
  isInAppifyError,
})

// The Flutter adapter intentionally consumes one narrow global boundary. The
// npm module itself remains bundled by the host Web application and no token
// or SDK instance is published on globalThis.
if (globalThis.__inappifyFlutterWebSdk === undefined) {
  Object.defineProperty(globalThis, '__inappifyFlutterWebSdk', {
    value: bridge,
    configurable: false,
    enumerable: false,
    writable: false,
  })
}
