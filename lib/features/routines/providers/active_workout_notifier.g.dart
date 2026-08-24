// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_workout_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Persists a small singleton pointer to the workout currently in progress.
///
/// v1 supports exactly one active workout at a time. The pointer is stored as a
/// single JSON blob in `shared_preferences`; it is device-local and not synced.

@ProviderFor(ActiveWorkoutNotifier)
final activeWorkoutProvider = ActiveWorkoutNotifierProvider._();

/// Persists a small singleton pointer to the workout currently in progress.
///
/// v1 supports exactly one active workout at a time. The pointer is stored as a
/// single JSON blob in `shared_preferences`; it is device-local and not synced.
final class ActiveWorkoutNotifierProvider
    extends $AsyncNotifierProvider<ActiveWorkoutNotifier, ActiveWorkout?> {
  /// Persists a small singleton pointer to the workout currently in progress.
  ///
  /// v1 supports exactly one active workout at a time. The pointer is stored as a
  /// single JSON blob in `shared_preferences`; it is device-local and not synced.
  ActiveWorkoutNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeWorkoutProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeWorkoutNotifierHash();

  @$internal
  @override
  ActiveWorkoutNotifier create() => ActiveWorkoutNotifier();
}

String _$activeWorkoutNotifierHash() => r'159dcb098e2b8e0a670ddcf33008a6b08fea3c75';

/// Persists a small singleton pointer to the workout currently in progress.
///
/// v1 supports exactly one active workout at a time. The pointer is stored as a
/// single JSON blob in `shared_preferences`; it is device-local and not synced.

abstract class _$ActiveWorkoutNotifier extends $AsyncNotifier<ActiveWorkout?> {
  FutureOr<ActiveWorkout?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ActiveWorkout?>, ActiveWorkout?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ActiveWorkout?>, ActiveWorkout?>,
              AsyncValue<ActiveWorkout?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
