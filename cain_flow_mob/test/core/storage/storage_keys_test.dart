import 'package:cain_flow_mob/core/storage/storage_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('storage keys keep workflow and session namespaces stable', () {
    expect(StorageKeys.schemaVersion, 'schema:version');
    expect(StorageKeys.workflowIndex, 'workflow:index');
    expect(StorageKeys.mediaAssetIndex, 'media:asset:index');
    expect(StorageKeys.workflowDocument('demo'), 'workflow:demo');
    expect(StorageKeys.workflowSession('demo'), 'session:workflow:demo');
  });
}
