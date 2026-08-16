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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wger/core/shared_preferences.dart';
import 'package:wger/features/routines/models/active_workout.dart';
import 'package:wger/features/routines/providers/active_workout_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  ActiveWorkout makeWorkout({int currentPage = 0}) => ActiveWorkout(
    routineId: 1,
    dayId: 2,
    iteration: 3,
    startedAt: DateTime.utc(2026, 4, 15, 10),
    currentPage: currentPage,
    validUntil: DateTime.utc(2026, 4, 15, 15),
  );

  setUp(() async {
    // In-memory shared preferences shared across containers in the same test,
    // so a "fresh container" simulates an app restart against the same store.
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    // `PreferenceHelper.asyncPref` is a process singleton that binds its backing
    // store at construction, so clear that exact instance to avoid bleed from a
    // prior test.
    await PreferenceHelper.asyncPref.clear();
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  test('build returns null when no pointer is persisted', () async {
    expect(await container.read(activeWorkoutProvider.future), isNull);
  });

  test('start persists the pointer and survives a restart', () async {
    final notifier = container.read(activeWorkoutProvider.notifier);
    final workout = makeWorkout(currentPage: 4);

    await notifier.start(workout);
    expect(container.read(activeWorkoutProvider).value, workout);

    // Simulate an app restart: a new container reading the same store.
    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    expect(await restarted.read(activeWorkoutProvider.future), workout);
  });

  test('updateCursor moves the persisted cursor', () async {
    final notifier = container.read(activeWorkoutProvider.notifier);
    await notifier.start(makeWorkout(currentPage: 0));

    await notifier.updateCursor(7);
    expect(container.read(activeWorkoutProvider).value!.currentPage, 7);

    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    final restored = await restarted.read(activeWorkoutProvider.future);
    expect(restored!.currentPage, 7);
  });

  test('updateCursor is a no-op when there is no pointer', () async {
    final notifier = container.read(activeWorkoutProvider.notifier);
    await container.read(activeWorkoutProvider.future);

    await notifier.updateCursor(3);

    expect(container.read(activeWorkoutProvider).value, isNull);
  });

  test('finish clears the pointer', () async {
    final notifier = container.read(activeWorkoutProvider.notifier);
    await notifier.start(makeWorkout());

    await notifier.finish();
    expect(container.read(activeWorkoutProvider).value, isNull);

    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    expect(await restarted.read(activeWorkoutProvider.future), isNull);
  });

  test('finish cannot lose against an in-flight write', () async {
    // Call sites fire-and-forget; without serialization a remove can complete
    // while an earlier write is still in flight, resurrecting the pointer.
    final notifier = container.read(activeWorkoutProvider.notifier);

    final ops = [
      notifier.start(makeWorkout(currentPage: 1)),
      notifier.updateCursor(2),
      notifier.finish(),
    ];
    await Future.wait(ops);

    expect(container.read(activeWorkoutProvider).value, isNull);
    expect(await PreferenceHelper.asyncPref.containsKey(PREFS_ACTIVE_WORKOUT), false);

    // And a restart sees the same outcome.
    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    expect(await restarted.read(activeWorkoutProvider.future), isNull);
  });

  test('a malformed stored pointer is treated as absent', () async {
    // Write through the same backing instance the notifier reads from.
    await PreferenceHelper.asyncPref.setString(PREFS_ACTIVE_WORKOUT, 'not-valid-json');

    expect(await container.read(activeWorkoutProvider.future), isNull);
  });
}
