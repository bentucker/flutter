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

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wger/features/routines/providers/active_workout_notifier.dart';
import 'package:wger/features/routines/screens/gym_mode.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

/// Surfaces a "Resume workout" affordance when an unfinished gym-mode workout
/// is persisted (and not yet expired). Renders nothing otherwise.
class ResumeWorkoutCard extends ConsumerWidget {
  const ResumeWorkoutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = AppLocalizations.of(context);
    final pointer = ref.watch(activeWorkoutProvider).value;

    if (pointer == null || !pointer.validUntil.isAfter(clock.now())) {
      return const SizedBox.shrink();
    }

    return Card(
      key: const ValueKey('resume-workout-card'),
      child: ListTile(
        leading: Icon(
          Icons.play_circle_fill,
          color: Theme.of(context).textTheme.headlineSmall!.color,
        ),
        title: Text(
          i18n.resumeWorkout,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).pushNamed(
            GymModeScreen.routeName,
            arguments: GymModeArguments(
              pointer.routineId,
              pointer.dayId,
              pointer.iteration,
            ),
          );
        },
      ),
    );
  }
}
