/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c)  2026 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wger/core/shared_preferences.dart';
import 'package:wger/features/routines/models/active_workout.dart';

part 'active_workout_notifier.g.dart';

/// Key under which the singleton active-workout pointer is stored.
const PREFS_ACTIVE_WORKOUT = 'activeWorkout';

/// Persists a small singleton pointer to the workout currently in progress.
///
/// v1 supports exactly one active workout at a time. The pointer is stored as a
/// single JSON blob in `shared_preferences`; it is device-local and not synced.
@Riverpod(keepAlive: true)
class ActiveWorkoutNotifier extends _$ActiveWorkoutNotifier {
  final _logger = Logger('ActiveWorkout');

  @override
  Future<ActiveWorkout?> build() async {
    final raw = await PreferenceHelper.asyncPref.getString(PREFS_ACTIVE_WORKOUT);
    if (raw == null) {
      return null;
    }
    try {
      return ActiveWorkout.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e, s) {
      // A malformed/legacy pointer must never crash the app; treat as absent.
      _logger.warning('Could not parse active workout pointer, ignoring', e, s);
      return null;
    }
  }

  /// Mutations are fire-and-forget at the call sites, so they are serialized
  /// here: an unserialized remove could lose against an in-flight write and
  /// resurrect a pointer the wipe just deleted.
  Future<void> _lastOp = Future.value();

  Future<void> _enqueue(Future<void> Function() op) {
    final run = _lastOp.then((_) => op());
    _lastOp = run.catchError((_) {});
    return run;
  }

  Future<void> _persist(ActiveWorkout workout) async {
    await PreferenceHelper.asyncPref.setString(
      PREFS_ACTIVE_WORKOUT,
      jsonEncode(workout.toJson()),
    );
    state = AsyncData(workout);
  }

  /// Persist a freshly-started workout pointer (overwrites any existing one).
  Future<void> start(ActiveWorkout workout) {
    _logger.fine('Starting active workout pointer: $workout');
    return _enqueue(() => _persist(workout));
  }

  /// Update the persisted cursor. No-op if no pointer exists.
  Future<void> updateCursor(int page) {
    return _enqueue(() async {
      final current = state.value;
      if (current == null || current.currentPage == page) {
        return;
      }
      await _persist(current.copyWith(currentPage: page));
    });
  }

  /// Delete the pointer (explicit session save / end, and the local-data
  /// wipe on logout or user switch).
  Future<void> finish() {
    _logger.fine('Clearing active workout pointer');
    return _enqueue(() async {
      await PreferenceHelper.asyncPref.remove(PREFS_ACTIVE_WORKOUT);
      state = const AsyncData(null);
    });
  }
}
