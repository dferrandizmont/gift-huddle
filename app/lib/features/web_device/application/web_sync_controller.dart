import '../../sync/application/sync_controller.dart';
import '../../../core/sync/device_registry.dart';
import '../../sync/domain/sync_status.dart';
import 'web_sync_engine.dart';

/// Injection into the existing controller provider without activating any of
/// the mobile engine's lifecycle, persistence or device-management paths.
class WebSyncController extends SyncController {
  WebSyncController(this.engine);
  final WebSyncEngine engine;
  Never _deny(String operation) => throw WebOperationException(operation);
  @override
  SyncStatus build() => const SyncStatus(SyncPhase.idle);
  @override
  bool get isV2 => true;
  @override
  Future<void> syncNow() => engine.sync();
  @override
  Future<Never> setEnabled(bool enabled) async => _deny('setEnabled');
  @override
  Future<Never> stopSyncing() async => _deny('leaveFamily');
  @override
  Future<Never> leaveFamily() async => _deny('leaveFamily');
  @override
  Future<Never> credentials() async => _deny('invite');
  @override
  Future<Never> readyCredentials() async => _deny('invite');
  @override
  Future<Never> expectPeer() async => _deny('invite');
  @override
  Future<Never> resumeAfterPairing() async => _deny('invite');
  @override
  Future<Never> removeDevice(
    String deviceId, {
    Future<void> Function(List<KnownDevice> orphans)? rememberOrphans,
    bool selfWaitAccepted = true,
  }) async => _deny('removeDevice');
  @override
  Future<Never> previewRemoveDevice(String deviceId) async =>
      _deny('removeDevice');
  @override
  Future<Never> approveDevice(String deviceId, {String? recordDigest}) async =>
      _deny('approveDevice');
  @override
  void setV2Pairing(bool pairing) => _deny('invite');
}
