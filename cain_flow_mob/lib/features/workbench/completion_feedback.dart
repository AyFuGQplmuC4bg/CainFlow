import 'package:flutter/services.dart';

/// Plays completion feedback when a workflow run finishes: a haptic buzz on
/// mobile plus a short system alert sound. Uses platform channels only
/// (`HapticFeedback`/`SystemSound`), so no plugin or asset is required and it
/// degrades to a no-op on platforms that lack the capability.
class CompletionFeedback {
  const CompletionFeedback();

  /// Success cue: a medium haptic pulse and the system alert sound.
  Future<void> success() async {
    try {
      await Future.wait([
        HapticFeedback.mediumImpact(),
        SystemSound.play(SystemSoundType.alert),
      ]);
    } catch (_) {
      // No haptics/sound channel on this platform; ignore.
    }
  }

  /// Failure cue: a heavier buzz; no sound to stay unobtrusive.
  Future<void> failure() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {
      // No haptics channel on this platform; ignore.
    }
  }
}
