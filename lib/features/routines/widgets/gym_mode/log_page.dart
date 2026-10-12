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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:wger/core/consts.dart';
import 'package:wger/core/formatting/formatting.dart';
import 'package:wger/core/snackbar.dart';
import 'package:wger/core/widgets/core.dart';
import 'package:wger/core/widgets/error.dart';
import 'package:wger/features/exercises/models/exercise.dart';
import 'package:wger/features/routines/gym_mode.dart';
import 'package:wger/features/routines/models/log.dart';
import 'package:wger/features/routines/models/set_config_data.dart';
import 'package:wger/features/routines/models/slot_entry.dart';
import 'package:wger/features/routines/providers/gym_log_notifier.dart';
import 'package:wger/features/routines/providers/gym_state.dart';
import 'package:wger/features/routines/providers/gym_state_notifier.dart';
import 'package:wger/features/routines/providers/plate_weights.dart';
import 'package:wger/features/routines/providers/workout_logs_notifier.dart';
import 'package:wger/features/routines/screens/settings_plates_screen.dart';
import 'package:wger/features/routines/validators.dart';
import 'package:wger/features/routines/widgets/forms/repetitions.dart';
import 'package:wger/features/routines/widgets/forms/rir.dart';
import 'package:wger/features/routines/widgets/forms/weight.dart';
import 'package:wger/features/routines/widgets/gym_mode/navigation.dart';
import 'package:wger/features/routines/widgets/logs/log_delete_dialog.dart';
import 'package:wger/features/routines/widgets/logs/log_edit_dialog.dart';
import 'package:wger/features/routines/widgets/plate_calculator.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

class LogPage extends ConsumerWidget {
  final _logger = Logger('LogPage');

  final PageController _controller;

  /// Identifies which slot page this widget renders, so it shows its own
  /// content instead of whatever the globally-current page happens to be.
  final String slotUuid;

  LogPage(this._controller, this.slotUuid);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gymState = ref.watch(gymStateProvider);
    final languageCode = Localizations.localeOf(context).languageCode;

    final slotEntryPage = gymState.getSlotPageByUUID(slotUuid);
    if (slotEntryPage == null) {
      _logger.info('getSlotPageByUUID for $slotUuid returned null, showing empty container.');
      return Container();
    }

    final page = gymState.getPageByIndex(slotEntryPage.pageIndex);
    if (page == null) {
      _logger.info(
        'getPageByIndex for ${slotEntryPage.pageIndex} returned null, showing empty container.',
      );
      return Container();
    }
    final setConfigData = slotEntryPage.setConfigData!;

    // Past logs come straight from the local DB (not the gym-mode routine
    // snapshot) so a set logged during this workout shows up right away.
    final pastLogs = ref.watch(
      pastExerciseLogsProvider(
        routineId: gymState.routine.id!,
        exerciseId: setConfigData.exerciseId,
        weeksBack: gymState.logScopeWeeks,
        // Collapsed below, once this workout's sets are taken out: collapsing
        // first would fold older identical sets into today's and drop them
        distinct: false,
      ),
    );
    // Every set of this workout, never collapsed, so a mistake (or a set saved
    // twice) can be found and fixed without leaving gym mode
    final workoutStart = gymState.workoutStart;
    final currentLogs = [
      ...?ref
          .watch(
            pastExerciseLogsProvider(
              routineId: gymState.routine.id!,
              exerciseId: setConfigData.exerciseId,
              distinct: false,
            ),
          )
          .value
          ?.where((log) => !log.date.isBefore(workoutStart)),
    ].reversed.toList();

    // Mark done sets
    final decorationStyle = slotEntryPage.logDone
        ? TextDecoration.lineThrough
        : TextDecoration.none;

    return Column(
      children: [
        NavigationHeader(
          setConfigData.exercise.getTranslation(languageCode).name,
          _controller,
        ),

        Container(
          color: theme.colorScheme.onInverseSurface,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Column(
              children: [
                Column(
                  children: [
                    Text(
                      setConfigData.textRepr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: decorationStyle,
                      ),
                    ),
                    if (setConfigData.type != SlotEntryType.normal)
                      Text(
                        setConfigData.type.name.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: decorationStyle,
                        ),
                      ),
                  ],
                ),
                Text(
                  '${slotEntryPage.setIndex + 1} / ${page.slotPages.where((e) => e.type == SlotPageType.log).length}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        if (setConfigData.exercise.showPlateCalculator)
          LogsPlatesWidget(exercise: setConfigData.exercise),
        if (slotEntryPage.setConfigData!.comment.isNotEmpty)
          Text(slotEntryPage.setConfigData!.comment, textAlign: TextAlign.center),
        const SizedBox(height: 10),

        // Overriding the log scope from here is handled in a follow-up, the
        // settings currently only live in the gym mode options.
        // _LogScopeControls(gymState: gymState),
        Expanded(
          child: _buildPastLogs(
            pastLogs,
            currentLogs,
            setConfigData.exercise,
            distinct: gymState.showDistinctLogs,
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(10),
          child: Card(
            color: Theme.of(context).colorScheme.inversePrimary,
            // color: Theme.of(context).secondaryHeaderColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: LogFormWidget(
                controller: _controller,
                configData: setConfigData,
                key: ValueKey('log-form-${slotEntryPage.uuid}'),
              ),
            ),
          ),
        ),
        NavigationFooter(_controller),
      ],
    );
  }

  /// Renders this workout's and the previous logs for this exercise
  Widget _buildPastLogs(
    AsyncValue<List<Log>> pastLogs,
    List<Log> currentLogs,
    Exercise exercise, {
    required bool distinct,
  }) {
    if (pastLogs.hasError) {
      _logger.warning('Could not load past logs', pastLogs.error, pastLogs.stackTrace);
      // Scroll-wrap so the indicator fits this slim slot instead of overflowing.
      return SingleChildScrollView(
        child: StreamErrorIndicator(pastLogs.error!, stacktrace: pastLogs.stackTrace),
      );
    }
    final currentIds = {for (final log in currentLogs) log.id};
    final older = [...?pastLogs.value?.where((log) => !currentIds.contains(log.id))];
    final logs = distinct ? deduplicateLogs(older) : older;
    return logs.isEmpty && currentLogs.isEmpty
        ? const SizedBox.shrink()
        : LogsPastLogsWidget(pastLogs: logs, currentLogs: currentLogs, exercise: exercise);
  }
}

class LogsPlatesWidget extends ConsumerWidget {
  const LogsPlatesWidget({required this.exercise, super.key});

  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plateWeightsState = ref.watch(plateCalculatorProvider);
    // The calculator's own total only follows edits of the weight field, so it
    // lags behind page changes; the set on screen is the source of truth
    final weight = ref.watch(gymLogProvider.select((log) => log?.weight)) ?? 0;
    final plates = groupPlates(
      plateCalculator(
        weight,
        plateWeightsState.barWeightFor(exercise.id),
        plateWeightsState.selectedPlates,
      ),
    );

    return Container(
      color: Theme.of(context).colorScheme.onInverseSurface,
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushNamed(ConfigurePlatesScreen.routeName, arguments: exercise);
            },
            child: SizedBox(
              child: plates.isNotEmpty
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ...plates.entries.map(
                          (entry) => Row(
                            children: [
                              Text(entry.value.toString()),
                              const Text('×'),
                              PlateWeight(
                                value: entry.key,
                                size: 37,
                                padding: 2,
                                margin: 0,
                                color: ref.read(plateCalculatorProvider).getColor(entry.key),
                              ),
                              const SizedBox(width: 10),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: MutedText(
                        AppLocalizations.of(context).plateCalculatorNotDivisible,
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 3),
        ],
      ),
    );
  }
}

class LogsPastLogsWidget extends ConsumerWidget {
  final List<Log> pastLogs;

  /// This workout's logs, oldest first; each can be edited or deleted
  final List<Log> currentLogs;

  /// The exercise the logs belong to, they only carry its ID
  final Exercise exercise;

  const LogsPastLogsWidget({
    super.key,
    required this.pastLogs,
    this.currentLogs = const [],
    required this.exercise,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logProvider = ref.read(gymLogProvider.notifier);
    final dateFormat = localizedDate(context);
    final i18n = AppLocalizations.of(context);

    void copy(Log log) {
      logProvider.setLog(log, exercise: exercise);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      showSnackbar(context, i18n.dataCopied);
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        children: [
          if (currentLogs.isNotEmpty) ...[
            Text(
              i18n.todaysWorkout,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            ...currentLogs.map(
              (log) => ListTile(
                key: ValueKey('current-log-${log.id}'),
                title: Text(log.repTextNoNl(context)),
                trailing: _CurrentLogMenu(log: log, exercise: exercise, onCopy: () => copy(log)),
                onTap: () => copy(log),
                contentPadding: const EdgeInsets.only(left: 40, right: 16),
              ),
            ),
          ],
          if (pastLogs.isNotEmpty)
            Text(
              i18n.labelWorkoutLogs,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ...pastLogs.map((pastLog) {
            return ListTile(
              key: ValueKey('past-log-${pastLog.id}'),
              title: Text(pastLog.repTextNoNl(context)),
              subtitle: Text(dateFormat.format(pastLog.date)),
              trailing: const Icon(Icons.copy),
              onTap: () => copy(pastLog),
              contentPadding: const EdgeInsets.symmetric(horizontal: 40),
            );
          }),
        ],
      ),
    );
  }
}

enum _CurrentLogAction { edit, delete, copy }

/// Edit, delete and copy for one of this workout's logs
class _CurrentLogMenu extends ConsumerWidget {
  const _CurrentLogMenu({required this.log, required this.exercise, required this.onCopy});

  final Log log;
  final Exercise exercise;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = AppLocalizations.of(context);

    return PopupMenuButton<_CurrentLogAction>(
      key: ValueKey('current-log-menu-${log.id}'),
      onSelected: (action) {
        switch (action) {
          case _CurrentLogAction.edit:
            showLogEditDialog(context, log);
          case _CurrentLogAction.delete:
            // Read before the dialog: this row is gone once the log is deleted
            final gym = ref.read(gymStateProvider.notifier);
            showDeleteLogDialog(
              context,
              exercise.getTranslation(Localizations.localeOf(context).languageCode).name,
              log,
              onDeleted: () =>
                  gym.logDeleted(slotEntryId: log.slotEntryId, exerciseId: log.exerciseId),
            );
          case _CurrentLogAction.copy:
            onCopy();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: _CurrentLogAction.edit, child: Text(i18n.edit)),
        PopupMenuItem(value: _CurrentLogAction.delete, child: Text(i18n.delete)),
        PopupMenuItem(value: _CurrentLogAction.copy, child: Text(i18n.copy)),
      ],
    );
  }
}

class LogFormWidget extends ConsumerStatefulWidget {
  final PageController controller;
  final SetConfigData configData;

  const LogFormWidget({
    super.key,
    required this.controller,
    required this.configData,
  });

  @override
  _LogFormWidgetState createState() => _LogFormWidgetState();
}

class _LogFormWidgetState extends ConsumerState<LogFormWidget> {
  final _form = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final logProvider = ref.read(workoutLogProvider);
    final log = ref.watch(gymLogProvider);

    // The log is populated when the page becomes current: the PageView can lay
    // out and mount this page before that happens, so guard against null.
    if (log == null) {
      return const SizedBox.shrink();
    }

    return Form(
      key: _form,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            i18n.newEntry,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          Row(
            children: [
              Flexible(
                child: RepetitionInputWidget(
                  key: const ValueKey('logs-reps-widget'),
                  value: log.repetitions,
                  valueChange: widget.configData.repetitionsRounding,
                  unit: log.repetitionsUnitObj,
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(gymLogProvider.notifier).setRepetitions(v);
                    }
                  },
                  onUnitChanged: (v) {
                    if (v != null) {
                      ref.read(gymLogProvider.notifier).setRepetitionUnit(v);
                    }
                  },
                ),
              ),
              Flexible(
                child: WeightInputWidget(
                  key: const ValueKey('logs-weight-widget'),
                  value: log.weight,
                  valueChange: widget.configData.weightRounding,
                  unit: log.weightUnitObj,
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(gymLogProvider.notifier).setWeight(v);
                      ref.read(plateCalculatorProvider.notifier).setWeight(v);
                    }
                  },
                  onUnitChanged: (v) {
                    if (v != null) {
                      ref.read(gymLogProvider.notifier).setWeightUnit(v);
                    }
                  },
                ),
              ),
            ],
          ),
          RiRInputWidget(
            key: const ValueKey('rir-input-widget'),
            log.rir,
            onChanged: (value) {
              log.rir = value == '' ? null : num.parse(value);
            },
          ),
          FilledButton(
            key: const ValueKey('save-log-button'),
            onPressed: () async {
              final isValid = _form.currentState!.validate();
              if (!isValid) {
                return;
              }
              _form.currentState!.save();

              final error = validateWorkoutLogCrossField(
                repetitions: log.repetitions,
                weight: log.weight,
                i18n: i18n,
              );
              if (error != null) {
                showSnackbar(context, error);
                return;
              }

              final gymState = ref.read(gymStateProvider);
              final gymProvider = ref.read(gymStateProvider.notifier);
              final page = gymState.getSlotEntryPageByIndex()!;

              // A failed write is intentionally left to propagate to the global
              // error handler; the success path below is then skipped.
              await logProvider.addEntry(log, dayId: gymState.dayId);
              if (!context.mounted) {
                return;
              }

              gymProvider.markSlotPageAsDone(page.uuid, isDone: true);
              showSnackbar(
                context,
                i18n.successfullySaved,
                center: true,
                duration: const Duration(seconds: 2),
              );
              widget.controller.nextPage(
                duration: DEFAULT_ANIMATION_DURATION,
                curve: DEFAULT_ANIMATION_CURVE,
              );
            },
            child: Text(i18n.save),
          ),
        ],
      ),
    );
  }
}

// Compact inline controls for overriding the global log-scope settings. Kept
// around for the follow-up that lets the scope be changed from the log page.
//
// class _LogScopeControls extends ConsumerWidget {
//   final GymModeState gymState;
//
//   const _LogScopeControls({required this.gymState});
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final gymNotifier = ref.read(gymStateProvider.notifier);
//     final i18n = AppLocalizations.of(context);
//     final theme = Theme.of(context);
//
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Row(
//             children: [
//               Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
//               const SizedBox(width: 4),
//               DropdownButton<int?>(
//                 value: gymState.logScopeWeeks,
//                 isDense: true,
//                 underline: const SizedBox.shrink(),
//                 style: theme.textTheme.bodySmall,
//                 onChanged: (value) => gymNotifier.setLogScopeWeeks(value),
//                 items: [
//                   DropdownMenuItem<int?>(
//                     value: null,
//                     child: Text(i18n.gymModeLogScopeCurrentRoutine),
//                   ),
//                   ...[8, 12, 25, 50].map(
//                     (w) => DropdownMenuItem<int?>(
//                       value: w,
//                       child: Text(i18n.gymModeLogScopeWeeks(w)),
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//           Row(
//             children: [
//               Text(i18n.gymModeDistinctLogs, style: theme.textTheme.bodySmall),
//               Switch.adaptive(
//                 value: gymState.showDistinctLogs,
//                 onChanged: (v) => gymNotifier.setShowDistinctLogs(v),
//                 materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }
