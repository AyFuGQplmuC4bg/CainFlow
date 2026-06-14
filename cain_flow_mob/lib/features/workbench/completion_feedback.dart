import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Plays the completion sound asset. Injectable so tests can substitute a fake
/// without constructing a real [AudioPlayer] (whose constructor needs the
/// plugin). The default uses audioplayers with the bundled asset.
typedef CompletionSoundPlayer = Future<void> Function();

Future<void> _defaultSoundPlayer() async {
  // AssetSource is rooted at the `assets/` directory by the plugin.
  await AudioPlayer().play(AssetSource('sounds/completion.mp3'));
}

/// Plays completion feedback when a workflow run finishes: an optional haptic
/// buzz on mobile and an optional notification sound (bundled asset). Both cues
/// are independently toggleable; either failing degrades to a no-op so it is
/// safe on platforms lacking haptics or audio.
class CompletionFeedback {
  CompletionFeedback({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    CompletionSoundPlayer? soundPlayer,
  }) : _soundPlayer = soundPlayer ?? _defaultSoundPlayer;

  /// Whether to play the notification sound on completion.
  final bool soundEnabled;

  /// Whether to vibrate on completion (mobile only).
  final bool hapticsEnabled;

  final CompletionSoundPlayer _soundPlayer;

  /// Success cue: a medium haptic pulse plus the notification sound, each
  /// gated by its toggle.
  Future<void> success() async {
    await Future.wait([
      if (hapticsEnabled) _buzz(HapticFeedback.mediumImpact),
      if (soundEnabled) _playSound(),
    ]);
  }

  /// Failure cue: a heavier buzz only (no sound, to stay unobtrusive).
  Future<void> failure() async {
    if (!hapticsEnabled) return;
    await _buzz(HapticFeedback.heavyImpact);
  }

  Future<void> _buzz(Future<void> Function() impact) async {
    try {
      await impact();
    } catch (_) {
      // No haptics channel on this platform; ignore.
    }
  }

  Future<void> _playSound() async {
    try {
      await _soundPlayer();
    } catch (_) {
      // No audio backend on this platform; ignore.
    }
  }
}
