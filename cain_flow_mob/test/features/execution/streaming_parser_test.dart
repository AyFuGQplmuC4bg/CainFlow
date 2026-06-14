import 'package:cain_flow_mob/features/execution/streaming_parser.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpenAI SSE', () {
    test('extracts content delta from a data line', () {
      final delta = StreamingParser.deltaFromLine(
        'data: {"choices":[{"delta":{"content":"Hel"}}]}',
        ModelProtocol.openai,
      );
      expect(delta, 'Hel');
    });

    test('ignores [DONE] and role-only deltas', () {
      expect(
        StreamingParser.deltaFromLine('data: [DONE]', ModelProtocol.openai),
        isNull,
      );
      expect(
        StreamingParser.deltaFromLine(
          'data: {"choices":[{"delta":{"role":"assistant"}}]}',
          ModelProtocol.openai,
        ),
        isNull,
      );
    });

    test('accumulates a multi-chunk stream into the full message', () {
      const raw = 'data: {"choices":[{"delta":{"content":"Hello"}}]}\n'
          'data: {"choices":[{"delta":{"content":", world"}}]}\n'
          'data: [DONE]\n';
      expect(
        StreamingParser.accumulate(raw, ModelProtocol.openai),
        'Hello, world',
      );
    });
  });

  group('Gemini SSE', () {
    test('accumulates candidate part text', () {
      const raw = 'data: {"candidates":[{"content":{"parts":[{"text":"A"}]}}]}\n'
          'data: {"candidates":[{"content":{"parts":[{"text":"B"}]}}]}\n';
      expect(StreamingParser.accumulate(raw, ModelProtocol.google), 'AB');
    });
  });

  test('malformed json lines are skipped', () {
    expect(
      StreamingParser.deltaFromLine('data: {not json', ModelProtocol.openai),
      isNull,
    );
  });
}
