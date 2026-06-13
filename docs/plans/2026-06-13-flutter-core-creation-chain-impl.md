# Flutter 核心创作链 实施计划 (Implementation Plan)

> **For Claude:** 按 task 逐条实现,每个 task 完成后跑 `flutter analyze` + 相关测试。

**目标:** 把 [设计方案](2026-06-13-flutter-core-creation-chain-design.md) 落地为可执行任务。

**前置基线:** `flutter analyze` 干净,`flutter test` 全绿(24+ 测试)。

---

## Phase 1 地基:打通画布参数中枢

### Task 1.1 NodeDefinition 增加 params 描述

**文件:** `lib/features/nodes/node_definition.dart`、`lib/features/nodes/node_registry.dart`、`test/features/nodes/node_registry_test.dart`

**步骤:**
1. 新增 `NodeParamDefinition`(`name`、`label`、`control` 枚举 `text/multiline/number/select/modelPicker/customParams`、`options`、`defaultValue`、`taskType?`)。
2. `NodeDefinition` 增加 `params: List<NodeParamDefinition>`。
3. 给 registry 各节点补 params:
   - Text → `text`(multiline)
   - TextChat → `systemPrompt`(multiline)、`apiConfigId`(modelPicker, chat)、`customParams`
   - ImageGenerate → `apiConfigId`(modelPicker, image)、`size`(select)、`quality`(select)、`customParams`
   - ImageImport → `assetId`(隐藏 / 只读,由选图写入)
   - ImagePreview → 无可编辑参数
   - ImageSave → 无(或 fileName 可选)
4. 测试:每个节点 def 可取到 params,默认值正确。

### Task 1.2 WorkbenchNode 携带 data

**文件:** `lib/features/workbench/workbench_signals.dart`、`test/features/workbench/workbench_signals_test.dart`

**步骤:**
1. `WorkbenchNode` 增加 `data: Map<String, dynamic>`(默认空 map)。
2. `fromJson` / `toJson` / `moveBy` 携带 data。
3. 新增 `updateNodeData(nodeId, data)` 信号方法(整体替换该节点 data)。
4. 测试:data 往返、updateNodeData 生效、moveBy 保留 data。

### Task 1.3 mapper 透传 data

**文件:** `lib/features/workbench/workbench_workflow_mapper.dart`、`test/features/workbench/workbench_workflow_mapper_test.dart`

**步骤:**
1. `_nodeToFlowNode` 把 `node.data` 传入 `FlowNode(data: ...)`。
2. `applyWorkflowToWorkbench` 把 `FlowNode.data` 带回 `WorkbenchNode`。
3. 测试:带 data 的图往返一致(尤其 prompt/apiConfigId)。

### Task 1.4 执行器接通 customParams / systemPrompt

**文件:** `lib/features/execution/cain_flow_node_executor.dart`、`test/features/execution/cain_flow_node_executor_test.dart`

**步骤:**
1. TextChat:从 `node.data['systemPrompt']`、`node.data['customParams']` 传入 `buildChatRequest`。
2. ImageGenerate:从 `node.data['customParams']` 传入 `buildImageRequest`。
3. 测试:fake client 验证 systemPrompt/customParams 进入请求体。

**Phase 1 成功标准:** 预置图带 data 时可跑通,参数不再丢失。

---

## Phase 2 画布编辑交互

### Task 2.1 节点增删信号

**文件:** `workbench_signals.dart`、`workbench_signals_test.dart`
- `addNode(type)`(画布中心,data 用 params 默认值)、`removeNode(id)`(级联删连线)。
- 测试:增删、级联删连线。

### Task 2.2 点选式连线信号 + 校验

**文件:** `workbench_signals.dart`、新增 `lib/features/workbench/connection_rules.dart`、对应测试
- `pendingConnectionFrom` 信号;`beginConnection` / `completeConnection` / `cancelPendingConnection` / `removeConnection`。
- 校验:类型匹配、禁自连、单输入端口替换、禁成环(复用 `ExecutionPlan` 拓扑预检)。
- 测试:合法连线、各类非法连线被拒、环检测。

### Task 2.3 节点选择器 UI

**文件:** `workbench_screen.dart`、widget 测试
- 「New workflow」旁 + 画布空白长按 → 节点选择器(`nodeRegistry.all`)。

### Task 2.4 端口可点击 + 连线 UI

**文件:** `widgets/node_card.dart`、`workbench_screen.dart`
- 端口点击回调,待定态高亮;`ConnectionLayer` 显示待定连线。

### Task 2.5 参数底部 sheet(数据驱动表单)

**文件:** 新增 `lib/features/workbench/widgets/node_param_sheet.dart`、widget 测试
- 选中节点弹 `showModalBottomSheet`,按 `NodeDefinition.params` 渲染控件,写回 `updateNodeData`。
- `modelPicker` 从 `ProviderSettings.models` 按 taskType 过滤;`customParams` 用 key-value 编辑。
- sheet 内提供「删除节点」。

**Phase 2 成功标准:** 手机上能新增节点、连线、改参数、删除。

---

## Phase 3 节点落地

### Task 3.1 custom-params 注入

**文件:** `cain_flow_node_executor.dart`、测试
- 解析 `node.data['customParams']`(支持数字/布尔/字符串),合并进 chat/image 请求。

### Task 3.2 ImageImport(image_picker)

**文件:** `pubspec.yaml`、`cain_flow_node_executor.dart`、`node_param_sheet.dart`、Android/iOS 权限配置、测试
- 加 `image_picker` 依赖;sheet 内「选择图片」→ `MediaRepository.saveBytes` → 写 `data['assetId']`。
- 执行 ImageImport:读 assetId → 输出 `{kind:'asset'}`。
- 配置 Android `READ_MEDIA_IMAGES` / iOS `NSPhotoLibraryUsageDescription`。

### Task 3.3 ImagePreview(cached_network_image)

**文件:** `pubspec.yaml`、`cain_flow_node_executor.dart`、`widgets/node_card.dart`、测试
- 加 `cached_network_image` 依赖。
- ImagePreview 执行:输入透传到输出。
- `NodeCard` 对有 image 的节点渲染缩略图:asset 读本地 `File`,url 用 `CachedNetworkImage`。

**Phase 3 成功标准:** 六节点全部可用,导入/预览生效。

---

## Phase 4 异步图像

### Task 4.1 协议与设置扩展

**文件:** `provider_settings.dart`、测试
- `ModelProtocol` 增 `newApiImageAsync`;`RuntimeSettings` 增 `asyncPollIntervalSeconds`(默认 2)、`asyncTimeoutSeconds`(默认 300)。
- 向后兼容旧 JSON。

### Task 4.2 异步请求构建 + 结果解析

**文件:** 新增 `lib/features/execution/async_image_protocol.dart`、测试
- 提交请求构建;`extractTaskId` / `extractStatus` / `extractResultUrl`(对齐 Web 版字段集)。
- 纯函数,单测覆盖各字段形态。

### Task 4.3 异步执行分支

**文件:** `cain_flow_node_executor.dart`、`execution_services.dart`、测试
- ImageGenerate 检测到 `newApiImageAsync` → 提交 → 按间隔轮询(每次 await 前查取消)→ completed 取 url(可下载存 asset)/ failed 抛错。
- 测试:本地 `HttpServer` mock 提交→轮询→完成 / 失败 / 超时 / 取消。

**Phase 4 成功标准:** 异步图像模型可跑通,取消/超时可控。

---

## Phase 5 轻量多工作流

### Task 5.1 工作流列表与切换

**文件:** `workbench_screen.dart`、`workbench_execution_controller.dart` 或新增 manager、测试
- 左侧列表读 `WorkflowRepository.listWorkflowIds()`;新建 / 切换 / 重命名 / 删除。
- 切换:`autosave.flush()` → load → `applyWorkflowToWorkbench`。
- 删除:`MediaRepository.cleanOrphanedAssets`。

### Task 5.2 版本兼容

**文件:** `core/models/workflow_document.dart`、测试
- 版本 1.3 → 1.4;无 `data` 字段按空 map 容错读取。

**Phase 5 成功标准:** 多工作流可建可切可删,旧文件不报错。

---

## Phase 6 收尾

### Task 6.1 全量验证

- `flutter analyze` 干净;`flutter test` 全绿。

### Task 6.2 文档与权限

**文件:** `cain_flow_mob/README.md`
- 新增节点说明、异步图像配置、相册权限说明、本期不支持清单。

