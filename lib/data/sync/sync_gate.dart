import '../local/database.dart';
import 'sync_gate_contract.dart';
import 'sync_gate_native.dart'
    if (dart.library.js_interop) 'sync_gate_web.dart'
    as platform;

export 'sync_gate_contract.dart';

/// Creates the synchronization gate appropriate for the current platform.
SyncGate createSyncGate(AppDatabase database) =>
    platform.createPlatformSyncGate(database);
