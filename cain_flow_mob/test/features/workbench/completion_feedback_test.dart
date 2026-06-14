import 'package:cain_flow_mob/features/workbench/completion_feedback.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> hapticCalls;

  setUp(() {
    hapticCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        hapticCalls.add(call);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('success buzzes when haptics enabled', () async {
    final feedback = CompletionFeedback(
      soundEnabled: false,
      hapticsEnabled: true,
      soundPlayer: () async {},
    );
    await feedback.success();
    expect(hapticCalls, isNotEmpty);
  });

  test('success does not buzz when haptics disabled', () async {
    final feedback = CompletionFeedback(
      soundEnabled: false,
      hapticsEnabled: false,
      soundPlayer: () async {},
    );
    await feedback.success();
    expect(hapticCalls, isEmpty);
  });

  test('success plays sound when sound enabled', () async {
    var plays = 0;
    final feedback = CompletionFeedback(
      soundEnabled: true,
      hapticsEnabled: false,
      soundPlayer: () async => plays++,
    );
    await feedback.success();
    expect(plays, 1);
  });

  test('success skips sound when sound disabled', () async {
    var plays = 0;
    final feedback = CompletionFeedback(
      soundEnabled: false,
      hapticsEnabled: false,
      soundPlayer: () async => plays++,
    );
    await feedback.success();
    expect(plays, 0);
  });

  test('failure buzzes but never plays sound', () async {
    var plays = 0;
    final feedback = CompletionFeedback(
      soundEnabled: true,
      hapticsEnabled: true,
      soundPlayer: () async => plays++,
    );
    await feedback.failure();
    expect(hapticCalls, isNotEmpty);
    expect(plays, 0);
  });

  test('a throwing sound player is swallowed', () async {
    final feedback = CompletionFeedback(
      soundEnabled: true,
      hapticsEnabled: false,
      soundPlayer: () async => throw Exception('no audio backend'),
    );
    await expectLater(feedback.success(), completes);
  });
}
