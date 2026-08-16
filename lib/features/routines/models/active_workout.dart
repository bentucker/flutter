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

import 'package:flutter/material.dart';

/// A small, device-local pointer to the workout currently in progress.
///
/// This is *not* synced user data; it is ephemeral UI cursor state persisted to
/// `shared_preferences` so an in-progress gym-mode workout (routine + day +
/// cursor) survives an app restart and can be resumed. The completion state of
/// each set is *not* stored here — it is reconstructed from the persisted logs
/// (`manager_workoutlog`), which remain the single source of truth.
@immutable
class ActiveWorkout {
  final int routineId;
  final int dayId;
  final int iteration;

  /// Workout start instant; restored into `GymModeState.workoutStart` on
  /// resume so elapsed time and the derived session start stay truthful.
  final DateTime startedAt;

  /// Cursor (page index) to restore on resume.
  final int currentPage;

  /// Same semantics as `GymModeState.validUntil`: after this the resume offer
  /// expires.
  final DateTime validUntil;

  const ActiveWorkout({
    required this.routineId,
    required this.dayId,
    required this.iteration,
    required this.startedAt,
    required this.currentPage,
    required this.validUntil,
  });

  ActiveWorkout copyWith({
    int? routineId,
    int? dayId,
    int? iteration,
    DateTime? startedAt,
    int? currentPage,
    DateTime? validUntil,
  }) {
    return ActiveWorkout(
      routineId: routineId ?? this.routineId,
      dayId: dayId ?? this.dayId,
      iteration: iteration ?? this.iteration,
      startedAt: startedAt ?? this.startedAt,
      currentPage: currentPage ?? this.currentPage,
      validUntil: validUntil ?? this.validUntil,
    );
  }

  Map<String, dynamic> toJson() => {
    'routineId': routineId,
    'dayId': dayId,
    'iteration': iteration,
    'startedAt': startedAt.toIso8601String(),
    'currentPage': currentPage,
    'validUntil': validUntil.toIso8601String(),
  };

  factory ActiveWorkout.fromJson(Map<String, dynamic> json) {
    return ActiveWorkout(
      routineId: json['routineId'] as int,
      dayId: json['dayId'] as int,
      iteration: json['iteration'] as int,
      startedAt: DateTime.parse(json['startedAt'] as String),
      currentPage: json['currentPage'] as int,
      validUntil: DateTime.parse(json['validUntil'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ActiveWorkout &&
      routineId == other.routineId &&
      dayId == other.dayId &&
      iteration == other.iteration &&
      startedAt == other.startedAt &&
      currentPage == other.currentPage &&
      validUntil == other.validUntil;

  @override
  int get hashCode => Object.hash(routineId, dayId, iteration, startedAt, currentPage, validUntil);

  @override
  String toString() =>
      'ActiveWorkout(routineId: $routineId, dayId: $dayId, iteration: $iteration, '
      'currentPage: $currentPage, validUntil: $validUntil)';
}
