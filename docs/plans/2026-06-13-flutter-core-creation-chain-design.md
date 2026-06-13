# Flutter 核心创作链 (Core Creation Chain) 设计方案

**日期:** 2026-06-13
**分支建议:** 接续 `feat/flutter-runnable-chain`
**前置:** [2026-06-13-flutter-minimum-runnable-chain.md](2026-06-13-flutter-minimum-runnable-chain.md) 已落地的「最小可跑链路」

---

## 目标与定位

把 Flutter 端 (`cain_flow_mob`) 从「只能跑预置图、不能编辑」推进到「**能在手机上搭出并跑通一条图像创作链**」。

定位为 **C 方案:核心创作链**,不追求与桌面 Web 版完整对等。

### 本期要做

- 画布编辑交互:新增 / 删除节点、点选式连线、底部表单改参数(D 方案)
- 打通「画布参数 ↔ 执行 ↔ 持久化」数据中枢
- 核心 6 节点全部可用:Text、TextChat、ImageGenerate、ImageImport、ImagePreview、ImageSave
- custom-params 自定义参数注入
- 异步图像协议(通用框架 + newapi-image-async)
- 轻量多工作流(新建 / 切换 / 重命名 / 删除)

### 本期不做(明确边界)

- 视频生成与视频异步协议(veo / doubao)
- 控制流(条件 / 循环)节点
- 统计、Prompt 库、历史记录、帮助面板
- 图片裁剪 / 绘制
- text-merge / text-split / image-resize / merge / compare 辅助节点
- 配置 ZIP 导入导出、Provider 健康检查、并发执行、撤销重做

---

## 现状关键发现

执行器 ([cain_flow_node_executor.dart](../../cain_flow_mob/lib/features/execution/cain_flow_node_executor.dart)) 已能读 `node.data['prompt'] / ['size'] / ['apiConfigId'] / ['providerId']`,但:

- `WorkbenchNode` ([workbench_signals.dart](../../cain_flow_mob/lib/features/workbench/workbench_signals.dart)) **没有 `data` 字段**。
- `workbenchToWorkflow` 的 `_nodeToFlowNode` ([workbench_workflow_mapper.dart](../../cain_flow_mob/lib/features/workbench/workbench_workflow_mapper.dart)) **没有透传 `data`**。

结果:UI 搭出来的图参数全空,执行必然抛 `No model configured` / 空 prompt。**这是本期第一优先要修的中枢断裂。**

其余:画布只读(新增 / 删除 / 连线 / 改参数全无),ImageImport / ImagePreview 仅注册未实现,无异步执行路径,只有单一工作流。

---

## 设计 ① 数据模型:打通画布参数中枢

**文件:** `workbench_signals.dart`、`workbench_workflow_mapper.dart`、`node_definition.dart`、`node_registry.dart`

1. `WorkbenchNode` 增加 `data: Map<String, dynamic>`(prompt、size、quality、apiConfigId、providerId、自定义参数等);`fromJson` / `toJson` / `moveBy` 同步携带。
2. `_nodeToFlowNode` 把 `node.data` 透传进 `FlowNode(data: ...)`;`applyWorkflowToWorkbench` 反向把 `FlowNode.data` 带回 `WorkbenchNode`。
3. `NodeDefinition` 增加 `params: List<NodeParamDefinition>`(字段名、label、控件类型 `text/multiline/number/select/modelPicker/customParams`、可选项、默认值),底部表单据此**数据驱动渲染**,新增节点只改定义。

**收益:** 执行器读取逻辑零改动即生效;「画布 ↔ 执行 ↔ 持久化」参数不再丢。这是整个方案的地基。

---

## 设计 ② 画布编辑交互(D 方案)

视觉保留节点图,操作避开手画线。所有编辑能力下沉到 `WorkbenchSignals`。

**新增 / 删除节点**
- 「New workflow」旁 + 画布空白长按弹节点选择器(`nodeRegistry.all`),点选在画布中心生成 `WorkbenchNode`,`id = node_<type>_<timestamp>`,`data` 用 `params` 默认值初始化。
- 信号:`addNode(type)`、`removeNode(id)`(级联删相关连线)。

**点选式连线**
- 点输出端口 → 进入待定态(`pendingConnectionFrom`,端口高亮);点另一节点输入端口 → 生成连线;点空白 / 同端口 → 取消。
- 校验:类型匹配(text→text / image→image)、禁自连、单输入端口只留一条(新替旧)、禁成环(连线时复用 `ExecutionPlan` 拓扑预检)。
- 信号:`beginConnection` / `completeConnection` / `cancelPendingConnection` / `removeConnection`。

**编辑参数(底部 sheet)**
- 点节点(非端口)选中 → 窄屏 `showModalBottomSheet`、宽屏 Inspector,按 `NodeDefinition.params` 渲染表单,改动写回 `node.data` 经 autosave 落盘。
- `modelPicker` 从 `ProviderSettings.models` 取选项,实现**按节点选模型**覆盖全局默认。

**删除**
- 选中节点后 sheet/Inspector 给「删除节点」;连线长按弹「删除连线」。

---

## 设计 ③ 异步图像 + ImageImport / ImagePreview

**异步图像(通用框架,先接 newapi-image-async)**

不改现有同步路径,加一层。沿用 Web 版契约
([provider-request-utils.js](../../js/features/execution/provider-request-utils.js)):

- 提交:POST → `extractAsyncImageTaskId`(`id/task_id/data.id/...`)
- 轮询:GET status → `extractAsyncImageStatus`(`completed/failed/pending`)
- 取结果:`completed` → `extractAsyncImageResult`(`data.image_url/url/...`)

实现:`ModelProtocol` 增 `newApiImageAsync`;新增异步分支按 `RuntimeSettings` 可配的**轮询间隔(默认 2s)/ 超时(默认 5min)**循环 GET,每次 `await` 前查取消标记;结果归一为现有 `{kind:'url'}` 或下载后 `{kind:'asset'}`,下游不改。

**ImageImport** — 用 `image_picker` 选图 → `MediaRepository.saveBytes` 存 asset → 输出 `{kind:'asset'}`;`data` 存 assetId,重跑免重选。

**ImagePreview** — 输入 payload 存节点输出(已有),新增 `NodeCard` 内嵌缩略图:asset 读本地文件,url 用 `cached_network_image`(带缓存 + 占位 / 失败态)。

**新依赖:** `image_picker`、`cached_network_image`。

---

## 设计 ④ 持久化 / 多工作流 / 收尾

**轻量多工作流**
- 左侧列表读 `WorkflowRepository.listWorkflowIds()`,支持新建 / 切换 / 重命名 / 删除。
- 切换:先 `autosave.flush()` 当前 → load 目标 → `applyWorkflowToWorkbench`。
- 删除:调 `MediaRepository.cleanOrphanedAssets` 清孤儿媒体。
- 不做 tab 多开,一次一个活动工作流。

**参数随图持久化**
- 设计 ① 打通后 autosave session JSON 自然带参数;`WorkflowDocument` 版本 1.3 → 1.4,加「无 `data` 字段按空 map 容错」的向后兼容读取。

**收尾**
- `flutter analyze` 干净 + `flutter test` 全绿。
- 新增单测:mapper 带 data 往返、连线校验 / 环检测、异步轮询(本地 `HttpServer` mock)、表单写回。
- README / 文档更新:新增节点、异步图像配置、`image_picker` 的 Android/iOS 相册权限说明。

---

## 实施阶段建议

1. **Phase 1 地基** — 设计 ①(`data` 中枢 + `NodeDefinition.params`),先让预置图带参跑通。
2. **Phase 2 编辑** — 设计 ②(新增 / 删除 / 连线 / 表单)。
3. **Phase 3 节点** — ImageImport(`image_picker`)、ImagePreview(`cached_network_image`)、custom-params。
4. **Phase 4 异步** — newapi-image-async 通用框架 + 轮询。
5. **Phase 5 工作流** — 轻量多工作流管理。
6. **Phase 6 收尾** — 测试、文档、权限。

每阶段独立可测、可交付,顺序前依后。

