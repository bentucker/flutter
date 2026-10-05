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
import 'package:flutter_test/flutter_test.dart';
import 'package:wger/core/network/network_provider.dart';
import 'package:wger/features/routines/providers/routines_notifier.dart';
import 'package:wger/features/routines/widgets/schedule_refresher.dart';

class _FakeRoutines extends RoutinesRiverpod {
  int refreshes = 0;

  @override
  Stream<RoutinesState> build() => Stream.value(const RoutinesState());

  @override
  void refreshStaleSchedules() => refreshes++;
}

class _FakeNetworkStatus extends NetworkStatus {
  _FakeNetworkStatus(this._initial);

  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}

void main() {
  late _FakeRoutines routines;

  Future<_FakeNetworkStatus> pump(WidgetTester tester, {required bool online}) async {
    routines = _FakeRoutines();
    final network = _FakeNetworkStatus(online);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routinesRiverpodProvider.overrideWith(() => routines),
          networkStatusProvider.overrideWith(() => network),
        ],
        child: const RoutineScheduleRefresher(child: SizedBox()),
      ),
    );
    return network;
  }

  testWidgets('returning from the background re-checks schedules', (tester) async {
    await pump(tester, online: true);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(routines.refreshes, 1);
  });

  testWidgets('coming back online re-checks schedules', (tester) async {
    final network = await pump(tester, online: false);

    network.set(true);
    await tester.pump();
    expect(routines.refreshes, 1);

    network.set(false);
    await tester.pump();
    expect(routines.refreshes, 1, reason: 'going offline must not trigger a check');
  });
}
