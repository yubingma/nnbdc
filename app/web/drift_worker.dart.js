"use strict";

// This is a stub for drift_worker.dart.js
// In production, you should replace this with the real file from drift releases
// See: https://drift.simonbinder.eu/web/
self.onmessage = function(e) {
  console.log('Drift worker received message:', e.data);
  // This is just a stub - the real drift worker would process database operations
  self.postMessage({
    id: e.data.id,
    success: false,
    error: 'This is a stub worker. Please replace with the real drift_worker.dart.js file.'
  });
}; 