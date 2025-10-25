// web.dart
import 'package:drift/drift.dart';
import 'package:nnbdc/global.dart';
import 'package:drift/wasm.dart';
import 'package:nnbdc/util/app_clock.dart';
// Explicitly import WebDatabase and DriftWebStorage for a safe fallback that avoids localStorage
// ignore: deprecated_member_use
import 'package:drift/web.dart' show WebDatabase, DriftWebStorage;
import 'dart:async';

import 'db.dart';

MyDatabase constructDb() {
  return MyDatabase(connectOnWeb());
}

DatabaseConnection connectOnWeb() {
  return DatabaseConnection.delayed(Future(() async {
    final base = Uri.base; // Robust against different base hrefs or sub-path deployments
    String devSuffix() {
      const bool isProduct = bool.fromEnvironment('dart.vm.product');
      if (isProduct) {
        return '';
      }
      return '?v=${AppClock.now().millisecondsSinceEpoch}';
    }

    Future<DatabaseConnection> openWasm() async {
      final opened = await WasmDatabase.open(
        databaseName: 'nnbdc_db',
        sqlite3Uri: base.resolve('sqlite3.wasm${devSuffix()}'),
        driftWorkerUri: base.resolve('drift_worker.dart.js${devSuffix()}'),
      );

      if (opened.missingFeatures.isNotEmpty) {
        Global.logger.d('Using ${opened.chosenImplementation} due to missing browser '
            'features: ${opened.missingFeatures}');
      }
      return opened.resolvedExecutor;
    }

    // If served over file:// or unsupported scheme, avoid non-http(s) as browsers may block workers/IDB
    if (base.scheme != 'http' && base.scheme != 'https') {
      Global.logger.w('Non-http(s) scheme detected (${base.scheme}); WASM requires http(s). Please serve via a local web server.');
    }

    // Retry WASM open to handle first-tab worker delays, without falling back to localStorage-based WebDatabase
    const int maxAttempts = 3;
    const Duration attemptTimeout = Duration(seconds: 3);
    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final conn = await openWasm().timeout(attemptTimeout);
        if (attempt > 1) {
          Global.logger.d('WASM open succeeded on attempt #$attempt');
        }
        return conn;
      } on TimeoutException catch (e, st) {
        lastError = e;
        Global.logger.w('WASM open timeout on attempt #$attempt', error: e, stackTrace: st);
      } catch (e, st) {
        lastError = e;
        Global.logger.w('WASM open failed on attempt #$attempt', error: e, stackTrace: st);
      }
      // brief backoff before retry
      await Future.delayed(const Duration(milliseconds: 300));
    }
    // If still failing after retries, try IndexedDB-backed WebDatabase explicitly (no localStorage fallback)
    try {
      Global.logger.w('Falling back to IndexedDB WebDatabase after WASM failures');
      // ignore: deprecated_member_use
      final storage = DriftWebStorage.indexedDb('nnbdc_db');
      // DatabaseConnection.fromExecutor is deprecated in newer drift; use unnamed ctor if available
      // ignore: deprecated_member_use
      return DatabaseConnection.fromExecutor(WebDatabase.withStorage(storage));
    } catch (e, st) {
      Global.logger.e('IndexedDB WebDatabase fallback failed', error: e, stackTrace: st);
      // Surface descriptive error to the caller
      throw Exception('Web database initialization failed. In private mode or restricted browsers, IndexedDB/localStorage may be unavailable. Please try a different browser or disable private mode. Original error: ${lastError?.toString() ?? e.toString()}');
    }
  }));
}
