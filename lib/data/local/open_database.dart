import 'package:drift/drift.dart';

import 'open_database_native.dart'
    if (dart.library.js_interop) 'open_database_web.dart'
    as platform;

/// The stable storage name for an account's local ledger.
///
/// The `v1` label stays fixed across schema upgrades.
/// The pre-cutover `opensplit-` files are unused.
String accountDatabaseName(String accountId) => 'opensplit-v1-$accountId';

/// Opens the database file belonging to [accountId].
QueryExecutor openAccountDatabase(String accountId) =>
    platform.openPlatformDatabase(accountDatabaseName(accountId));
