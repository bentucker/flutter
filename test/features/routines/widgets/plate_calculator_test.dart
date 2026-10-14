import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wger/features/account/models/user_profile.dart';
import 'package:wger/features/account/providers/user_profile_notifier.dart';
import 'package:wger/features/exercises/models/exercise.dart';
import 'package:wger/features/routines/providers/plate_weights.dart';
import 'package:wger/features/routines/widgets/plate_calculator.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

import '../../../../test_data/exercises.dart';

Future<void> pumpWidget(
  WidgetTester tester, {
  required ProviderContainer container,
  Exercise? exercise,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ConfigureAvailablePlates(exercise: exercise)),
      ),
    ),
  );
}

void main() {
  late ProviderContainer container;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    container = ProviderContainer(
      overrides: [
        plateCalculatorProvider.overrideWith(() => PlateCalculatorNotifier()),
        // The notifier reads the profile's unit when nothing is saved
        userProfileProvider.overrideWith(() => _NoProfile()),
      ],
    );
  });

  testWidgets('opened from an exercise, the no-bar switch marks it barless', (tester) async {
    await pumpWidget(tester, container: container, exercise: testBenchPress);

    expect(find.byKey(const ValueKey('barlessSwitch')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('barlessSwitch')));
    await tester.pump();

    final state = container.read(plateCalculatorProvider);
    expect(state.barlessExercises, {testBenchPress.id});
    expect(state.barWeightFor(testBenchPress.id), 0);
    expect(state.barWeightFor(testBenchPress.id + 1), state.barWeight);
  });

  testWidgets('without an exercise there is no per-exercise switch', (tester) async {
    await pumpWidget(tester, container: container);

    expect(find.byKey(const ValueKey('barlessSwitch')), findsNothing);
  });

  testWidgets('Smoke test for ConfigureAvailablePlates', (WidgetTester tester) async {
    await pumpWidget(tester, container: container);

    expect(find.text('Unit'), findsWidgets);
    expect(find.text('Bar weight'), findsWidgets);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(PlateWeight), findsWidgets);
  });

  testWidgets(
    'ConfigureAvailablePlates correctly updates state',
    (WidgetTester tester) async {
      // Arrange
      await pumpWidget(tester, container: container);
      final notifier = container.read(plateCalculatorProvider.notifier);
      notifier.state = PlateCalculatorState(
        isMetric: true,
        barWeight: 20,
        useColors: false,
        selectedPlates: [1.25, 2.5],
      );

      // Correctly changes the unit
      expect(notifier.state.isMetric, isTrue);
      await tester.tap(find.byKey(const ValueKey('weightUnitDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('lb').last);
      await tester.pumpAndSettle();
      expect(notifier.state.isMetric, isFalse);

      // Correctly changes the bar weight
      expect(notifier.state.barWeight, 45);
      await tester.tap(find.byKey(const ValueKey('barWeightDropdown')));
      await tester.pumpAndSettle();
      final menuItem = find.ancestor(
        of: find.text('25'),
        matching: find.byType(InkWell),
      );
      expect(menuItem, findsOneWidget);
      await tester.tap(menuItem);
      await tester.pumpAndSettle();
      expect(notifier.state.barWeight, 25);

      // Correctly toggles the useColors switch
      expect(notifier.state.useColors, isFalse);
      await tester.tap(find.byKey(const ValueKey('useColorsSwitch')));
      await tester.pump();
      expect(notifier.state.useColors, isTrue);

      // Correctly adds and removes plates
      expect(notifier.state.selectedPlates.contains(5.0), isTrue);
      await tester.tap(find.byKey(const ValueKey('plateWeight-5')));
      await tester.pump();
      expect(notifier.state.selectedPlates.contains(5.0), isFalse);
    },
  );
}

class _NoProfile extends UserProfileNotifier {
  @override
  Stream<UserProfile?> build() => Stream.value(null);
}
