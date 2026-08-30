import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

const _sqlite3Wasm = 'sqlite3.wasm';
const _driftWorker = 'drift_worker.js';

/// Opens [name] in the browser's Origin Private File System.
///
/// OpenSplit deliberately has no second browser database backend. Falling back
/// to another storage API would create an independent local ledger under the
/// same account and make data appear to disappear between browser sessions.
QueryExecutor openPlatformDatabase(String name) => DatabaseConnection.delayed(
  Future(() async {
    final probe = await WasmDatabase.probe(
      sqlite3Uri: Uri.parse(_sqlite3Wasm),
      driftWorkerUri: Uri.parse(_driftWorker),
    );
    final storage = selectOpfsStorage(probe.availableStorages);
    return probe.open(storage, name);
  }),
);

/// Selects the safest available OPFS implementation.
WasmStorageImplementation selectOpfsStorage(
  List<WasmStorageImplementation> available,
) {
  const preferred = [
    WasmStorageImplementation.opfsShared,
    WasmStorageImplementation.opfsLocks,
  ];
  for (final implementation in preferred) {
    if (available.contains(implementation)) {
      return implementation;
    }
  }

  throw UnsupportedError(
    'This browser cannot provide the OPFS storage OpenSplit requires.',
  );
}
