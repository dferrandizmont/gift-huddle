import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs/shared_preferences_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/accent_palette.dart';
import '../core/sync/envelope.dart';
import '../features/family/application/family_controller.dart';
import '../features/family/data/device_keys_store.dart';
import '../features/family/data/family_store.dart';
import '../features/sync/application/sync_controller.dart';
import '../features/sync/data/sync_config.dart';
import '../features/sync/data/sync_endpoint.dart';
import '../features/sync/data/sync_transport_common.dart';
import '../features/sync/data/sync_transport_factory.dart';
import '../features/sync/data/sync_transport_v2.dart';
import '../features/web_device/application/vault_service.dart';
import '../features/web_device/application/web_gate_controller.dart';
import '../features/web_device/application/web_session_platform.dart';
import '../features/web_device/application/web_sync_engine.dart';
import '../features/web_device/application/web_sync_controller.dart';
import '../features/web_device/application/web_device_providers.dart';
import '../features/web_device/data/guard_client.dart';
import '../features/web_device/data/vault_store.dart';
import '../features/web_device/data/web_device_keys_store.dart';
import '../features/web_device/data/web_family_store.dart';
import '../features/web_device/presentation/web_gate.dart';
import '../features/web_device/presentation/web_gate_model.dart';
import '../l10n/app_localizations.dart';
import 'app.dart';
import 'web_location.dart';

/// Allows offline lifecycle tests to use the actual bootstrap container.
typedef WebGateFactory = WebGateController Function(
  void Function(WebSyncEngine) create,
  void Function() dispose,
  void Function() changed,
);

/// Application composition only: the already implemented gate supplies all UI.
class WebBootstrap extends StatefulWidget {
  const WebBootstrap({super.key, required this.preferences, this.gateFactory});
  final WebGateFactory? gateFactory;
  final SharedPreferences preferences;
  @override
  State<WebBootstrap> createState() => _WebBootstrapState();
}

class _WebBootstrapState extends State<WebBootstrap> {
  WebGateController? _gate;
  ProviderContainer? _sessionContainer;
  BaseSyncTransport? _transport;
  @override
  void initState() {
    super.initState();
    clearWebPairingLocation();
    unawaited(_initialize());
  }

  BaseSyncTransport _network() =>
      _transport ??= createSyncTransport(SyncEndpoint.parse(kSyncHost)!);
  void _cancelNetwork() {
    _transport?.close();
    _transport = null;
  }

  Future<WebGateController> _createGate() async {
    final store = await openVaultStore();
    final vault = VaultService(
      store: store,
      guard: GuardClient(
        base: Uri.parse(kSyncHost),
        send: (method, uri, {body, headers = const {}}) =>
            _network().send(method, uri, body: body, headers: headers),
      ),
      revokeSelf: (v) async {
        final auth = V2Auth(
          syncId: v.header.syncId,
          deviceId: v.header.deviceId,
          credential: decodeBase64Url(v.data['credential'] as String),
        );
        await _network().v2.revoke(auth, auth.deviceId);
      },
    );
    return WebGateController(
      vault: vault,
      platform: createSessionPlatform(),
      transport: () => _network().v2,
      cancelTransport: _cancelNetwork,
      createContainer: _createContainer,
      disposeContainer: _disposeContainer,
      candidateChanged: _candidateChanged,
    );
  }

  void _candidateChanged() {
    final c = _sessionContainer;
    if (c != null) {
      unawaited(
        c
            .read(familyControllerProvider.notifier)
            .reloadStoredCandidate()
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _initialize() async {
    final gate =
        widget.gateFactory?.call(
          _createContainer,
          _disposeContainer,
          _candidateChanged,
        ) ??
        await _createGate();
    if (!mounted) {
      await gate.close();
      return;
    }
    _gate = gate;
    gate.addListener(_changed);
    await gate.initialize();
    if (mounted) setState(() {});
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _disposeContainer() {
    final container = _sessionContainer;
    _sessionContainer = null;
    container?.dispose();
  }

  void _createContainer(WebSyncEngine engine) {
    final gate = _gate!;
    final store = WebFamilyStore(
      gate.vault,
      engine,
      onSaved: () {
        unawaited(engine.requestSync());
      },
    );
    _sessionContainer = ProviderContainer(
      retry: familyRetry,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(widget.preferences),
        deviceKeysStoreProvider.overrideWithValue(
          WebDeviceKeysStore(gate.vault),
        ),
        familyStoreProvider.overrideWithValue(store),
        // A read of the normal controller cannot start a mobile v1/v2 engine.
        syncTransportProvider.overrideWithValue(null),
        syncV2TransportProvider.overrideWithValue(null),
        syncControllerProvider.overrideWith(() => WebSyncController(engine)),
        localRegistryViewProvider.overrideWith((ref) async {
          await ref.watch(familyControllerProvider.future);
          return engine.view;
        }),
        webGateActionsProvider.overrideWithValue(gate),
        webSyncEngineProvider.overrideWithValue(engine),
      ],
    );
  }

  @override
  void dispose() {
    _gate?.removeListener(_changed);
    unawaited(_gate?.close());
    _disposeContainer();
    _cancelNetwork();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gate = _gate;
    final session = _sessionContainer;
    // No family ProviderContainer exists outside an unlocked session.
    if (gate?.view is WebGateOpen && session != null) {
      return UncontrolledProviderScope(
        container: session,
        child: const RegalosApp(webSession: true),
      );
    }
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(AccentId.rose.palette, Brightness.light),
      home: gate == null
          ? const SizedBox.shrink()
          : WebGate(
              view: gate.view,
              actions: gate,
              onConfirmCode: gate.confirmCode,
              onRejectCode: gate.rejectCode,
              child: const SizedBox.shrink(),
            ),
    );
  }
}
