# CainFlow Mobile — Future Features 实施计划(P1–P4 选定项)

> **For Claude:** 按 task 逐条实现,每个 task 完成后 `flutter analyze` + 相关测试。逐阶段提交。

**目标:** 在核心创作链(Phase 1–6)之上,实现用户选定的 future features:
F2 辅助节点、F3 多参考图、F4 远程下载、并发执行、撤销重做、配置 ZIP、
Provider 健康检查、真缩略图、历史记录、Prompt 库、统计、控制流、裁剪绘制、
相机节点、流式响应。

**技术选型(已定):**
- 图像处理统一用 `image` 包(resize/merge/compare/缩略图/裁剪)。
- 控制流新建独立的**迭代式执行引擎**(支持循环/条件),不破坏现有拓扑执行器。

**新增依赖(预估):** `image`、`archive`、`file_picker`、`share_plus`、`camera`(F18 相机节点)。

---

## Phase 7 — 图像基建 + 辅助节点(F2 + 真缩略图)

依赖 `image` 包。先建图像服务,再铺节点与缩略图。

### Task 7.1 引入 image 包 + ImageOps 服务
- 加 `image` 依赖。
- 新建 `lib/features/media/image_ops.dart`:`decode`、`resize(w,h,fit)`、
  `merge(list, layout)`、`encodePng/Jpg`,纯函数 + 单测(用内置小图)。

### Task 7.2 真缩略图服务
- 实现 `ThumbnailService`(替换 passthrough):解码原图 → 缩放到 ~256px →
  存 `{assetId}-thumb.png` → 写回 `MediaAsset.thumbnailRelativePath`。
- NodeImageThumbnail 优先读缩略图文件。
- 测试:缩略图生成、尺寸上限、索引回写。

### Task 7.3 text-merge / text-split 节点
- registry 注册;executor 实现(纯本地:merge 连接多输入文本,split 按行/分隔符)。
- 动态输入端口(text-merge 可扩展 text_1..n);split 输出动态命名。
- 测试。

### Task 7.4 image-resize / image-merge / image-compare 节点
- registry + executor,用 ImageOps;结果存 MediaRepository。
- compare 输出并排对比图。
- 测试(fake 输入 asset)。

---

## Phase 8 — 参考图与远程媒体(F3 + F4)

### Task 8.1 ImageGenerate / TextChat 多参考图输入
- 端口扩展:image_1..n(可扩展);mask(ImageGenerate)。
- provider_request_builder 注入参考图(base64/url,参照原版 getOpenAiReferenceImages)。
- 测试:参考图进入请求体。

### Task 8.2 远程图片下载落盘
- 新建下载工具:HTTP 拉流 → MediaRepository.saveBytes,失败可重试。
- ImageSave / ImageGenerate(url 结果)可选下载落盘(节点参数 downloadToLocal)。
- 测试:本地 HttpServer mock 下载。

---

## Phase 9 — 执行体验(并发 + 撤销重做)

### Task 9.1 并发执行
- WorkflowRunner 改为按 DAG 层级并发(同层无依赖节点并行),加并发上限
  (RuntimeSettings.maxConcurrency)+ 取消传播。
- 保持失败短路语义可配。
- 测试:并发顺序、上限、取消、失败。

### Task 9.2 撤销 / 重做
- 新建 `lib/features/workbench/history_stack.dart`:对 nodes/connections/data
  快照(上限 N 步)。
- 监听 workbench 变更入栈;undo/redo 信号 + AppBar 按钮。
- 测试:增删/连线/改参数后 undo/redo 正确还原。

---

## Phase 10 — 配置与可靠性(配置 ZIP + Provider 健康检查)

### Task 10.1 配置 ZIP 导入导出
- 加 `archive` + `file_picker`/`share_plus`。
- 打包 providers+models+settings+workflows 为 ZIP;导入解包合并。
- 测试:打包/解包往返(内存)。

### Task 10.2 Provider 健康检查 + 拉取模型
- 设置页「测试连接」按钮:探测端点连通性 + 鉴权;「拉取模型」从端点取可用模型列表。
- 测试:本地 HttpServer mock 成功/失败/超时。

---

## Phase 11 — 周边模块(历史 + Prompt 库 + 统计)

### Task 11.1 执行历史
- 新建 history feature:每次运行写入条目(缩略图、prompt、provider/model、时间),
  侧栏列表 + 全屏预览 + 删除,懒加载。MMKV 索引 + 媒体复用。
- 测试:写入/读取/删除/留存上限。

### Task 11.2 Prompt 库
- 模板保存(标题+内容+时间戳),列表/编辑/删除,一键填入 Text 节点。
- 测试。

### Task 11.3 请求统计
- 按天/provider/model 计数,7 天留存,统计面板。
- executor 发请求时记录。
- 测试:累加、留存裁剪。

---

## Phase 12 — 控制流(迭代式引擎,F15)

### Task 12.1 迭代式执行引擎
- 新建 `lib/features/execution/iterative_workflow_runner.dart`:基于待执行队列 +
  节点就绪判定,支持节点重复执行与分支跳过(不再要求无环 DAG)。
- 与现有 NodeExecutor 接口兼容;ExecutionSignals 复用。
- 测试:线性、分支、循环、最大迭代上限(防死循环)。

### Task 12.2 control-flow 节点
- ControlCondition(if/else:比较输入,激活 true/false 分支);
  ControlLoop(计数/条件循环,loop/done 分支)。
- registry + executor;连线允许回边(引擎支持)。
- 测试:条件真假、循环 N 次、循环退出。

### Task 12.3 引擎切换
- workbench 控制器在图含控制流节点时用迭代式引擎,否则用现有串行/并发引擎。
- 测试:含/不含控制流的图都跑通。

---

## Phase 13 — 媒体编辑 + 相机(裁剪绘制 + 相机节点)

### Task 13.1 图片裁剪
- 用 image 包做裁剪(自由 + 预设比例),裁剪 UI(拖拽选框)。
- 作为 ImagePreview/独立节点的编辑操作,结果存 MediaRepository。
- 测试:裁剪区域计算。

### Task 13.2 图片绘制(标注)
- 画板:笔/线/箭头/矩形 + undo,合成到图上。
- 测试:绘制操作栈。

### Task 13.3 相机控制节点
- camera-control:输入参考图 → 生成镜头 prompt 文本输出(可先做规则/模板,
  或走 TextChat 视觉)。加 `camera` 依赖如需拍照输入。
- 测试。

---

## Phase 14 — 流式响应(F21)

### Task 14.1 TextChat 流式
- ProviderClient 增 streaming 发送(SSE 解析);TextChat 增量写出。
- 节点参数 stream 开关;画布/inspector 显示增量。
- 测试:本地 HttpServer 发 SSE 分块,验证增量拼接 + 取消。

---

## Phase 15 — 收尾

### Task 15.1 全量验证 + 文档
- `flutter analyze` 干净;`flutter test` 全绿。
- README / future-features 更新已完成项;权限补充(相机)。
- 更新 future-features 文档勾掉已实现项。

---

## 阶段依赖与顺序

7(图像基建)→ 8(参考图/下载,依赖 7 的 ImageOps)→ 9(执行体验,独立)→
10(配置/健康,独立)→ 11(周边,部分依赖历史用缩略图=7)→ 12(控制流引擎)→
13(媒体编辑,依赖 7)→ 14(流式)→ 15(收尾)。

每阶段独立可测、可提交。控制流(12)风险最高,隔离在独立引擎。
