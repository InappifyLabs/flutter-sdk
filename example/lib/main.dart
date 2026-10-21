import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/models/offering_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InappifyExampleApp());
}

/// Supply the public app key and optional user identifier with --dart-define.
/// No SDK network operation runs until a button is pressed.
class InappifyExampleApp extends StatelessWidget {
  const InappifyExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Inappify example',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: const _ExamplePage(),
  );
}

class _ExamplePage extends StatefulWidget {
  const _ExamplePage();

  @override
  State<_ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<_ExamplePage> {
  static const _appKey = String.fromEnvironment('INAPPIFY_PUBLIC_APP_KEY');
  static const _userId = String.fromEnvironment('INAPPIFY_APP_USER_ID');

  bool _busy = false;
  bool _configured = false;
  String _message = 'Provide a public app key, then configure the SDK.';
  OfferingModel? _offering;

  Future<void> _perform(Future<String> Function() operation) async {
    setState(() => _busy = true);
    try {
      final message = await operation();
      if (mounted) setState(() => _message = message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _failure(InappifyFailure? failure) =>
      'Operation failed: ${failure?.code ?? 'unknown'}';

  Future<String> _configure() async {
    if (_appKey.isEmpty) return 'Set INAPPIFY_PUBLIC_APP_KEY first.';
    // Web starts anonymously; authenticated Web users need a backend Identity
    // Ticket through configureAuthenticatedWebSessionResult (see docs/WEB.md).
    final result = await InappifySdk.configureResult(
      apiKey: _appKey,
      appUserIdentifier: kIsWeb || _userId.isEmpty ? null : _userId,
    );
    _configured = result.isSuccess;
    return result.isSuccess
        ? 'Configured. Backend SDK: ${InappifySdk.sdkVersion}'
        : _failure(result.failure);
  }

  Future<String> _loadOffering() async {
    final result = await InappifySdk.getCurrentOfferingResult();
    if (!result.isSuccess) return _failure(result.failure);
    _offering = result.data;
    return _offering == null
        ? 'No offering selected by the server.'
        : 'Current offering: ${_offering!.identifier}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inappify example')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(_message),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : () => _perform(_configure),
          child: const Text('Configure'),
        ),
        OutlinedButton(
          onPressed: _busy || !_configured
              ? null
              : () => _perform(_loadOffering),
          child: const Text('Load current offering'),
        ),
        OutlinedButton(
          onPressed: _busy || !_configured
              ? null
              : () => _perform(() async {
                  final result = await InappifySdk.getCustomerInfoResult();
                  return result.isSuccess
                      ? 'Customer refreshed. Entitlements: '
                            '${result.data?.entitlements.length ?? 0}'
                      : _failure(result.failure);
                }),
          child: const Text('Refresh customer'),
        ),
        OutlinedButton(
          onPressed: _busy || !_configured || kIsWeb
              ? null
              : () => _perform(() async {
                  final result = await InappifySdk.syncStorePurchases();
                  return result.isSuccess
                      ? 'Purchase sync completed.'
                      : _failure(result.failure);
                }),
          child: const Text('Sync store purchases'),
        ),
        if (_offering != null)
          OutlinedButton(
            onPressed: _busy ? null : () => _offering!.showPaywall(context),
            child: const Text('Preview paywall'),
          ),
        const SizedBox(height: 20),
        const Text(
          'This sample previews offerings and recovery. Integrate your own '
          'purchase action and durable consumable delivery using the guides. '
          'Web also requires the JavaScript provider bundle described in docs/WEB.md.',
        ),
      ],
    ),
  );
}
