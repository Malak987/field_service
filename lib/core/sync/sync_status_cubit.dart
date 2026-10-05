import 'dart:async';

import 'package:field_service/core/sync/sync_manager.dart';
import 'package:field_service/core/sync/sync_status.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Presentation-ready state for a compact sync indicator.
///
/// This is deliberately the *only* UI mechanism of the offline layer: a
/// future "Synced / Syncing… / Offline / N pending / Sync failed" badge
/// builds on [SyncHealth.displayStatus] without knowing anything about
/// queues or connectivity. No feature should build its own indicator.
class SyncStatusCubit extends Cubit<SyncHealth> {
  SyncStatusCubit({required SyncManager syncManager})
    : super(syncManager.currentHealth) {
    _subscription = syncManager.onHealthChanged.listen(emit);
  }

  StreamSubscription<SyncHealth>? _subscription;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
