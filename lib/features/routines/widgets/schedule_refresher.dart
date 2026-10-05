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

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wger/core/network/network_provider.dart';
import 'package:wger/features/routines/providers/routines_notifier.dart';

/// Re-checks log-driven routine schedules when the app returns from the
/// background or the server becomes reachable again.
///
/// Such schedules shift with sessions and calendar days, and a check skipped
/// while offline would otherwise wait for the next trigger. Mount it where it
/// lives as long as the app: it wraps the home screen, which stays mounted
/// under pushed routes.
class RoutineScheduleRefresher extends ConsumerStatefulWidget {
  const RoutineScheduleRefresher({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RoutineScheduleRefresher> createState() => _RoutineScheduleRefresherState();
}

class _RoutineScheduleRefresherState extends ConsumerState<RoutineScheduleRefresher> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _refresh);
    ref.listenManual(networkStatusProvider, (previous, next) {
      if (next && previous == false) {
        _refresh();
      }
    });
  }

  void _refresh() => ref.read(routinesRiverpodProvider.notifier).refreshStaleSchedules();

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
