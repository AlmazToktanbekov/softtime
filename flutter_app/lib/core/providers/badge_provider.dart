import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

class BadgeState {
  final bool duty;
  final bool requests;

  const BadgeState({this.duty = false, this.requests = false});

  BadgeState copyWith({bool? duty, bool? requests}) => BadgeState(
        duty: duty ?? this.duty,
        requests: requests ?? this.requests,
      );
}

class BadgeNotifier extends StateNotifier<BadgeState> {
  final ApiService _api;
  // IDs, which user has already "seen" (opened the relevant tab)
  final Set<String> _seenSwapIds = {};
  final Set<String> _seenRequestIds = {};

  BadgeNotifier(this._api) : super(const BadgeState());

  Future<void> refresh() async {
    try {
      final swapsFuture = _api.getIncomingSwaps();
      final requestsFuture = _api.getMyAbsenceRequests();

      final swaps = await swapsFuture;
      final requests = await requestsFuture;

      final pendingSwaps = swaps.where((s) => s.status == 'pending').toList();
      final hasNewSwap = pendingSwaps.any((s) => !_seenSwapIds.contains(s.id));

      const reviewedStatuses = {'approved', 'rejected', 'needs_clarification'};
      final reviewedRequests =
          requests.where((r) => reviewedStatuses.contains(r.status)).toList();
      final hasNewRequest =
          reviewedRequests.any((r) => !_seenRequestIds.contains(r.id));

      if (mounted) {
        state = state.copyWith(duty: hasNewSwap, requests: hasNewRequest);
      }
    } catch (_) {}
  }

  /// Call when user opens the Duty tab — marks all current pending swaps as seen.
  Future<void> clearDuty() async {
    try {
      final swaps = await _api.getIncomingSwaps();
      for (final s in swaps.where((s) => s.status == 'pending')) {
        _seenSwapIds.add(s.id);
      }
    } catch (_) {}
    if (mounted) state = state.copyWith(duty: false);
  }

  /// Call when user opens the Requests tab — marks all reviewed requests as seen.
  Future<void> clearRequests() async {
    try {
      final requests = await _api.getMyAbsenceRequests();
      const reviewedStatuses = {'approved', 'rejected', 'needs_clarification'};
      for (final r in requests.where((r) => reviewedStatuses.contains(r.status))) {
        _seenRequestIds.add(r.id);
      }
    } catch (_) {}
    if (mounted) state = state.copyWith(requests: false);
  }
}

final badgeProvider = StateNotifierProvider<BadgeNotifier, BadgeState>((ref) {
  return BadgeNotifier(ApiService());
});
