# Flutter 运行中节点状态显示 设计方案

**日期:** 2026-06-14
**目标:** 仿原 Web 工程,为 mob 增加运行中节点的可视化 —— 运行到哪个节点、各节点状态、实时计时、异步轮询进度、底部计时蒙版与取消。

---

## 现状对比

| 维度 | 原 Web 版 | mob 现状 |
|------|-----------|----------|
| 节点运行高亮 | `.running` 青色发光动画 | 无(卡片不反映运行态) |
| 计时 | `#{id}-time` 实时跳秒,完成定格 | **完全无计时** |
| 生成/轮询进度 | `1/3`、轮询「第 N 次」 | 无 |
| 整体进度 | — | 无 |
| 状态显示位置 | 节点 DOM 上 | 仅底部状态条 + Inspector 文字 |

mob 的 `ExecutionSignals` 只跟踪 `NodeRunState`(pending/running/completed/failed/skipped)状态转换,无任何 `DateTime`/`Duration`。

## 范围(用户选定)

- **全做(C)**:节点卡片运行态 + Inspector 详情 + 底部整体感知。
- 计时:**实时跳秒**,但时长**不放节点徽章**,改为**底部中央蒙版**显示已用时 + 取消按钮。
- 节点卡片:运行高亮发光、完成/失败/跳过边框色、角落状态点/转圈、异步轮询进度。
- 蒙版内容:**仅计时 + 取消**。

---

## 设计 ① 计时数据层

**文件:** `lib/features/execution/execution_signals.dart`

- `NodeRunSnapshot` 增 `startedAt: DateTime?` / `finishedAt: DateTime?`;计算 `duration`(running→`now-startedAt`,终态→区间)。
- `markNode(running)` 盖 `startedAt`;`markNode(completed/failed/skipped)` 盖 `finishedAt` 并清该节点 `pollProgress`。
- 新增 `workflowStartedAt`(`markWorkflowRunning` 时记)。
- 新增 `pollProgress: Map<String,String>`(节点→进度文本);`setPollProgress`/清除。
- 计算 `completedCount` / `totalCount`(由 `nodeStates` 派生)。
- **全局 ticker**:`nowTick = signal<DateTime>`,`Timer.periodic(1s)` 仅在工作流 running 期间驱动,idle 停。读 `duration` 的 widget 同读 `nowTick` 实现跳秒;终态不依赖 tick。
- `now` 可注入(测试用)。

## 设计 ② 执行器/引擎接线

**文件:** `workflow_runner.dart`、`iterative_workflow_runner.dart`、`cain_flow_node_executor.dart`、`execution_services.dart`

- 两个引擎**零逻辑改动**:时间戳由 `markNode` 内部自动盖。
- 异步进度:`ExecutionServices` 加可选 `executionSignals`;`_executeAsyncImageGenerate` 轮询每次调 `setPollProgress(nodeId, '轮询 $attempt')`。默认控制器注入全局 signals,测试可不传(进度空,不影响)。

## 设计 ③ NodeCard 运行态视觉

**文件:** `widgets/node_card.dart`、`workbench_screen.dart`

- 入参 `runState: NodeRunState?` + `pollText: String?`,画布从 `executionSignals` 传入(SignalWidget 自动重建)。
- 边框/发光:running 青色呼吸发光;completed 绿;failed 红;skipped 置灰;selected 优先描边,运行态叠加。
- 右上角状态点(Stack 角标):pending 灰 / running 青转圈 / completed 绿 / failed 红 / skipped 暗灰。
- 轮询文本:有 `pollText` 时描述行下方一行青色小字。
- **不增高卡片**(角标用 Stack 叠加、轮询文本占预留位),避免连线锚点偏移。

## 设计 ④ 底部计时蒙版

**文件:** `workbench_screen.dart`(`_CanvasStage` 的 Stack)

- 底部中央胶囊蒙版,`Positioned(bottom:16)` 水平居中。
- 内容:左「12.3s」(读 `workflowStartedAt`+`nowTick` 跳秒),右「取消」按钮 → `controller.stop()`。
- 显隐:`workflowState==running` 时 `AnimatedOpacity` 淡入,否则淡出;不定格。
- 半透明深色圆角 + 阴影,仅占中间一小条,不挡节点操作。

## 设计 ⑤ Inspector / 状态条 / 测试

- Inspector `_NodeStatusLine` 补时长行:running「已运行 8.2s」、终态「耗时 2.45s」。
- 底部左下状态条:running 时「Running · 3/5」(`completedCount/totalCount`)。
- 测试:
  - signals:时间戳、duration(注入 now)、count、pollProgress 增删、ticker 启停。
  - widget:NodeCard 各状态边框/状态点;蒙版 running 显示/idle 隐藏/点取消触发 stop(fake controller)。
  - 复用既有锚点测试确认卡片高度不变。

## 不做(YAGNI)

- 节点上的定格时长徽章(改放蒙版/Inspector)。
- 并发点阵(mob 已分层并发,单节点状态点足够)。
- 历史耗时(已有 createdAt)。

---

## 实施顺序

1. **Phase A 计时数据层**(设计①)—— signals + ticker + 测试。
2. **Phase B 接线**(设计②)—— ExecutionServices 注入 + 异步进度。
3. **Phase C 节点视觉**(设计③)—— NodeCard runState/状态点/轮询。
4. **Phase D 蒙版 + Inspector + 状态条**(设计④⑤)。
5. **Phase E 验证** —— analyze + test 全绿,README 截图说明。
