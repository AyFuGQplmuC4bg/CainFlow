abstract final class StorageKeys {
  static const schemaVersion = 'schema:version';
  static const workflowIndex = 'workflow:index';
  static const activeWorkflowId = 'workflow:active';
  static const settings = 'settings:global';
  static const providerSettings = 'settings:providers';
  static const mediaAssetIndex = 'media:asset:index';
  static const logRing = 'logs:ring';

  static String workflowDocument(String id) => 'workflow:$id';

  static String workflowSession(String id) => 'session:workflow:$id';
}
