/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2025 - 2026 wger Team
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
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wger/core/widgets/error.dart';
import 'package:wger/features/exercises/models/exercise.dart';
import 'package:wger/features/routines/gym_mode.dart';
import 'package:wger/features/routines/models/day_data.dart';
import 'package:wger/features/routines/models/log.dart';
import 'package:wger/features/routines/models/routine.dart';
import 'package:wger/features/routines/models/set_config_data.dart';
import 'package:wger/features/routines/models/slot_data.dart';
import 'package:wger/features/routines/providers/gym_log_notifier.dart';
import 'package:wger/features/routines/providers/gym_state.dart';
import 'package:wger/features/routines/providers/gym_state_notifier.dart';
import 'package:wger/features/routines/providers/plate_weights.dart';
import 'package:wger/features/routines/providers/workout_logs_repository.dart';
import 'package:wger/features/routines/widgets/gym_mode/log_page.dart';
import 'package:wger/features/routines/widgets/logs/log_edit_dialog.dart';
import 'package:wger/features/routines/widgets/plate_calculator.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

import '../../../../../test_data/exercises.dart';
import '../../../../../test_data/routines.dart' as testdata;
import 'log_page_test.mocks.dart';

/// Strips the exercise off a fixture log, watchLogsByExerciseDrift only joins the units
Log asDriftLog(Log log) =>
    Log(
        id: log.id,
        exerciseId: log.exerciseId,
        iteration: log.iteration,
        slotEntryId: log.slotEntryId,
        routineId: log.routineId,
        sessionId: log.sessionId,
        repetitions: log.repetitions,
        rir: log.rir,
        weight: log.weight,
        date: log.date,
      )
      ..repetitionUnit = log.repetitionsUnitObj
      ..weightUnit = log.weightUnitObj;

@GenerateMocks([WorkoutLogRepository])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LogPage tests', () {
    late List<Exercise> testExercises;
    late ProviderContainer container;
    late MockWorkoutLogRepository mockWorkoutLogRepo;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      testExercises = getTestExercises();
      mockWorkoutLogRepo = MockWorkoutLogRepository();
      when(mockWorkoutLogRepo.addLocalDrift(any)).thenAnswer((_) async {});
      // Past logs on the page come from this stream (per exercise); reuse the
      // test routine's logs so the previous-entries assertions keep working.
      when(
        mockWorkoutLogRepo.watchLogsByExerciseDrift(
          routineId: anyNamed('routineId'),
          exerciseId: anyNamed('exerciseId'),
        ),
      ).thenAnswer((invocation) {
        final exerciseId = invocation.namedArguments[#exerciseId] as int;
        return Stream.value(
          testdata.getTestRoutine().filterLogsByExercise(exerciseId).map(asDriftLog).toList(),
        );
      });
      container = ProviderContainer.test(
        overrides: [workoutLogRepositoryProvider.overrideWithValue(mockWorkoutLogRepo)],
      );
    });

    /// Seeds the gym state with [routine] and navigates to the first log page
    /// (index 2: start -> exercise overview -> log). [setCurrentPage] also
    /// seeds gymLogProvider with the log template for that slot.
    void seedLogPage(Routine routine) {
      final notifier = container.read(gymStateProvider.notifier);
      notifier.initData(routine, routine.days.first.id!, 1);
      notifier.setCurrentPage(2);
    }

    Future<void> pumpLogPage(WidgetTester tester) async {
      // The widget resolves its own slot now, so hand it the uuid of the slot
      // the gym state was seeded on (via setCurrentPage above).
      final slotUuid = container.read(gymStateProvider).getSlotEntryPageByIndex()!.uuid;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              // A PageView gives LogPage's PageController something to attach to.
              body: Builder(
                builder: (context) {
                  final controller = PageController();
                  return PageView(
                    controller: controller,
                    children: [LogPage(controller, slotUuid)],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('handles null reps/weight without crashing', (tester) async {
      final notifier = container.read(gymStateProvider.notifier);
      final routine = testdata.getTestRoutine();
      routine.dayDataGym = [
        DayData(
          iteration: 1,
          date: DateTime(2024, 11, 01),
          label: '',
          day: routine.dayDataGym.first.day,
          slots: [
            SlotData(
              isSuperset: false,
              exerciseIds: [testExercises[0].id],
              setConfigs: [
                SetConfigData(
                  exerciseId: testExercises[0].id,
                  exercise: testExercises[0],
                  slotEntryId: 1,
                  nrOfSets: 1,
                  repetitions: null,
                  repetitionsUnit: null,
                  weight: null,
                  weightUnit: null,
                  restTime: 120,
                  rir: 1.5,
                  rpe: 8,
                  textRepr: '3x100kg',
                ),
              ],
            ),
          ],
        ),
      ];
      notifier.initData(routine, routine.days.first.id!, 1);
      notifier.setCurrentPage(2);

      expect(notifier.state.getSlotEntryPageByIndex()!.type, SlotPageType.log);
      await pumpLogPage(tester);
      expect(find.byType(LogPage), findsOneWidget);
    });

    testWidgets('plates follow the weight of the set on screen without editing', (tester) async {
      // Regression: the plate row only learned the weight from edits of the
      // weight field, so a fresh page showed the previous page's plates, or
      // "not possible" (no weight yet) until the field was touched.
      seedLogPage(testdata.getTestRoutine());
      await pumpLogPage(tester);

      final weight = container.read(gymLogProvider)!.weight!;
      final plates = container.read(plateCalculatorProvider);
      final expected = groupPlates(
        plateCalculator(weight, plates.barWeight, plates.selectedPlates),
      );
      expect(expected, isNotEmpty, reason: 'fixture weight $weight must be loadable');
      expect(find.text('Not possible to reach weight with available plates'), findsNothing);
      expect(find.byType(PlateWeight), findsNWidgets(expected.length));

      // Another set on the same page widget (e.g. after a page change)
      container
          .read(gymLogProvider.notifier)
          .setWeight(weight + 2 * plates.selectedPlates.reduce(max));
      await tester.pump();
      final updated = groupPlates(
        plateCalculator(
          weight + 2 * plates.selectedPlates.reduce(max),
          plates.barWeight,
          plates.selectedPlates,
        ),
      );
      expect(find.byType(PlateWeight), findsNWidgets(updated.length));
    });

    testWidgets('a barless exercise splits the whole weight over both sides', (tester) async {
      seedLogPage(testdata.getTestRoutine());
      await pumpLogPage(tester);
      final log = container.read(gymLogProvider)!;
      final plates = container.read(plateCalculatorProvider);
      List<num> shown() =>
          tester.widgetList<PlateWeight>(find.byType(PlateWeight)).map((w) => w.value).toList();
      List<num> expected(num bar) =>
          groupPlates(plateCalculator(100, bar, plates.selectedPlates)).keys.toList();
      expect(
        expected(0),
        isNot(expected(plates.barWeight)),
        reason: 'fixture must tell them apart',
      );

      container.read(gymLogProvider.notifier).setWeight(100);
      await tester.pump();
      expect(shown(), expected(plates.barWeight));

      container.read(plateCalculatorProvider.notifier).setBarless(log.exerciseId, true);
      await tester.pump();
      expect(shown(), expected(0));
    });

    group('this workout', () {
      // Two identical sets saved during this workout (the second by mistake),
      // plus the fixture's older logs
      late List<Log> current;
      // The older log the current sets were copied from: same numbers
      late String twinId;

      Future<void> pumpWithCurrentLogs(WidgetTester tester) async {
        // Phone-sized, so the lazily built list reaches the older logs
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        seedLogPage(testdata.getTestRoutine());
        final page = container.read(gymStateProvider).getSlotEntryPageByIndex()!;
        final cfg = page.setConfigData!;
        final template = testdata.getTestRoutine().filterLogsByExercise(cfg.exerciseId).first;
        twinId = template.id!;
        final now = container.read(gymStateProvider).workoutStart;
        current = [
          for (final (i, id) in ['now-1', 'now-2'].indexed)
            asDriftLog(
              template.copyWith(
                date: now.add(Duration(minutes: 1 + i)),
                slotEntryId: cfg.slotEntryId,
                exerciseId: cfg.exerciseId,
              )..id = id,
            ),
        ];
        when(
          mockWorkoutLogRepo.watchLogsByExerciseDrift(
            routineId: anyNamed('routineId'),
            exerciseId: anyNamed('exerciseId'),
            since: anyNamed('since'),
          ),
        ).thenAnswer(
          (_) => Stream.value([
            ...current.reversed,
            ...testdata.getTestRoutine().filterLogsByExercise(cfg.exerciseId).map(asDriftLog),
          ]),
        );
        when(mockWorkoutLogRepo.deleteLocalDrift(any)).thenAnswer((_) async {});
        await pumpLogPage(tester);
      }

      testWidgets('lists every set of this workout, duplicates included', (tester) async {
        await pumpWithCurrentLogs(tester);

        expect(find.text('Your workout today'), findsOneWidget);
        expect(find.byKey(const ValueKey('current-log-now-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('current-log-now-2')), findsOneWidget);
        // Only this workout's sets get the menu
        final menu = find.byWidgetPredicate((w) => w is PopupMenuButton);
        final pastRows = find.byWidgetPredicate(
          (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('past-log-'),
        );
        expect(pastRows, findsWidgets, reason: 'older logs must still be listed');
        // Collapsing identical sets must not fold an older set into today's
        expect(find.byKey(ValueKey('past-log-$twinId')), findsOneWidget);
        expect(find.descendant(of: pastRows.first, matching: menu), findsNothing);
        expect(
          find.descendant(of: find.byKey(const ValueKey('current-log-now-1')), matching: menu),
          findsOneWidget,
        );
      });

      testWidgets('edit opens the log edit dialog', (tester) async {
        await pumpWithCurrentLogs(tester);

        await tester.tap(find.byKey(const ValueKey('current-log-menu-now-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();

        expect(find.byType(LogEditDialog), findsOneWidget);
      });

      testWidgets('delete removes the set after confirming and unticks one set', (tester) async {
        await pumpWithCurrentLogs(tester);
        final gym = container.read(gymStateProvider.notifier);
        final uuid = container.read(gymStateProvider).getSlotEntryPageByIndex()!.uuid;
        gym.markSlotPageAsDone(uuid, isDone: true);
        expect(container.read(gymStateProvider).getSlotEntryPageByIndex()!.logDone, true);

        await tester.tap(find.byKey(const ValueKey('current-log-menu-now-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        verifyNever(mockWorkoutLogRepo.deleteLocalDrift(any));
        await tester.tap(find.widgetWithText(TextButton, 'Delete'));
        await tester.pumpAndSettle();

        verify(mockWorkoutLogRepo.deleteLocalDrift('now-2')).called(1);
        expect(container.read(gymStateProvider).getSlotEntryPageByIndex()!.logDone, false);
      });

      testWidgets('copy fills the form like tapping the row', (tester) async {
        await pumpWithCurrentLogs(tester);

        await tester.tap(find.byKey(const ValueKey('current-log-menu-now-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();

        expect(find.text('Data copied to new entry'), findsOneWidget);
        expect(container.read(gymLogProvider)!.weight, current.first.weight);
      });
    });

    test('logDeleted keeps every set ticked when an extra set is removed', () {
      seedLogPage(testdata.getTestRoutine());
      final state = container.read(gymStateProvider);
      final cfg = state.getSlotEntryPageByIndex()!.setConfigData!;
      bool matches(SlotPageEntry sp) =>
          sp.type == SlotPageType.log &&
          sp.setConfigData?.slotEntryId == cfg.slotEntryId &&
          sp.setConfigData?.exercise.id == cfg.exercise.id;
      List<bool> ticks() => [
        for (final page in container.read(gymStateProvider).pages)
          for (final sp in page.slotPages)
            if (matches(sp)) sp.logDone,
      ];
      final sets = ticks().length;
      final gym = container.read(gymStateProvider.notifier);
      final uuid = state.getSlotEntryPageByIndex()!.uuid;
      // One more log than prescribed sets
      for (var i = 0; i <= sets; i++) {
        gym.markSlotPageAsDone(uuid, isDone: true);
      }

      gym.logDeleted(slotEntryId: cfg.slotEntryId, exerciseId: cfg.exercise.id);
      expect(ticks(), List.filled(sets, true), reason: 'the extra set was the one removed');

      gym.logDeleted(slotEntryId: cfg.slotEntryId, exerciseId: cfg.exercise.id);
      expect(ticks(), [...List.filled(sets - 1, true), false]);
    });

    testWidgets('renders without crashing for the default slot entry page', (tester) async {
      seedLogPage(testdata.getTestRoutine());
      await pumpLogPage(tester);

      expect(find.byType(LogPage), findsOneWidget);
    });

    testWidgets('copy from past log updates form fields and shows a SnackBar', (tester) async {
      seedLogPage(testdata.getTestRoutine());
      await pumpLogPage(tester);

      final pastLogTile = find.byWidgetPredicate(
        (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('past-log-'),
      );
      expect(pastLogTile, findsWidgets);
      await tester.tap(pastLogTile.first);
      await tester.pumpAndSettle();

      final editableFields = find.byType(EditableText);
      expect(editableFields, findsWidgets);
      final repText = tester.widget<EditableText>(editableFields.at(0)).controller.text;
      final weightText = tester.widget<EditableText>(editableFields.at(1)).controller.text;
      // `contains` would also pass on the prefilled weight of 100
      expect(repText, '10');
      expect(weightText, '10');
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('shows an error indicator when past logs fail to load', (tester) async {
      // Error via a stream event (not a build throw), so riverpod surfaces it
      // as state instead of scheduling a retry timer.
      final controller = StreamController<List<Log>>();
      addTearDown(controller.close);
      when(
        mockWorkoutLogRepo.watchLogsByExerciseDrift(
          routineId: anyNamed('routineId'),
          exerciseId: anyNamed('exerciseId'),
        ),
      ).thenAnswer((_) => controller.stream);

      seedLogPage(testdata.getTestRoutine());
      await pumpLogPage(tester);

      controller.addError(Exception('boom'));
      await tester.pumpAndSettle();

      expect(find.byType(StreamErrorIndicator), findsOneWidget);
    });

    testWidgets('save button persists the entered reps/weight with slot/routine/iteration', (
      tester,
    ) async {
      seedLogPage(testdata.getTestRoutine());
      await pumpLogPage(tester);

      // Overwrite the pre-filled values so the assertion proves the user's
      // edits flow through, not just the set-config defaults.
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '12'); // reps
      await tester.enterText(fields.at(1), '34'); // weight
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('save-log-button')));
      await tester.pumpAndSettle();

      final gymState = container.read(gymStateProvider);
      final captured = verify(
        mockWorkoutLogRepo.addLocalDrift(captureAny, dayId: captureAnyNamed('dayId')),
      ).captured;
      final saved = captured[0] as Log;
      expect(saved.repetitions, 12);
      expect(saved.weight, 34);
      expect(saved.slotEntryId, gymState.getSlotEntryPageByIndex()!.setConfigData!.slotEntryId);
      expect(saved.routineId, gymState.routine.id);
      expect(saved.iteration, gymState.iteration);
      // The lazy session needs the day, otherwise days that need logs to
      // advance can't see it (issue wger#2460)
      expect(captured[1], gymState.dayId);
    });

    testWidgets('reps quick buttons increment and decrement the value', (tester) async {
      final routine = testdata.getTestRoutine();
      routine.dayDataGym[0].slots[0].setConfigs[0].repetitions = 0;
      seedLogPage(routine);
      await pumpLogPage(tester);

      final repsWidget = find.byKey(const ValueKey('logs-reps-widget'));
      expect(repsWidget, findsOneWidget);
      final addBtn = find.descendant(of: repsWidget, matching: find.byIcon(Icons.add));
      final removeBtn = find.descendant(of: repsWidget, matching: find.byIcon(Icons.remove));

      await tester.tap(addBtn);
      await tester.pumpAndSettle();
      expect(find.descendant(of: repsWidget, matching: find.text('1')), findsOneWidget);

      await tester.tap(addBtn);
      await tester.pumpAndSettle();
      expect(find.descendant(of: repsWidget, matching: find.text('2')), findsOneWidget);

      await tester.tap(removeBtn);
      await tester.pumpAndSettle();
      expect(find.descendant(of: repsWidget, matching: find.text('1')), findsOneWidget);
    });

    testWidgets('weight quick buttons increment and decrement the value', (tester) async {
      final routine = testdata.getTestRoutine();
      routine.dayDataGym[0].slots[0].setConfigs[0].weight = 0;
      seedLogPage(routine);
      await pumpLogPage(tester);

      final weightWidget = find.byKey(const ValueKey('logs-weight-widget'));
      expect(weightWidget, findsOneWidget);
      final addBtn = find.descendant(of: weightWidget, matching: find.byIcon(Icons.add));
      final removeBtn = find.descendant(of: weightWidget, matching: find.byIcon(Icons.remove));

      await tester.tap(addBtn);
      await tester.pumpAndSettle();
      expect(find.descendant(of: weightWidget, matching: find.text('1.25')), findsOneWidget);

      await tester.tap(addBtn);
      await tester.pumpAndSettle();
      expect(find.descendant(of: weightWidget, matching: find.text('2.5')), findsOneWidget);

      await tester.tap(removeBtn);
      await tester.pumpAndSettle();
      expect(find.descendant(of: weightWidget, matching: find.text('1.25')), findsOneWidget);
    });
  });
}
