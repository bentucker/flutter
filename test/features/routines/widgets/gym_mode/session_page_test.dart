/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2020 - 2026 wger Team
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
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wger/core/shared_preferences.dart';
import 'package:wger/features/routines/models/active_workout.dart';
import 'package:wger/features/routines/models/routine.dart';
import 'package:wger/features/routines/models/session.dart';
import 'package:wger/features/routines/providers/active_workout_notifier.dart';
import 'package:wger/features/routines/providers/gym_state_notifier.dart';
import 'package:wger/features/routines/providers/workout_session_repository.dart';
import 'package:wger/features/routines/widgets/gym_mode/session_page.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

import '../../../../../test_data/routines.dart';
import 'session_page_test.mocks.dart';

@GenerateMocks([WorkoutSessionRepository])
void main() {
  late MockWorkoutSessionRepository mockRepository;
  late Routine testRoutine;
  late GymStateNotifier notifier;
  late ProviderContainer container;

  setUp(() async {
    // The session page now clears the active-workout pointer on save, which
    // touches shared_preferences.
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    await PreferenceHelper.asyncPref.clear();

    testRoutine = getTestRoutine();
    mockRepository = MockWorkoutSessionRepository();
    when(mockRepository.watchAllDrift()).thenAnswer(
      (_) => Stream<List<WorkoutSession>>.multi((controller) {
        controller.add(testRoutine.sessions);
      }),
    );

    container = ProviderContainer.test(
      overrides: [
        workoutSessionRepositoryProvider.overrideWithValue(mockRepository),
      ],
    );
    notifier = container.read(gymStateProvider.notifier);
    notifier.state = notifier.state.copyWith(
      showExercisePages: true,
      showTimerPages: true,
      dayId: 1,
      iteration: 1,
      routine: testRoutine,
    );
    notifier.calculatePages();
    when(mockRepository.editLocalDrift(any)).thenAnswer(
      (_) => Future.value(testRoutine.sessions[0]),
    );
    // when(mockRoutinesProvider.fetchAndSetRoutineFull(any)).thenAnswer(
    //   (_) => Future.value(testRoutine),
    // );
  });

  Widget renderSessionPage({locale = 'en'}) {
    final pageController = PageController(initialPage: 0);

    return UncontrolledProviderScope(
      container: container,

      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PageView(
            controller: pageController,
            children: [
              SessionPage(pageController),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('Test that data from  session is loaded', (WidgetTester tester) async {
    withClock(Clock.fixed(DateTime(2021, 5, 1)), () async {
      await tester.pumpWidget(renderSessionPage());
      await tester.pumpAndSettle();

      expect(find.text('10:00 AM'), findsOneWidget);
      expect(find.text('12:34 PM'), findsOneWidget);
      expect(find.text('This is a note'), findsOneWidget);
      final toggleButtons = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      expect(toggleButtons.isSelected[2], isTrue);
    });
  });

  testWidgets('Existing session with null times falls back to defaults', (
    WidgetTester tester,
  ) async {
    // A session created lazily while logging has no times; the page should
    // prefill the gym session's start and the current time instead of leaving
    // both fields blank.
    testRoutine.sessions[0] = testRoutine.sessions[0].copyWith(timeStart: null, timeEnd: null);

    notifier.state = notifier.state.copyWith(
      routine: testRoutine,
      workoutStart: DateTime(2021, 5, 1, 13, 35),
    );
    notifier.calculatePages();

    await withClock(Clock.fixed(DateTime(2021, 5, 1, 15, 23)), () async {
      await tester.pumpWidget(renderSessionPage());
      await tester.pumpAndSettle();

      expect(find.text('1:35 PM'), findsOneWidget);
      expect(find.text('3:23 PM'), findsOneWidget);
    });
  });

  testWidgets('Test correct default data (no existing session)', (WidgetTester tester) async {
    // Arrange
    testRoutine.sessions = [];
    notifier.state = notifier.state.copyWith(
      workoutStart: DateTime(2021, 5, 1, 13, 35),
    );

    // Act
    await tester.pumpWidget(renderSessionPage());
    await tester.pumpAndSettle();

    // Assert
    final timeNow = TimeOfDay.now().format(tester.element(find.byType(TextFormField).first));
    expect(find.text('1:35 PM'), findsOneWidget);
    expect(find.text(timeNow), findsOneWidget);
    final toggleButtons = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
    expect(toggleButtons.isSelected[1], isTrue);
  });

  testWidgets('Test that correct data is send to server', (WidgetTester tester) async {
    withClock(Clock.fixed(DateTime(2021, 5, 1)), () async {
      await tester.pumpWidget(renderSessionPage());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      final captured =
          verify(mockRepository.editLocalDrift(captureAny as dynamic)).captured.single
              as WorkoutSession;

      expect(captured.id, '1');
      expect(captured.impression, WorkoutImpression.good);
      expect(captured.notes, equals('This is a note'));
      expect(captured.timeStart, equals(const TimeOfDay(hour: 10, minute: 0)));
      expect(captured.timeEnd, equals(const TimeOfDay(hour: 12, minute: 34)));
    });
  });

  testWidgets('explicit session save clears the active-workout resume pointer', (
    WidgetTester tester,
  ) async {
    // Seed an in-progress pointer.
    await container
        .read(activeWorkoutProvider.notifier)
        .start(
          ActiveWorkout(
            routineId: 1,
            dayId: 1,
            iteration: 1,
            startedAt: DateTime(2021, 5, 1),
            currentPage: 3,
            validUntil: DateTime(2021, 5, 1, 5),
          ),
        );
    expect(container.read(activeWorkoutProvider).value, isNotNull);

    // The save flow persists the session through the repository; stub the
    // write so the handler completes and reaches the finish() call.
    when(
      mockRepository.addLocalDrift(any),
    ).thenAnswer((inv) async => inv.positionalArguments.first as WorkoutSession);

    await tester.pumpWidget(renderSessionPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();

    expect(
      await PreferenceHelper.asyncPref.containsKey(PREFS_ACTIVE_WORKOUT),
      false,
      reason: 'saving the session finishes the workout and drops the resume pointer',
    );
    expect(container.read(activeWorkoutProvider).value, isNull);
  });
}
