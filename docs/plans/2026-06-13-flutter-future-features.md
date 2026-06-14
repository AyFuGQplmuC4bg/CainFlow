# CainFlow Mobile — Future Features 路线图

**日期:** 2026-06-13
**基线:** 核心创作链(C 方案)已落地 —— 见
[设计方案](2026-06-13-flutter-core-creation-chain-design.md)、
[实施计划](2026-06-13-flutter-core-creation-chain-impl.md)。

本文档登记 mob 相对原版 Web 端**仍未支持**的功能,按价值与工程量分级,供后续迭代取用。已完成的能力不在此列。

---

## 已具备(基线,不在 future 范围)

仅作对照:Text / TextChat / ImageGenerate / ImageImport / ImagePreview / ImageSave
六节点、custom-params、画布编辑(增删/点选连线/表单)、openai+google+newApiImageAsync
协议、轻量多工作流、本地媒体与缩略图、持久化设置与日志。

---

## P1 — 高价值,补齐创作能力

### F1. 视频生成节点 + 视频异步协议
- **原版:** video-generate(关键帧 start/end + 3 参考图),协议 veo-unified / veo-openai / doubao-video。
- **缺口:** mob 无视频节点,`ModelTaskType.video` 仅有枚举无执行。
- **工程量:** 中-大。异步框架已具备(复用 Phase 4 的 submit→poll→resolve),主要是 3 种视频协议的请求/轮询/取结果格式各异 + 关键帧上传 + 视频预览(播放器)。
- **建议:** 先接 veo-openai(格式最接近现有 async),再按需补 veo-unified / doubao。

### F2. 辅助处理节点
- **原版:** text-merge / text-split / image-resize / image-merge / image-compare。
- **缺口:** mob 全无。
- **工程量:** text-merge/split 低(纯本地);image-resize/merge/compare 中(需本地图像解码/缩放/拼接,依赖 image 包)。
- **建议:** text 系优先(成本低、拼 prompt 常用),image 系按需求引入。

### F3. 参考图输入(ImageGenerate / TextChat 多图)
- **原版:** ImageGenerate 支持 5 张参考图 + mask;TextChat 支持 5 张视觉输入。
- **缺口:** mob 的 image 端口仅 1 个 reference,且执行器未把参考图编码进请求体。
- **工程量:** 中。端口扩展 + provider_request_builder 注入 base64/url 参考图(原版 `getOpenAiReferenceImages` 可参照)。

### F4. 远程图片下载落盘
- **缺口:** url 结果只存元数据,不下载到本地;ImageSave 对 url 仅透传。
- **工程量:** 低-中。HTTP 拉流 → MediaRepository.saveBytes。注意大图内存与失败重试。

---

## P2 — 体验与可用性

### F5. 并发执行
- **原版:** 可选并发请求模式 + 每 provider 并发计数 UI。
- **缺口:** mob 严格串行拓扑执行。
- **工程量:** 中。WorkflowRunner 改为按 DAG 层级并发,需加并发上限与取消传播。

### F6. 撤销 / 重做
- **缺口:** mob 无历史栈。
- **工程量:** 中。对 workbench signals(nodes/connections/data)做快照栈。

### F7. 拖拽连线(替代/补充点选)
- **现状:** Phase 2 用点选式连线(移动端友好)。
- **可选增强:** 桌面/平板上支持长按端口拖拽连线,提升效率。
- **工程量:** 中。手势 + 实时预览连线。

### F8. 节点类型校验与连线预览增强
- **缺口:** 连线时已有类型/环校验,但无「拖拽中高亮可连端口」等引导。
- **工程量:** 低-中。

### F9. 配置导入导出(ZIP)
- **原版:** config-archive 导出/导入 providers+models+workflows+settings 为 ZIP。
- **缺口:** mob 仅单工作流 JSON 文本导入导出。
- **工程量:** 中。archive 包打包 + 文件选择/分享(file_picker / share_plus)。

### F10. Provider 健康检查 / 拉取模型列表
- **原版:** 端点连通性探测、代理不匹配检测、从端点拉取可用模型。
- **缺口:** mob 保存前无校验。
- **工程量:** 中。

### F11. 缩略图生成服务
- **现状:** ThumbnailService 是 passthrough 空实现;画布缩略图直接读原图。
- **缺口:** 无真正的缩略图(大图列表内存压力)。
- **工程量:** 中。本地解码缩放生成缩略图文件。

---

## P3 — 周边功能模块

### F12. 历史记录
- **原版:** 执行历史侧栏(缩略图、全屏预览、按元数据筛选、导出/删除、懒加载)。
- **工程量:** 大。

### F13. Prompt 库
- **原版:** 模板保存、全屏编辑、导入导出到画布、时间戳。
- **工程量:** 中。

### F14. 请求统计
- **原版:** 按天/provider/model 统计调用,7 天留存。
- **工程量:** 中。

### F15. 控制流节点
- **原版:** control-flow(条件分支 if/else、循环)。
- **缺口:** mob 无;且当前执行引擎是无环 DAG,循环需要引擎改造。
- **工程量:** 大(引擎层改动 + 节点)。

### F16. 媒体编辑工具
- **原版:** 图片裁剪(自由/预设比例)、绘制(笔/线/箭头/形状 + undo)。
- **工程量:** 大。

### F17. 相机控制节点
- **原版:** camera-control(从参考图提取镜头 prompt)。
- **工程量:** 中。

### F18. 更新检查 / 帮助面板
- **原版:** update-manager、help-panel。
- **缺口:** 移动端发布渠道不同(应用商店),update-manager 可能不适用;help 可做成内嵌文档。
- **工程量:** 低-中。

---

## P4 — 设置与基础设施细项

### F19. 通用设置项对齐
- **原版:** 通知(声音+音量)、缓存大小、自动缩放、动画开关、更新检查间隔、图片保存命名策略、工具栏/侧栏固定。
- **缺口:** mob 设置仅 provider/model/runtime。
- **工程量:** 逐项低,累计中。按移动端实际需要挑选(部分桌面项不适用)。

### F20. 代理 / 网络设置
- **原版:** 代理 URL+鉴权、连通性探测、超时、绕过检测。
- **缺口:** mob 仅 runtime timeout。移动端代理需求通常较低。
- **工程量:** 中。

### F21. 流式响应(streaming)
- **缺口:** mob 所有响应缓冲返回,无流式。
- **工程量:** 中。TextChat 流式输出需 SSE 解析 + 增量 UI。

### F22. 工作流分组 / 文件夹
- **原版:** workflow-manager 支持文件夹组织。
- **缺口:** mob 平铺列表。
- **工程量:** 低-中。

---

## 建议迭代顺序

1. **下一里程碑(创作力):** F1 视频 → F3 参考图 → F4 远程下载 → F2(text 系)。
2. **再下一里程碑(体验):** F5 并发 → F6 撤销重做 → F11 缩略图 → F9 配置 ZIP。
3. **按需补充:** P3/P4 模块依用户反馈选取,不必整体对齐桌面版。

> 原则延续 C 方案:移动端不追求与桌面 full parity,优先「在手机上把一条创作链做顺」。
