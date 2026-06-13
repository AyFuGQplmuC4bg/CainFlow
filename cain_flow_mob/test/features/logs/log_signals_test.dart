import 'package:cain_flow_mob/features/logs/log_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('log signals keep newest entries within capacity', () {
    final logs = LogSignals(capacity: 2);

    logs.add(LogLevel.info, 'one');
    logs.add(LogLevel.warning, 'two');
    logs.add(LogLevel.error, 'three');

    expect(logs.entries.value.map((entry) => entry.message), ['three', 'two']);
    expect(logs.hasErrors.value, isTrue);

    logs.clear();
    expect(logs.entries.value, isEmpty);
  });
}
