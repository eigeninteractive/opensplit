import 'package:drift/drift.dart';

import 'open_database_native.dart'
    if (dart.library.js_interop) 'open_database_web.dart'
    as platform;

/// Opens the database file belonging to [accountId].
QueryExecutor openAccountDatabase(String accountId) =>
    platform.openPlatformDatabase('opensplit-$accountId');
