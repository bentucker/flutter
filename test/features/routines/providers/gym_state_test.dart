/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2020, 2025 wger Team
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

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wger/core/shared_preferences.dart';
import 'package:wger/database/powersync/database.dart';
import 'package:wger/features/account/models/user_profile.dart';
import 'package:wger/features/account/providers/user_profile_notifier.dart';
import 'package:wger/features/account/providers/user_profile_repository.dart';
import 'package:wger/features/exercises/models/exercise.dart';
import 'package:wger/features/routines/models/active_workout.dart';
import 'package:wger/features/routines/models/day.dart';
import 'package:wger/features/routines/models/day_data.dart';
import 'package:wger/features/routines/models/log.dart';
import 'package:wger/features/routines/models/routine.dart';
import 'package:wger/features/routines/models/session.dart';
import 'package:wger/features/routines/models/set_config_data.dart';
import 'package:wger/features/routines/models/slot_data.dart';
import 'package:wger/features/routines/providers/active_workout_notifier.dart';
import 'package:wger/features/routines/providers/gym_state.dart';
import 'package:wger/features/routines/providers/gym_state_notifier.dart';
import 'package:wger/features/routines/providers/routines_notifier.dart';
import 'package:wger/features/routines/providers/workout_session_repository.dart';

import '../../../../test_data/exercises.dart';
import '../../../../test_data/routines.dart';
import '../../../helpers/in_memory_drift.dart';
import '../helpers/routine_form_test_overrides.dart';

void main() {
  late GymStateNotifier notifier;
  late ProviderContainer container;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    container = ProviderContainer.test();
    notifier = container.read(gymStateProvider.notifier);
    notifier.state = notifier.state.copyWith(
      showExercisePages: true,
      showTimerPages: true,
      dayId: 1,
      iteration: 1,
      routine: getTestRoutine(),
    );
    notifier.calculatePages();
  });

  group('GymStateNotifier.markSlotPageAsDone', () {
    test('Correctly changes the flag', () {
      // Arrange
      final slotPage = notifier.state.pages[1].slotPages[1];
      expect(slotPage.type, SlotPageType.log);
      expect(
        notifier.state.pages.every((p) => p.slotPages.every((s) => !s.logDone)),
        true,
        reason: 'All slot pages are initially not done',
      );

      // Act
      notifier.markSlotPageAsDone(slotPage.uuid, isDone: true);

      // Assert
      for (final page in notifier.state.pages.where((p) => p.type == PageType.set)) {
        for (final slot in page.slotPages.where((s) => s.type == SlotPageType.log)) {
          if (slot.uuid == slotPage.uuid) {
            expect(slot.logDone, true);
          } else {
            expect(slot.logDone, false);
          }
        }
      }
    });
  });

  group('GymStateNotifier.recalculateIndices', () {
    test('Correctly recalculates indices if new pages are added', () {
      // Arrange
      final newPages = [
        ...notifier.state.pages.sublist(0, 2),
        PageEntry(
          type: PageType.set,
          pageIndex: 1111,
          uuid: 'new-page-1',
        ),
        PageEntry(
          type: PageType.set,
          pageIndex: 9,
          uuid: 'new-page-2',
        ),
        ...notifier.state.pages.sublist(2),
        PageEntry(
          type: PageType.set,
          pageIndex: 0,
          uuid: 'new-page-3',
          slotPages: [
            SlotPageEntry(
              type: SlotPageType.timer,
              pageIndex: 10,
              setIndex: 9,
              uuid: 'new-slot-1',
            ),
            SlotPageEntry(
              type: SlotPageType.timer,
              pageIndex: 10,
              setIndex: 6,
              uuid: 'new-slot-2',
            ),
            SlotPageEntry(
              type: SlotPageType.timer,
              pageIndex: 100,
              setIndex: 100,
              uuid: 'new-slot-3',
            ),
          ],
        ),
      ];
      notifier.state = notifier.state.copyWith(pages: newPages);

      // Act
      notifier.recalculateIndices();

      // Assert
      final pages = notifier.state.pages;
      expect(pages[0].pageIndex, 0);
      expect(pages[1].pageIndex, 1);

      // These three have the same pageIndex because the new ones don't have any slot
      // pages (this should not happen in practice)
      expect(pages[2].pageIndex, 8);
      expect(pages[3].pageIndex, 8);
      expect(pages[4].pageIndex, 8);

      expect(pages[5].pageIndex, 15);
      expect(pages[6].pageIndex, 16);
      expect(pages[7].pageIndex, 17);

      // Preserve the order of new pages
      expect(pages[7].uuid, 'new-page-3');

      // Slot pages have correct indices, the original order is preserved
      final slotPages = pages[7].slotPages;
      expect(slotPages[0].uuid, 'new-slot-1');
      expect(slotPages[0].pageIndex, 17);
      expect(slotPages[0].setIndex, 0);
      expect(slotPages[1].uuid, 'new-slot-2');
      expect(slotPages[1].pageIndex, 18);
      expect(slotPages[1].setIndex, 1);
      expect(slotPages[2].uuid, 'new-slot-3');
      expect(slotPages[2].pageIndex, 19);
      expect(slotPages[2].setIndex, 2);
    });
  });

  group('GymStateNotifier.replaceExercises', () {
    test('Correctly swaps an exercise', () {
      // Arrange
      final page = notifier.state.pages[1];
      final slotPage = page.slotPages[1];
      expect(slotPage.type, SlotPageType.log);
      expect(
        notifier.state.pages.every((p) => p.exercises.every((e) => e.id != testSquats.id)),
        isTrue,
        reason: 'the new exercise is not part of the routine yet',
      );

      // Act
      notifier.replaceExercises(page.uuid, originalExerciseId: 1, newExercise: testSquats);

      // Assert: every slot page of that page carries the new exercise, and the
      // routine itself was rebuilt too (the log draft reads from it)
      final updated = notifier.state.pages[1];
      expect(
        updated.slotPages
            .where((s) => s.setConfigData != null)
            .map((s) => s.setConfigData!.exercise.id),
        everyElement(testSquats.id),
      );
      expect(updated.exercises.map((e) => e.id), everyElement(testSquats.id));
      expect(
        notifier.state.routine.dayDataGym
            .expand((d) => d.slots)
            .expand((s) => s.setConfigs)
            .every((c) => c.exerciseId != 1),
        isTrue,
        reason: 'the replaced exercise is gone from the routine',
      );
    });
  });

  group('GymStateNotifier.addExerciseAfterPage', () {
    test('Stamps the profile default weight unit on the ad-hoc set configs', () async {
      // Ad-hoc exercises bypass routine hydration, so the notifier itself
      // resolves the profile default: lb (id 2) for an imperial user.
      final profileRepo = MockUserProfileRepository();
      when(
        profileRepo.watchDrift(),
      ).thenAnswer((_) => Stream.value(UserProfile(id: 1, weightUnitStr: 'lb')));

      final imperialContainer = ProviderContainer.test(
        overrides: [
          userProfileRepositoryProvider.overrideWithValue(profileRepo),
          routineWeightUnitProvider.overrideWith((ref) => Stream.value(testWeightUnits)),
        ],
      );
      // Let both streams emit before the notifier reads them (in the app the
      // dashboard keeps them alive long before gym mode starts).
      imperialContainer.listen(userProfileProvider, (_, _) {});
      imperialContainer.listen(routineWeightUnitProvider, (_, _) {});
      await pumpEventQueue();

      final imperialNotifier = imperialContainer.read(gymStateProvider.notifier);
      imperialNotifier.state = imperialNotifier.state.copyWith(
        showExercisePages: true,
        showTimerPages: true,
        dayId: 1,
        iteration: 1,
        routine: getTestRoutine(),
      );
      imperialNotifier.calculatePages();
      final setPage = imperialNotifier.state.pages.firstWhere((p) => p.type == PageType.set);

      imperialNotifier.addExerciseAfterPage(setPage.uuid, newExercise: testSquats);

      // recalculateIndices copies the page objects, so look the page up by uuid.
      final pages = imperialNotifier.state.pages;
      final newPage = pages[pages.indexWhere((p) => p.uuid == setPage.uuid) + 1];
      expect(newPage.slotPages, isNotEmpty);
      for (final slotPage in newPage.slotPages) {
        // testWeightUnit2 has id 2 == WEIGHT_UNIT_LB.
        expect(slotPage.setConfigData!.weightUnit, testWeightUnit2);
        expect(slotPage.setConfigData!.weightUnitId, isNull);
      }
    });
  });

  group('GymStateNotifier.calculatePages, supersets', () {
    // A superset slot holds several exercises that are trained alternating.
    // calculatePages then has to emit one overview page per exercise instead
    // of the single one a normal slot gets.

    SetConfigData configFor(int exerciseId, Exercise exercise) => SetConfigData(
      exerciseId: exerciseId,
      exercise: exercise,
      slotEntryId: exerciseId,
      nrOfSets: 1,
      repetitions: 8,
      repetitionsUnit: testRepetitionUnits.first,
      weight: 40,
      weightUnit: testWeightUnits.first,
      restTime: 60,
      textRepr: '8x40kg',
    );

    /// A routine whose only slot supersets [exerciseIds].
    Routine supersetRoutine(List<int> exerciseIds, {List<SetConfigData>? setConfigs}) {
      final exercises = getTestExercises();
      final day = Day(id: 1, routineId: 1, name: 'Superset day');

      return getTestRoutine()
        ..dayDataGym = [
          DayData(
            iteration: 1,
            date: DateTime(2024, 11, 1),
            day: day,
            slots: [
              SlotData(
                isSuperset: true,
                exerciseIds: exerciseIds,
                setConfigs:
                    setConfigs ?? [for (final id in exerciseIds) configFor(id, exercises[id - 1])],
              ),
            ],
          ),
        ];
    }

    test('emits one overview page per exercise of the slot', () {
      notifier.state = notifier.state.copyWith(
        showExercisePages: true,
        showTimerPages: false,
        dayId: 1,
        iteration: 1,
        routine: supersetRoutine([1, 2]),
      );

      notifier.calculatePages();

      final slotPages = notifier.state.pages[1].slotPages;
      final overviews = slotPages.where((p) => p.type == SlotPageType.exerciseOverview);
      expect(overviews, hasLength(2));
      expect(
        overviews.map((p) => p.setConfigData!.exerciseId),
        [1, 2],
        reason: 'each exercise of the superset gets its own overview page',
      );
      expect(slotPages.where((p) => p.type == SlotPageType.log), hasLength(2));
    });

    test('page indices stay consecutive across the superset', () {
      notifier.state = notifier.state.copyWith(
        showExercisePages: true,
        showTimerPages: false,
        dayId: 1,
        iteration: 1,
        routine: supersetRoutine([1, 2]),
      );

      notifier.calculatePages();

      final indices = notifier.state.pages[1].slotPages.map((p) => p.pageIndex);
      expect(indices, [1, 2, 3, 4]);
    });

    test('an exercise without a set config is skipped instead of crashing', () {
      // The exercise list and the set configs come from separate parts of the
      // API response, so they can disagree while a routine is being edited
      final exercises = getTestExercises();
      final routine = supersetRoutine(
        [1, 2],
        setConfigs: [configFor(1, exercises[0])],
      );
      notifier.state = notifier.state.copyWith(
        showExercisePages: true,
        showTimerPages: false,
        dayId: 1,
        iteration: 1,
        routine: routine,
      );

      notifier.calculatePages();

      final slotPages = notifier.state.pages[1].slotPages;
      expect(
        slotPages
            .where((p) => p.type == SlotPageType.exerciseOverview)
            .single
            .setConfigData!
            .exerciseId,
        1,
      );
      expect(slotPages.where((p) => p.type == SlotPageType.log), hasLength(1));
    });
  });

  group('GymStateNotifier.calculatePages', () {
    test(
      'Correctly generates pages - exercise and timer',
      () {
        // Arrange
        notifier.state = notifier.state.copyWith(
          showExercisePages: true,
          showTimerPages: true,
        );

        // Act
        notifier.calculatePages();

        // Assert
        final pages = notifier.state.pages;
        final setEntry = pages.firstWhere((p) => p.type == PageType.set);
        expect(pages.length, 5, reason: '5 PageEntries (start, set 1, set 2, session, summary)');
        expect(
          setEntry.slotPages.where((p) => p.type == SlotPageType.log).length,
          3,
          reason: 'Three sets',
        );
        expect(
          setEntry.slotPages.where((p) => p.type == SlotPageType.timer).length,
          3,
          reason: 'One timer after each set',
        );
        expect(
          setEntry.slotPages.where((p) => p.type == SlotPageType.exerciseOverview).length,
          1,
          reason: 'One exercise overview at the start',
        );
        expect(setEntry.slotPages[0].type, SlotPageType.exerciseOverview);
        expect(setEntry.slotPages[1].type, SlotPageType.log);
        expect(setEntry.slotPages[2].type, SlotPageType.timer);
        expect(notifier.state.totalPages, 17);
      },
    );

    test('Correctly generates pages - no exercises and no timer', () {
      // Arrange
      notifier.state = notifier.state.copyWith(
        showExercisePages: false,
        showTimerPages: false,
      );

      // Act
      notifier.calculatePages();

      // Assert
      final pages = notifier.state.pages;
      final setEntry = pages.firstWhere((p) => p.type == PageType.set);
      expect(pages.length, 5, reason: '4 PageEntries (start, set 1, set 2, session, summary)');
      expect(
        setEntry.slotPages.where((p) => p.type == SlotPageType.log).length,
        3,
        reason: 'Three sets',
      );
      expect(
        setEntry.slotPages.where((p) => p.type == SlotPageType.timer).length,
        0,
        reason: 'No timer',
      );
      expect(
        setEntry.slotPages.where((p) => p.type == SlotPageType.exerciseOverview).length,
        0,
        reason: 'No overview',
      );
      expect(setEntry.slotPages[0].type, SlotPageType.log);
      expect(setEntry.slotPages[1].type, SlotPageType.log);
      expect(setEntry.slotPages[2].type, SlotPageType.log);
      expect(notifier.state.totalPages, 9);
    });

    test('Correctly generates pages - exercises and no timer', () {
      // Arrange
      notifier.state = notifier.state.copyWith(
        showExercisePages: true,
        showTimerPages: false,
      );

      // Act
      notifier.calculatePages();

      // Assert
      final pages = notifier.state.pages;
      final setEntry = pages.firstWhere((p) => p.type == PageType.set);
      expect(pages.length, 5, reason: '5 PageEntries (start, set 1, set 2, session, summary)');
      expect(
        setEntry.slotPages.where((p) => p.type == SlotPageType.log).length,
        3,
        reason: 'Three sets',
      );
      expect(
        setEntry.slotPages.where((p) => p.type == SlotPageType.timer).length,
        0,
        reason: 'No timer',
      );
      expect(
        setEntry.slotPages.where((p) => p.type == SlotPageType.exerciseOverview).length,
        1,
        reason: 'One exercise overview at the start',
      );
      expect(setEntry.slotPages.length, 4);
      expect(setEntry.slotPages[0].type, SlotPageType.exerciseOverview);
      expect(setEntry.slotPages[1].type, SlotPageType.log);
      expect(setEntry.slotPages[2].type, SlotPageType.log);
      expect(setEntry.slotPages[3].type, SlotPageType.log);
      expect(notifier.state.totalPages, 11);
    });
  });

  group('GymStateNotifier.setLogScopeWeeks', () {
    test('Sets the scope and persists it', () async {
      // Act
      notifier.setLogScopeWeeks(12);
      await pumpEventQueue();

      // Assert
      expect(notifier.state.logScopeWeeks, 12);
      expect(await PreferenceHelper.asyncPref.getInt(PREFS_LOG_SCOPE_WEEKS), 12);
    });

    test('Resets the scope to the current routine', () async {
      // Arrange
      notifier.setLogScopeWeeks(12);
      await pumpEventQueue();

      // Act
      notifier.setLogScopeWeeks(null);
      await pumpEventQueue();

      // Assert
      expect(notifier.state.logScopeWeeks, isNull);
      expect(await PreferenceHelper.asyncPref.getInt(PREFS_LOG_SCOPE_WEEKS), isNull);
    });
  });

  group('GymStateNotifier.setShowWorkoutDuration', () {
    test('Sets the flag and persists it', () async {
      // Act
      notifier.setShowWorkoutDuration(false);
      await pumpEventQueue();

      // Assert
      expect(notifier.state.showWorkoutDuration, false);
      expect(await PreferenceHelper.asyncPref.getBool(PREFS_SHOW_WORKOUT_DURATION), false);
    });
  });

  group('GymStateNotifier.startWorkout', () {
    test('Resets the workout start time to now', () {
      // Arrange
      notifier.state = notifier.state.copyWith(workoutStart: DateTime(2024, 5, 1, 10, 0));

      // Act
      withClock(Clock.fixed(DateTime(2024, 5, 1, 17, 30, 21)), () {
        notifier.startWorkout();
      });

      // Assert
      expect(notifier.state.workoutStart, DateTime(2024, 5, 1, 17, 30, 21));
      expect(notifier.state.startTime, const TimeOfDay(hour: 17, minute: 30));
    });
  });

  group('GymStateNotifier.clear', () {
    test('Resets the workout start time', () {
      // Arrange
      notifier.state = notifier.state.copyWith(workoutStart: DateTime(2024, 5, 1, 10, 0));

      // Act
      withClock(Clock.fixed(DateTime(2024, 5, 2, 9, 15)), () {
        notifier.clear();
      });

      // Assert
      expect(notifier.state.workoutStart, DateTime(2024, 5, 2, 9, 15));
    });
  });

  group('GymStateNotifier.initData', () {
    test('Resets the workout start time when the state is reset', () {
      // Arrange
      notifier.state = notifier.state.copyWith(
        isInitialized: false,
        workoutStart: DateTime(2024, 5, 1, 10, 0),
      );

      // Act
      withClock(Clock.fixed(DateTime(2024, 5, 2, 18, 0)), () {
        notifier.initData(getTestRoutine(), 1, 1);
      });

      // Assert
      expect(notifier.state.workoutStart, DateTime(2024, 5, 2, 18, 0));
    });

    test('Keeps the workout start time when the state is not reset', () {
      // Arrange
      notifier.state = notifier.state.copyWith(
        isInitialized: true,
        workoutStart: DateTime(2024, 5, 1, 10, 0),
      );

      // Act
      notifier.initData(getTestRoutine(), 1, 1);

      // Assert
      expect(notifier.state.workoutStart, DateTime(2024, 5, 1, 10, 0));
    });

    test('Returns the stored page so a resumed workout reopens where it left off', () {
      // The return value is what gym_mode jumps the PageView to
      notifier.state = notifier.state.copyWith(
        isInitialized: true,
        dayId: 1,
        currentPage: 4,
      );

      expect(notifier.initData(getTestRoutine(), 1, 1), 4);
      expect(notifier.state.currentPage, 4);
    });

    test('Starting a different day resets to the first page', () {
      notifier.state = notifier.state.copyWith(
        isInitialized: true,
        dayId: 1,
        currentPage: 4,
      );

      expect(notifier.initData(getTestRoutine(), 2, 1), 0);
      expect(notifier.state.dayId, 2);
    });

    test('An expired validUntil resets even on the same day', () {
      // The session is only resumable for a while; after that the same day
      // starts over instead of dropping the user in the middle of it
      notifier.state = notifier.state.copyWith(
        isInitialized: true,
        dayId: 1,
        currentPage: 4,
        validUntil: DateTime(2024, 5, 1, 10, 0),
      );

      final page = withClock(
        Clock.fixed(DateTime(2024, 5, 2, 18, 0)),
        () => notifier.initData(getTestRoutine(), 1, 1),
      );

      expect(page, 0);
    });
  });

  group('GymModeState.copyWith', () {
    test('Keeps the log scope when it is not passed', () {
      final state = notifier.state.copyWith(logScopeWeeks: 8);

      expect(state.copyWith(showDistinctLogs: false).logScopeWeeks, 8);
    });

    test('Clears the log scope on clearLogScopeWeeks', () {
      final state = notifier.state.copyWith(logScopeWeeks: 8);

      expect(state.copyWith(clearLogScopeWeeks: true).logScopeWeeks, isNull);
    });
  });

  group('GymStateNotifier.restoreCompletionFromLogs', () {
    late DriftPowersyncDatabase db;
    late ProviderContainer container;
    late GymStateNotifier sut;

    // The first day of the test routine (dayId 1) has two slots:
    //  - slot 0: exercise id 1, slotEntryId 1, 3 sets
    //  - slot 1: exercise id 6, slotEntryId 1, 3 sets
    WorkoutSession sessionWithLogs(List<int> exerciseIds) {
      final session = WorkoutSession(
        id: 's1',
        routineId: 1,
        dayId: 1,
        date: clock.now(),
        logs: [
          for (final exerciseId in exerciseIds)
            Log(
              exerciseId: exerciseId,
              routineId: 1,
              sessionId: 's1',
              slotEntryId: 1,
              weight: 50,
              repetitions: 5,
              date: clock.now(),
            ),
        ],
      );
      return session;
    }

    Future<void> bootstrap(List<WorkoutSession> sessions) async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      db = await openTestDatabase();
      container = ProviderContainer(
        overrides: [
          workoutSessionRepositoryProvider.overrideWithValue(_FakeSessionRepo(db, sessions)),
        ],
      );
      sut = container.read(gymStateProvider.notifier);
      sut.state = sut.state.copyWith(
        // Keep the page tree simple: only log pages, no overview/timer.
        showExercisePages: false,
        showTimerPages: false,
        dayId: 1,
        iteration: 1,
        routine: getTestRoutine(),
      );
      sut.calculatePages();
    }

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    List<SlotPageEntry> logPagesOfSlot(int slotIndex) => sut.state.pages
        .where((p) => p.type == PageType.set)
        .toList()[slotIndex]
        .slotPages
        .where((s) => s.type == SlotPageType.log)
        .toList();

    test('marks the first k log pages of each group done from persisted logs', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        // 1 log for slot 0 (exercise 1), 2 logs for slot 1 (exercise 6).
        await bootstrap([
          sessionWithLogs([1, 6, 6]),
        ]);

        // Nothing is done before restoring.
        expect(
          sut.state.pages.expand((p) => p.slotPages).where((s) => s.logDone),
          isEmpty,
        );

        await sut.restoreCompletionFromLogs();

        final slot0 = logPagesOfSlot(0);
        final slot1 = logPagesOfSlot(1);
        expect(slot0.where((s) => s.logDone).length, 1);
        expect(slot0[0].logDone, true, reason: 'first set of slot 0 is done');
        expect(slot0[1].logDone, false);
        expect(slot1.where((s) => s.logDone).length, 2);
        expect(slot1[0].logDone, true);
        expect(slot1[1].logDone, true);
        expect(slot1[2].logDone, false);
      });
    });

    test('completion is rebuilt after a simulated re-entry (calculatePages + restore)', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        await bootstrap([
          sessionWithLogs([1]),
        ]);

        // Simulate re-entry: the page tree is rebuilt fresh (logDone=false)...
        sut.calculatePages();
        expect(logPagesOfSlot(0)[0].logDone, false);

        // ...then completion is reconstructed from the persisted log.
        await sut.restoreCompletionFromLogs();
        expect(logPagesOfSlot(0)[0].logDone, true);
      });
    });

    test('a set logged after entry survives a settings toggle (snapshot maintained)', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        await bootstrap([
          sessionWithLogs([1]),
        ]);
        await sut.restoreCompletionFromLogs();
        expect(logPagesOfSlot(0)[0].logDone, true);

        // Simulate logging a second set mid-session.
        sut.markSlotPageAsDone(logPagesOfSlot(0)[1].uuid, isDone: true);

        // Toggling a setting rebuilds the page tree; the snapshot must re-tick
        // both sets without any extra DB read.
        sut.setShowTimerPages(true);

        final slot0 = logPagesOfSlot(0);
        expect(
          slot0.where((s) => s.logDone).length,
          2,
          reason: 'restored set + after-entry set both stay ticked after a toggle',
        );

        // setShowTimerPages fires an unawaited _savePrefs; let it settle before
        // the container is disposed in tearDown.
        await pumpEventQueue();
      });
    });

    test('prefers the session matching the current dayId (no cross-day contamination)', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        // A *different* routine day trained the same calendar date: it shares
        // the (routine, date) key space and even reuses slotEntryId/exerciseId,
        // so only matching on dayId keeps it from over-completing the current
        // day's slots.
        final dayTwoSession = WorkoutSession(
          id: 's2',
          routineId: 1,
          dayId: 2,
          date: clock.now(),
          logs: [
            for (var i = 0; i < 3; i++)
              Log(
                exerciseId: 1,
                routineId: 1,
                sessionId: 's2',
                slotEntryId: 1,
                weight: 50,
                repetitions: 5,
                date: clock.now(),
              ),
          ],
        );
        final dayOneSession = sessionWithLogs([1]); // dayId 1, a single log

        // Return the day-2 session FIRST so a naive firstOrNull would pick it.
        await bootstrap([dayTwoSession, dayOneSession]);

        await sut.restoreCompletionFromLogs();

        final slot0 = logPagesOfSlot(0);
        expect(
          slot0.where((s) => s.logDone).length,
          1,
          reason: 'uses the dayId-1 session (1 log), not the day-2 session (3 logs)',
        );
        expect(slot0[0].logDone, true);
      });
    });

    test('keys completion on (slotEntryId, exerciseId), not exerciseId alone', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        final exercise = getTestExercises()[0]; // id 1
        // A single log for the *second* slot entry (slotEntryId 20).
        final session = WorkoutSession(
          id: 's1',
          routineId: 1,
          dayId: 1,
          date: clock.now(),
          logs: [
            Log(
              exerciseId: exercise.id,
              routineId: 1,
              sessionId: 's1',
              slotEntryId: 20,
              weight: 50,
              repetitions: 5,
              date: clock.now(),
            ),
          ],
        );
        await bootstrap([session]);

        // Two log pages with the SAME exercise but DIFFERENT slotEntryId (e.g. a
        // repeated exercise / superset across two slots).
        SlotPageEntry logPage(int slotEntryId, int pageIndex) => SlotPageEntry(
          type: SlotPageType.log,
          pageIndex: pageIndex,
          setIndex: pageIndex,
          setConfigData: SetConfigData(
            textRepr: '-/-',
            exerciseId: exercise.id,
            exercise: exercise,
            slotEntryId: slotEntryId,
          ),
        );
        sut.state = sut.state.copyWith(
          pages: [
            PageEntry(
              type: PageType.set,
              pageIndex: 0,
              slotPages: [logPage(10, 0), logPage(20, 1)],
            ),
          ],
        );

        await sut.restoreCompletionFromLogs();

        final logs = sut.state.pages.first.slotPages;
        // The log targets slotEntryId 20, so only that page is done — keying on
        // exerciseId alone would (wrongly) mark the first page (slotEntryId 10).
        expect(logs[0].logDone, false, reason: 'slotEntryId 10 page must stay undone');
        expect(logs[1].logDone, true, reason: 'slotEntryId 20 page is the one logged');
      });
    });

    test('markSlotPageAsDone undo decrements the snapshot so a toggle un-ticks', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        await bootstrap([
          sessionWithLogs([1]),
        ]);
        await sut.restoreCompletionFromLogs();
        expect(logPagesOfSlot(0)[0].logDone, true);

        // Undo the set: this must decrement the in-memory snapshot.
        sut.markSlotPageAsDone(logPagesOfSlot(0)[0].uuid, isDone: false);
        expect(logPagesOfSlot(0)[0].logDone, false);

        // A settings toggle rebuilds the page tree from the snapshot; the set
        // must stay un-ticked (i.e. the decrement actually happened).
        sut.setShowTimerPages(true);
        expect(
          logPagesOfSlot(0)[0].logDone,
          false,
          reason: 'undo decremented the snapshot, so the set is not re-ticked',
        );

        await pumpEventQueue();
      });
    });

    test('clamps completion when there are more logs than prescribed sets', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        // Slot 0 prescribes 3 sets; persist 5 logs for it.
        await bootstrap([
          sessionWithLogs([1, 1, 1, 1, 1]),
        ]);

        await sut.restoreCompletionFromLogs();

        final slot0 = logPagesOfSlot(0);
        expect(slot0.length, 3);
        expect(
          slot0.every((s) => s.logDone),
          true,
          reason: 'all 3 prescribed sets are done and the 2 extra logs are ignored',
        );
      });
    });
  });

  group('GymStateNotifier.restoreCompletionFromLogs (live stream)', () {
    test('resolves on the first emission of a non-closing stream', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
        final db = await openTestDatabase();
        addTearDown(db.close);

        // A controller that emits but is never closed (mirrors the real drift
        // watch stream, which stays open for the session lifetime).
        final controller = StreamController<List<WorkoutSession>>();
        addTearDown(controller.close);

        final container = ProviderContainer(
          overrides: [
            workoutSessionRepositoryProvider.overrideWithValue(
              _StreamSessionRepo(db, controller.stream),
            ),
          ],
        );
        addTearDown(container.dispose);

        final sut = container.read(gymStateProvider.notifier);
        sut.state = sut.state.copyWith(
          showExercisePages: false,
          showTimerPages: false,
          dayId: 1,
          iteration: 1,
          routine: getTestRoutine(),
        );
        sut.calculatePages();

        final session = WorkoutSession(
          id: 's1',
          routineId: 1,
          dayId: 1,
          date: clock.now(),
          logs: [
            Log(
              exerciseId: 1,
              routineId: 1,
              sessionId: 's1',
              slotEntryId: 1,
              weight: 50,
              repetitions: 5,
              date: clock.now(),
            ),
          ],
        );
        // Emit one snapshot, but never close the stream.
        controller.add([session]);

        // Must resolve on the first emission rather than waiting for close.
        // `completes` asserts the future finishes without relying on a tight
        // wall-clock budget; a genuine hang is caught by the test harness's own
        // timeout instead of a flaky 5s deadline.
        await expectLater(sut.restoreCompletionFromLogs(), completes);

        final slot0 = sut.state.pages
            .where((p) => p.type == PageType.set)
            .first
            .slotPages
            .where((s) => s.type == SlotPageType.log)
            .toList();
        expect(slot0[0].logDone, true);
      });
    });
  });

  group('GymStateNotifier.initData resume cursor', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      // `PreferenceHelper.asyncPref` binds its backing store at construction, so
      // clear that exact singleton instance to avoid bleed from a prior test.
      await PreferenceHelper.asyncPref.clear();
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('restores the cursor from a matching persisted pointer on reset', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        await container
            .read(activeWorkoutProvider.notifier)
            .start(
              ActiveWorkout(
                routineId: 1,
                dayId: 1,
                iteration: 1,
                startedAt: clock.now(),
                currentPage: 5,
                validUntil: clock.now().add(const Duration(hours: 2)),
              ),
            );
        // Ensure the pointer is loaded before initData reads it synchronously.
        await container.read(activeWorkoutProvider.future);

        final sut = container.read(gymStateProvider.notifier);
        final initialPage = sut.initData(getTestRoutine(), 1, 1);

        expect(initialPage, 5, reason: 'cursor restored from the pointer');
        expect(sut.state.currentPage, 5);
      });
    });

    test('a resumed workout keeps its original start instant', () async {
      // Regression: workoutStart was unconditionally reset to now, so a
      // resumed workout's elapsed timer and derived session start time
      // restarted at the resume moment.
      final originalStart = DateTime(2026, 4, 15, 10, 30);
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        await container
            .read(activeWorkoutProvider.notifier)
            .start(
              ActiveWorkout(
                routineId: 1,
                dayId: 1,
                iteration: 1,
                startedAt: originalStart,
                currentPage: 5,
                validUntil: clock.now().add(const Duration(hours: 2)),
              ),
            );
        await container.read(activeWorkoutProvider.future);

        final sut = container.read(gymStateProvider.notifier);
        sut.initData(getTestRoutine(), 1, 1);

        expect(sut.state.workoutStart, originalStart);
        expect(sut.state.startTime, TimeOfDay.fromDateTime(originalStart));
      });
    });

    test('starts at page 0 when no pointer matches', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        // No pointer persisted.
        expect(await container.read(activeWorkoutProvider.future), isNull);

        final sut = container.read(gymStateProvider.notifier);
        final initialPage = sut.initData(getTestRoutine(), 1, 1);

        expect(initialPage, 0);

        // Let the fire-and-forget pointer write settle before disposal.
        await Future<void>.delayed(Duration.zero);
      });
    });

    test('writes a freshly-anchored pointer even when the prior window expired', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        // No pointer persisted yet; simulate a stale in-memory window so the
        // pointer write must NOT reuse it (the path where Issue 1's bug bit).
        final sut = container.read(gymStateProvider.notifier);
        sut.state = sut.state.copyWith(
          dayId: 1,
          iteration: 1,
          routine: getTestRoutine(),
          validUntil: clock.now().subtract(const Duration(hours: 1)),
        );

        sut.initData(getTestRoutine(), 1, 1);

        // Let the fire-and-forget start() settle.
        await pumpEventQueue();

        final written = container.read(activeWorkoutProvider).value;
        expect(written, isNotNull);
        expect(
          written!.validUntil.isAfter(clock.now()),
          true,
          reason: 'the pointer must be born with a fresh window, never already expired',
        );
        expect(written.validUntil, clock.now().add(DEFAULT_DURATION));
      });
    });

    test('does not resume from an expired pointer (page 0)', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        await container
            .read(activeWorkoutProvider.notifier)
            .start(
              ActiveWorkout(
                routineId: 1,
                dayId: 1,
                iteration: 1,
                startedAt: clock.now().subtract(const Duration(hours: 6)),
                currentPage: 5,
                validUntil: clock.now().subtract(const Duration(hours: 1)), // already expired
              ),
            );
        await container.read(activeWorkoutProvider.future);

        final sut = container.read(gymStateProvider.notifier);
        final initialPage = sut.initData(getTestRoutine(), 1, 1);

        expect(initialPage, 0, reason: 'an expired pointer must not resume');
        await Future<void>.delayed(Duration.zero);
      });
    });

    test('does not resume from a pointer for a different routine (page 0)', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        await container
            .read(activeWorkoutProvider.notifier)
            .start(
              ActiveWorkout(
                routineId: 999, // different routine
                dayId: 1,
                iteration: 1,
                startedAt: clock.now(),
                currentPage: 5,
                validUntil: clock.now().add(const Duration(hours: 2)),
              ),
            );
        await container.read(activeWorkoutProvider.future);

        final sut = container.read(gymStateProvider.notifier);
        final initialPage = sut.initData(getTestRoutine(), 1, 1);

        expect(initialPage, 0, reason: 'a mismatched-routine pointer must not resume');
        await Future<void>.delayed(Duration.zero);
      });
    });

    test('does not resume from a pointer for a different day (page 0)', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        await container
            .read(activeWorkoutProvider.notifier)
            .start(
              ActiveWorkout(
                routineId: 1,
                dayId: 2, // different day
                iteration: 1,
                startedAt: clock.now(),
                currentPage: 5,
                validUntil: clock.now().add(const Duration(hours: 2)),
              ),
            );
        await container.read(activeWorkoutProvider.future);

        final sut = container.read(gymStateProvider.notifier);
        final initialPage = sut.initData(getTestRoutine(), 1, 1);

        expect(initialPage, 0, reason: 'a mismatched-day pointer must not resume');
        await Future<void>.delayed(Duration.zero);
      });
    });

    test('clamps a resume cursor that points past the last real page', () async {
      await withClock(Clock.fixed(DateTime(2026, 4, 15, 12)), () async {
        await container
            .read(activeWorkoutProvider.notifier)
            .start(
              ActiveWorkout(
                routineId: 1,
                dayId: 1,
                iteration: 1,
                startedAt: clock.now(),
                currentPage: 9999, // absurdly large → would land on the summary
                validUntil: clock.now().add(const Duration(hours: 2)),
              ),
            );
        await container.read(activeWorkoutProvider.future);

        final sut = container.read(gymStateProvider.notifier);
        final initialPage = sut.initData(getTestRoutine(), 1, 1);

        // Never resume onto the summary (last) page.
        expect(initialPage, lessThan(sut.state.totalPages - 1));
        expect(initialPage, sut.state.totalPages - 2);
        await Future<void>.delayed(Duration.zero);
      });
    });
  });
}

/// Fake session repository that yields a fixed in-memory list, bypassing the
/// drift stream so the unit tests stay synchronous and deterministic.
class _FakeSessionRepo extends WorkoutSessionRepository {
  _FakeSessionRepo(super.db, this._sessions);

  final List<WorkoutSession> _sessions;

  @override
  Stream<List<WorkoutSession>> watchAllDrift() => Stream.value(_sessions);
}

/// Fake session repository backed by an arbitrary (possibly non-closing) stream,
/// used to prove `restoreCompletionFromLogs` resolves on the first emission of a
/// live stream without hanging.
class _StreamSessionRepo extends WorkoutSessionRepository {
  _StreamSessionRepo(super.db, this._stream);

  final Stream<List<WorkoutSession>> _stream;

  @override
  Stream<List<WorkoutSession>> watchAllDrift() => _stream;
}
