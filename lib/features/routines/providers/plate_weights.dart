import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wger/core/consts.dart';
import 'package:wger/core/shared_preferences.dart';
import 'package:wger/features/routines/gym_mode.dart';

const DEFAULT_KG_PLATES = [2.5, 5, 10, 15, 20, 25];
const DEFAULT_LB_PLATES = [2.5, 5, 10, 25, 35, 45];

const DEFAULT_BAR_WEIGHT_KG = 20;
const DEFAULT_BAR_WEIGHT_LB = 45;

const PREFS_KEY_PLATES = 'selectedPlates';

final plateCalculatorProvider = NotifierProvider<PlateCalculatorNotifier, PlateCalculatorState>(
  PlateCalculatorNotifier.new,
);

class PlateCalculatorState {
  // https://en.wikipedia.org/wiki/Barbell#Bumper_plates
  final Map<double, Color> plateColorMapKg = {
    25: Colors.red,
    20: Colors.blue,
    15: Colors.yellow,
    10: Colors.green,
    5: Colors.white,
    2.5: Colors.red,
    2: Colors.blue,
    1.25: Colors.yellow,
    1: Colors.green,
    0.5: Colors.white,
  };
  final Map<double, Color> plateColorMapLb = {
    55: Colors.red,
    45: Colors.blue,
    35: Colors.yellow,
    25: Colors.green,
    10: Colors.white,
    5: Colors.blue,
    2.5: Colors.green,
    1.25: Colors.white,
  };

  final bool useColors;
  final bool isMetric;
  final num totalWeight;
  final num barWeight;
  final List<num> selectedPlates;

  /// Exercises done on a plate-loaded machine without a bar: their whole
  /// weight is split over both sides.
  final Set<int> barlessExercises;
  final List<num> availablePlatesKg = const [0.5, 1, 1.25, 2, 2.5, 5, 10, 15, 20, 25];
  final List<num> availablePlatesLb = const [2.5, 5, 10, 25, 35, 45];

  final availableBarWeightsKg = [10, 15, 20];
  final availableBarWeightsLb = [15, 20, 25, 33, 45];

  PlateCalculatorState({
    this.useColors = true,
    num? barWeight,
    this.isMetric = true,
    this.totalWeight = 0,
    List<num>? selectedPlates,
    Set<int>? barlessExercises,
  }) : barWeight = barWeight ?? (isMetric ? DEFAULT_BAR_WEIGHT_KG : DEFAULT_BAR_WEIGHT_LB),
       selectedPlates =
           selectedPlates ?? (isMetric ? [...DEFAULT_KG_PLATES] : [...DEFAULT_LB_PLATES]),
       barlessExercises = barlessExercises ?? const {};

  PlateCalculatorState.fromJson(Map<String, dynamic> plateData)
    : useColors = plateData['useColors'] ?? true,
      isMetric = plateData['isMetric'] ?? true,
      selectedPlates = plateData['selectedPlates']?.cast<num>() ?? [...DEFAULT_KG_PLATES],
      barWeight =
          plateData['barWeight'] ??
          ((plateData['isMetric'] ?? true) ? DEFAULT_BAR_WEIGHT_KG : DEFAULT_BAR_WEIGHT_LB),
      barlessExercises = {...?(plateData['barlessExercises'] as List?)?.cast<int>()},
      totalWeight = 0;

  PlateCalculatorState copyWith({
    bool? useColors,
    bool? isMetric,
    num? totalWeight,
    num? barWeight,
    List<num>? selectedPlates,
    Set<int>? barlessExercises,
  }) {
    return PlateCalculatorState(
      useColors: useColors ?? this.useColors,
      isMetric: isMetric ?? this.isMetric,
      totalWeight: totalWeight ?? this.totalWeight,
      barWeight: barWeight ?? this.barWeight,
      selectedPlates: selectedPlates ?? this.selectedPlates,
      barlessExercises: barlessExercises ?? this.barlessExercises,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'useColors': useColors,
      'isMetric': isMetric,
      'selectedPlates': selectedPlates,
      'barWeight': barWeight,
      'barlessExercises': barlessExercises.toList(),
    };
  }

  /// The bar weight to subtract for [exerciseId]: none on a barless machine
  num barWeightFor(int? exerciseId) =>
      exerciseId != null && barlessExercises.contains(exerciseId) ? 0 : barWeight;

  List<num> get availablePlates {
    return isMetric ? availablePlatesKg : availablePlatesLb;
  }

  List<num> get availableBarsWeights {
    return isMetric ? availableBarWeightsKg : availableBarWeightsLb;
  }

  List<num> get platesList {
    return plateCalculator(totalWeight, barWeight, selectedPlates);
  }

  bool get hasPlates {
    return platesList.isNotEmpty;
  }

  Map<num, int> get calculatePlates {
    return groupPlates(plateCalculator(totalWeight, barWeight, selectedPlates));
  }

  Color getColor(num plate) {
    if (!useColors) {
      return Colors.grey;
    }

    if (isMetric) {
      return plateColorMapKg[plate.toDouble()] ?? Colors.grey;
    }
    return plateColorMapLb[plate.toDouble()] ?? Colors.grey;
  }
}

class PlateCalculatorNotifier extends Notifier<PlateCalculatorState> {
  final _logger = Logger('PlateCalculatorNotifier');

  late SharedPreferencesAsync _prefs;

  PlateCalculatorNotifier({SharedPreferencesAsync? prefs}) : super() {
    _prefs = prefs ?? PreferenceHelper.asyncPref;
  }

  @override
  PlateCalculatorState build() {
    _readDataFromSharedPrefs();
    return PlateCalculatorState();
  }

  Future<void> saveToSharedPrefs() async {
    _logger.fine('Saving plate data to SharedPreferences');
    await _prefs.setString(PREFS_KEY_PLATES, jsonEncode(state.toJson()));
  }

  Future<void> _readDataFromSharedPrefs() async {
    _logger.fine('Reading plate data from SharedPreferences');
    final prefsData = await _prefs.getString(PREFS_KEY_PLATES);

    if (prefsData != null) {
      try {
        state = PlateCalculatorState.fromJson(json.decode(prefsData));
        _logger.fine('Plate data loaded from SharedPreferences: ${state.toJson()}');
      } catch (e) {
        _logger.fine('Error decoding plate data from SharedPreferences: $e');
        state = PlateCalculatorState();
      }
    }
  }

  Future<void> toggleSelection(num x) async {
    final newSelectedPlates = List.of(state.selectedPlates);
    if (newSelectedPlates.contains(x)) {
      newSelectedPlates.remove(x);
    } else {
      newSelectedPlates.add(x);
    }
    state = state.copyWith(selectedPlates: newSelectedPlates);
    await saveToSharedPrefs();
  }

  void setBarWeight(num x) {
    _logger.fine('Setting bar weight to $x');
    state = state.copyWith(barWeight: x);
    unawaited(saveToSharedPrefs());
  }

  void setBarless(int exerciseId, bool barless) {
    final updated = {...state.barlessExercises};
    if (barless) {
      updated.add(exerciseId);
    } else {
      updated.remove(exerciseId);
    }
    state = state.copyWith(barlessExercises: updated);
    unawaited(saveToSharedPrefs());
  }

  void setUseColors(bool value) {
    state = state.copyWith(useColors: value);
    unawaited(saveToSharedPrefs());
  }

  void unitChange({WeightUnitEnum? unit}) {
    final WeightUnitEnum changeTo =
        unit ?? (state.isMetric ? WeightUnitEnum.lb : WeightUnitEnum.kg);

    if (changeTo == WeightUnitEnum.kg && !state.isMetric) {
      state = state.copyWith(
        isMetric: true,
        totalWeight: 0,
        barWeight: DEFAULT_BAR_WEIGHT_KG,
        selectedPlates: [...DEFAULT_KG_PLATES],
      );
    }

    if (changeTo == WeightUnitEnum.lb && state.isMetric) {
      state = state.copyWith(
        isMetric: false,
        totalWeight: 0,
        barWeight: DEFAULT_BAR_WEIGHT_LB,
        selectedPlates: [...DEFAULT_LB_PLATES],
      );
    }
    unawaited(saveToSharedPrefs());
  }

  void setWeight(num x) {
    _logger.fine('Setting weight to $x');
    state = state.copyWith(totalWeight: x);
  }
}
