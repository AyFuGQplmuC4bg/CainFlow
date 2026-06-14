import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Convenience accessor.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Hand-written localizations for EN and ZH.
abstract class AppLocalizations {
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizationsEn();
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// All delegates needed by MaterialApp (includes framework delegates).
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('zh'),
  ];

  // --- Workbench AppBar ---
  String get importWorkflow;
  String get undo;
  String get redo;
  String get saveWorkflow;
  String get logs;
  String get settings;
  String get stop;
  String get run;
  String savedWorkflowSnack(String name);

  // --- Canvas / connections ---
  String get cannotConnectSelf;
  String get portTypeMismatch;
  String get connectionCycle;
  String get zoomOut;
  String get zoomIn;

  // --- Run timer overlay ---
  String get cancelRun;

  // --- Workflow rail ---
  String get workflows;
  String get addNode;
  String get newWorkflow;
  String get renameWorkflow;
  String get workflowHint;
  String get rename;
  String get delete;
  String get nameLabel;
  String get cancel;
  String get ok;

  // --- Inspector ---
  String get inspector;
  String get selectNodeHint;
  String get clearSelection;
  String statusLabel(String label);
  String runningDuration(String secs);
  String elapsedDuration(String secs);

  // --- Execution status / node state labels ---
  String get statusReady;
  String get statusRunning;
  String get statusCompleted;
  String get statusFailed;
  String get statusCanceled;
  String get statePending;
  String get stateSkipped;

  // --- Settings ---
  String get settingsTitle;
  String get closeSettings;
  String get providers;
  String get addProvider;
  String get noProviders;
  String get models;
  String get addModel;
  String get noModels;
  String get runtimeSection;
  String get timeoutLabel;
  String get retryCountLabel;
  String get asyncPollLabel;
  String get asyncTimeoutLabel;
  String get completionSoundLabel;
  String get completionHapticsLabel;
  String get activeChatModel;
  String get activeImageModel;
  String get noneOption;
  String get workflowJson;
  String get exportGraph;
  String get pasteJsonLabel;
  String get importIntoWorkbench;
  String get pasteFirst;
  String invalidWorkflowJson(String message);
  String get couldNotImport;
  String get addProviderTitle;
  String get editProviderTitle;
  String get endpointLabel;
  String get apiKeyLabel;
  String get protocolLabel;
  String get testConnection;
  String get save;
  String get addModelTitle;
  String get editModelTitle;
  String get modelIdLabel;
  String get taskTypeLabel;
  String get providerLabel;
  String get editTooltip;
  String get deleteTooltip;
  String get language;
  String get langSystem;
  String get langEnglish;
  String get langChinese;

  // --- Node param sheet ---
  String get deleteNode;
  String get noEditableParams;
  String get editCamera;
  String get noImageSelected;
  String imageSelected(String id);
  String get chooseImage;
  String get defaultOption;
  String get noMatchingModels;
  String get mustBeJsonObject;
  String get invalidJson;
  String get jsonSuffix;

  // --- Folder picker ---
  String get browseFolder;
  String get noFolderSelected;
  String imageSavedTo(String path);

  // --- Log panel ---
  String get clearLogs;
  String get noLogsYet;

  // --- Compact overflow menu ---
  String get moreActions;
}

// ---------------------------------------------------------------------------
// English
// ---------------------------------------------------------------------------

class AppLocalizationsEn extends AppLocalizations {
  @override String get importWorkflow => 'Import workflow';
  @override String get undo => 'Undo';
  @override String get redo => 'Redo';
  @override String get saveWorkflow => 'Save workflow';
  @override String get logs => 'Logs';
  @override String get settings => 'Settings';
  @override String get stop => 'Stop';
  @override String get run => 'Run';
  @override String savedWorkflowSnack(String name) => 'Saved "$name"';

  @override String get cannotConnectSelf => 'Cannot connect a node to itself';
  @override String get portTypeMismatch => 'Port types do not match';
  @override String get connectionCycle => 'That link would create a cycle';
  @override String get zoomOut => 'Zoom out';
  @override String get zoomIn => 'Zoom in';

  @override String get cancelRun => 'Cancel';

  @override String get workflows => 'Workflows';
  @override String get addNode => 'Add node';
  @override String get newWorkflow => 'New workflow';
  @override String get renameWorkflow => 'Rename workflow';
  @override String get workflowHint => 'Long-press a workflow to rename or delete';
  @override String get rename => 'Rename';
  @override String get delete => 'Delete';
  @override String get nameLabel => 'Name';
  @override String get cancel => 'Cancel';
  @override String get ok => 'OK';

  @override String get inspector => 'Inspector';
  @override String get selectNodeHint => 'Select a node to edit its settings.';
  @override String get clearSelection => 'Clear selection';
  @override String statusLabel(String label) => 'Status: $label';
  @override String runningDuration(String secs) => 'Running ${secs}s';
  @override String elapsedDuration(String secs) => 'Elapsed ${secs}s';

  @override String get statusReady => 'Ready';
  @override String get statusRunning => 'Running';
  @override String get statusCompleted => 'Completed';
  @override String get statusFailed => 'Failed';
  @override String get statusCanceled => 'Canceled';
  @override String get statePending => 'Pending';
  @override String get stateSkipped => 'Skipped';

  @override String get settingsTitle => 'Settings';
  @override String get closeSettings => 'Close settings';
  @override String get providers => 'Providers';
  @override String get addProvider => 'Add provider';
  @override String get noProviders => 'No providers configured';
  @override String get models => 'Models';
  @override String get addModel => 'Add model';
  @override String get noModels => 'No models configured';
  @override String get runtimeSection => 'Runtime';
  @override String get timeoutLabel => 'Timeout (seconds)';
  @override String get retryCountLabel => 'Retry count';
  @override String get asyncPollLabel => 'Async poll (seconds)';
  @override String get asyncTimeoutLabel => 'Async timeout (seconds)';
  @override String get completionSoundLabel => 'Completion sound';
  @override String get completionHapticsLabel => 'Vibrate on completion';
  @override String get activeChatModel => 'Active chat model';
  @override String get activeImageModel => 'Active image model';
  @override String get noneOption => 'None';
  @override String get workflowJson => 'Workflow JSON';
  @override String get exportGraph => 'Export graph';
  @override String get pasteJsonLabel => 'Paste workflow JSON to import';
  @override String get importIntoWorkbench => 'Import into workbench';
  @override String get pasteFirst => 'Paste workflow JSON first.';
  @override String invalidWorkflowJson(String message) => 'Invalid workflow JSON: $message';
  @override String get couldNotImport => 'Could not import workflow.';
  @override String get addProviderTitle => 'Add provider';
  @override String get editProviderTitle => 'Edit provider';
  @override String get endpointLabel => 'Endpoint';
  @override String get apiKeyLabel => 'API key';
  @override String get protocolLabel => 'Protocol';
  @override String get testConnection => 'Test connection';
  @override String get save => 'Save';
  @override String get addModelTitle => 'Add model';
  @override String get editModelTitle => 'Edit model';
  @override String get modelIdLabel => 'Model ID';
  @override String get taskTypeLabel => 'Task type';
  @override String get providerLabel => 'Provider';
  @override String get editTooltip => 'Edit';
  @override String get deleteTooltip => 'Delete';
  @override String get language => 'Language';
  @override String get langSystem => 'System';
  @override String get langEnglish => 'English';
  @override String get langChinese => '中文';

  @override String get deleteNode => 'Delete node';
  @override String get noEditableParams => 'This node has no editable parameters.';
  @override String get editCamera => 'Edit';
  @override String get noImageSelected => 'No image selected';
  @override String imageSelected(String id) => 'Selected: $id';
  @override String get chooseImage => 'Choose';
  @override String get defaultOption => '(default)';
  @override String get noMatchingModels => 'No matching models configured';
  @override String get mustBeJsonObject => 'Must be a JSON object';
  @override String get invalidJson => 'Invalid JSON';
  @override String get jsonSuffix => '(JSON)';
  @override String get clearLogs => 'Clear logs';
  @override String get noLogsYet => 'No logs yet';
  @override String get moreActions => 'More';
  @override String get browseFolder => 'Browse';
  @override String get noFolderSelected => 'No folder selected';
  @override String imageSavedTo(String path) => 'Image copied to $path';
}

// ---------------------------------------------------------------------------
// Chinese (Simplified)
// ---------------------------------------------------------------------------

class AppLocalizationsZh extends AppLocalizations {
  @override String get importWorkflow => '导入工作流';
  @override String get undo => '撤销';
  @override String get redo => '重做';
  @override String get saveWorkflow => '保存工作流';
  @override String get logs => '日志';
  @override String get settings => '设置';
  @override String get stop => '停止';
  @override String get run => '运行';
  @override String savedWorkflowSnack(String name) => '已保存「$name」';

  @override String get cannotConnectSelf => '不能连接到节点自身';
  @override String get portTypeMismatch => '端口类型不匹配';
  @override String get connectionCycle => '连接会形成循环';
  @override String get zoomOut => '缩小';
  @override String get zoomIn => '放大';

  @override String get cancelRun => '取消';

  @override String get workflows => '工作流';
  @override String get addNode => '添加节点';
  @override String get newWorkflow => '新建工作流';
  @override String get renameWorkflow => '重命名工作流';
  @override String get workflowHint => '长按工作流以重命名或删除';
  @override String get rename => '重命名';
  @override String get delete => '删除';
  @override String get nameLabel => '名称';
  @override String get cancel => '取消';
  @override String get ok => '确定';

  @override String get inspector => '检查器';
  @override String get selectNodeHint => '选择节点以编辑参数。';
  @override String get clearSelection => '清除选择';
  @override String statusLabel(String label) => '状态: $label';
  @override String runningDuration(String secs) => '已运行 ${secs}s';
  @override String elapsedDuration(String secs) => '耗时 ${secs}s';

  @override String get statusReady => '就绪';
  @override String get statusRunning => '运行中';
  @override String get statusCompleted => '完成';
  @override String get statusFailed => '失败';
  @override String get statusCanceled => '已取消';
  @override String get statePending => '等待';
  @override String get stateSkipped => '已跳过';

  @override String get settingsTitle => '设置';
  @override String get closeSettings => '关闭设置';
  @override String get providers => '服务商';
  @override String get addProvider => '添加服务商';
  @override String get noProviders => '未配置服务商';
  @override String get models => '模型';
  @override String get addModel => '添加模型';
  @override String get noModels => '未配置模型';
  @override String get runtimeSection => '运行参数';
  @override String get timeoutLabel => '超时 (秒)';
  @override String get retryCountLabel => '重试次数';
  @override String get asyncPollLabel => '异步轮询 (秒)';
  @override String get asyncTimeoutLabel => '异步超时 (秒)';
  @override String get completionSoundLabel => '完成提示音';
  @override String get completionHapticsLabel => '完成时震动';
  @override String get activeChatModel => '当前对话模型';
  @override String get activeImageModel => '当前图像模型';
  @override String get noneOption => '无';
  @override String get workflowJson => '工作流 JSON';
  @override String get exportGraph => '导出';
  @override String get pasteJsonLabel => '粘贴工作流 JSON 以导入';
  @override String get importIntoWorkbench => '导入到工作台';
  @override String get pasteFirst => '请先粘贴工作流 JSON。';
  @override String invalidWorkflowJson(String message) => '工作流 JSON 无效: $message';
  @override String get couldNotImport => '无法导入工作流。';
  @override String get addProviderTitle => '添加服务商';
  @override String get editProviderTitle => '编辑服务商';
  @override String get endpointLabel => '接口地址';
  @override String get apiKeyLabel => 'API 密钥';
  @override String get protocolLabel => '协议';
  @override String get testConnection => '测试连接';
  @override String get save => '保存';
  @override String get addModelTitle => '添加模型';
  @override String get editModelTitle => '编辑模型';
  @override String get modelIdLabel => '模型 ID';
  @override String get taskTypeLabel => '任务类型';
  @override String get providerLabel => '服务商';
  @override String get editTooltip => '编辑';
  @override String get deleteTooltip => '删除';
  @override String get language => '语言';
  @override String get langSystem => '跟随系统';
  @override String get langEnglish => 'English';
  @override String get langChinese => '中文';

  @override String get deleteNode => '删除节点';
  @override String get noEditableParams => '此节点无可编辑参数。';
  @override String get editCamera => '编辑';
  @override String get noImageSelected => '未选择图片';
  @override String imageSelected(String id) => '已选: $id';
  @override String get chooseImage => '选择';
  @override String get defaultOption => '(默认)';
  @override String get noMatchingModels => '未配置匹配的模型';
  @override String get mustBeJsonObject => '必须是 JSON 对象';
  @override String get invalidJson => 'JSON 格式无效';
  @override String get jsonSuffix => '(JSON)';
  @override String get clearLogs => '清除日志';
  @override String get noLogsYet => '暂无日志';
  @override String get moreActions => '更多';
  @override String get browseFolder => '浏览';
  @override String get noFolderSelected => '未选择文件夹';
  @override String imageSavedTo(String path) => '图片已复制到 $path';
}

// ---------------------------------------------------------------------------
// Delegate
// ---------------------------------------------------------------------------

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return locale.languageCode == 'zh' ? AppLocalizationsZh() : AppLocalizationsEn();
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
