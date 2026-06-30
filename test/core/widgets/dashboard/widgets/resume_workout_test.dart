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
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wger/core/shared_preferences.dart';
import 'package:wger/core/widgets/dashboard/widgets/resume_workout.dart';
import 'package:wger/features/routines/models/active_workout.dart';
import 'package:wger/features/routines/providers/active_workout_notifier.dart';
import 'package:wger/features/routines/screens/gym_mode.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    // PreferenceHelper.asyncPref binds its backing store once; clear that exact
    // instance to avoid cross-test bleed of the singleton pointer.
    await PreferenceHelper.asyncPref.clear();
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  // Captured route arguments so navigation can be asserted without building the
  // real (provider-heavy) gym-mode screen.
  Object? capturedArgs;

  Widget render() {
    capturedArgs = null;
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        onGenerateRoute: (settings) {
          if (settings.name == GymModeScreen.routeName) {
            capturedArgs = settings.arguments;
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('gym-mode-sentinel')),
            );
          }
          return MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: ResumeWorkoutCard()),
          );
        },
      ),
    );
  }

  ActiveWorkout pointer({DateTime? validUntil, int currentPage = 4}) => ActiveWorkout(
    routineId: 7,
    dayId: 3,
    iteration: 2,
    startedAt: clock.now(),
    currentPage: currentPage,
    validUntil: validUntil ?? clock.now().add(const Duration(hours: 2)),
  );

  testWidgets('renders the resume affordance when an unexpired pointer exists', (tester) async {
    await container.read(activeWorkoutProvider.notifier).start(pointer());

    await tester.pumpWidget(render());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('resume-workout-card')), findsOneWidget);
    expect(
      find.text(AppLocalizations.of(tester.element(find.byType(Scaffold))).resumeWorkout),
      findsOneWidget,
    );
  });

  testWidgets('renders nothing when there is no pointer', (tester) async {
    await tester.pumpWidget(render());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('resume-workout-card')), findsNothing);
  });

  testWidgets('hides the affordance when the pointer is expired', (tester) async {
    await container.read(activeWorkoutProvider.notifier).start(pointer(validUntil: DateTime(2000)));

    await tester.pumpWidget(render());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('resume-workout-card')), findsNothing);
  });

  testWidgets('navigates to gym mode with the pointer arguments on tap', (tester) async {
    await container.read(activeWorkoutProvider.notifier).start(pointer());

    await tester.pumpWidget(render());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('resume-workout-card')));
    await tester.pumpAndSettle();

    expect(capturedArgs, isA<GymModeArguments>());
    final args = capturedArgs! as GymModeArguments;
    expect(args.routineId, 7);
    expect(args.dayId, 3);
    expect(args.iteration, 2);
  });
}
