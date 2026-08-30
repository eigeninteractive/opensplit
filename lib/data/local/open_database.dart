import 'package:drift/drift.dart';

import 'open_database_native.dart'
    if (dart.library.js_interop) 'open_database_web.dart'
    as platform;

/// Opens the database file belonging to [accountId].
///
/// Platform implementations preserve the same account-keyed naming while
/// choosing storage according to their own lifecycle guarantees.
QueryExecutor openAccountDatabase(String accountId) =>
    platform.openPlatformDatabase('opensplit-$accountId');
