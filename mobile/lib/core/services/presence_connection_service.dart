import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../network/socket_service.dart';
import 'background_sync_service.dart';

/// Monitors both device OS network connectivity (Mobile Data / Wi-Fi)
/// and live Socket.IO connection status.
///
/// [isPresenceLiveNotifier] is only `true` when the device has an active
/// internet connection AND the real-time socket is connected.
///
/// When mobile data/Wi-Fi is turned off, [isPresenceLiveNotifier] immediately
/// becomes `false`, allowing the UI to suppress stale online/last-seen status.
///
/// When the connection is restored, [reconnectCounter] increments, signaling
/// screens (Dashboard and Chat) to fetch fresh, present status from the server.
class PresenceConnectionService {
  static final PresenceConnectionService _instance = PresenceConnectionService._internal();
  factory PresenceConnectionService() => _instance;
  PresenceConnectionService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  SocketService? _socketService;

  final ValueNotifier<bool> isPresenceLiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> reconnectCounter = ValueNotifier<int>(0);

  bool _hasNetwork = true;
  bool _isInitialized = false;

  bool get isPresenceLive => isPresenceLiveNotifier.value;

  void initialize(SocketService socketService) {
    _socketService = socketService;
    if (_isInitialized) return;
    _isInitialized = true;
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_handleConnectivityResults);
    _connectivity.checkConnectivity().then(_handleConnectivityResults);

    _socketService?.isConnectedNotifier.addListener(_recalculatePresence);
  }

  void _handleConnectivityResults(List<ConnectivityResult> results) {
    final hasNet = results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);
    _hasNetwork = hasNet;
    _recalculatePresence();
  }

  void _recalculatePresence() {
    final socketConnected = _socketService?.isConnected == true;
    final isLive = _hasNetwork && socketConnected;
    final wasLive = isPresenceLiveNotifier.value;

    if (wasLive != isLive) {
      isPresenceLiveNotifier.value = isLive;
      if (!wasLive && isLive) {
        // Connection just restored! Increment reconnect counter so listeners
        // fetch the present status of users from the server.
        reconnectCounter.value++;
        // Reset sync scheduling state so future offline breaks can safely schedule a new task
        BackgroundSyncService.resetSyncSchedule();
      }
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _socketService?.isConnectedNotifier.removeListener(_recalculatePresence);
    _isInitialized = false;
  }
}
