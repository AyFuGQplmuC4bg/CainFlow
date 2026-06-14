# Mob 端相机控制 3D 视角预览设计

日期:2026-06-14
分支:feat/flutter-runnable-chain

## 背景

mob 端相机控制节点的 5D 参数(pitch/yaw/distance/fov/roll)已与 web 端对齐,
但缺少 web 端的实时视角"显示":web 用 Three.js 渲染相机所见的画面,拖拽即时变化,
并在节点卡片上保留一张当前视角缩略图。mob 端目前只有一个 2D 俯视示意图,
用户在调参时看不到效果。

目标:让用户在动态调整参数时,实时看到相机视角的真实效果,并在节点卡片上
保留当前视角缩略图。

## 关键判断

web 端 3D 场景里真正有意义的元素只有一个:**贴着上游参考图的单个平面**
(`frontPlane`),相机用 5D 参数绕它运动;背面是 `BACK` 占位面;grid/axes 是装饰。

因此**不引入任何重型 3D 引擎**(model_viewer / flutter_cube 等需要 glTF/WebView/
OpenGL 绑定,为渲染一个平面纯属浪费,且增大包体、拖慢冷启动)。

**选定方案:纯 Dart 透视投影 + `Canvas.drawVertices` 贴图。**

## 范围

本期做:
- 第一人称 3D 视角预览(画面 = 相机所见),拖拽/滑块实时联动
- 节点卡片当前视角缩略图(对齐 web 的 `cameraPreviewImage`)

本期不做(YAGNI):
- 第三人称相机模型视角、相机模型 3D 网格、观察者视角拖拽
- web 的 tainted-canvas 截图兜底

## 架构

### 1. 投影数学模块 `camera/camera_projection.dart`

与 web `applyCameraStateToCamera` 同源,纯函数、可单测。

坐标系(对齐 web):主体中心 `(0, 1.2, 0)`,平面在 XY 面、法线朝 +Z。
相机位置由球坐标:

```
pos.x = distance * cos(pitch) * sin(yaw)
pos.y = distance * sin(pitch) + 1.2
pos.z = distance * cos(pitch) * cos(yaw)
```

管线:View(lookAt + 绕视线 Z 转 roll) → Projection(fov + 宽高比) →
透视除法 → 视口像素映射。

对外:

```dart
class CameraProjection {
  CameraProjection(CameraState state, Size viewport);
  Offset projectVertex(Vector3 world);   // 世界 → 屏幕像素
  bool get subjectFacingAway;            // 法线背向相机 → 画 BACK
}
```

用 `package:vector_math`(Flutter SDK 内置传递依赖,无需新增 pubspec)做矩阵运算。

### 2. 渲染组件 `camera/camera_preview_3d.dart`

```dart
class CameraPreview3D extends StatefulWidget {
  final CameraState state;
  final ui.Image? referenceImage;   // 解码好的上游图,可空
  final ValueChanged<CameraState>? onStateChanged; // 手势回调
}
```

纹理解码放在编辑器层(异步一次),组件只画。`referenceImage == null` 画占位。

绘制(CustomPainter,远→近):
1. 地面网格线(空间纵深)
2. 主体平面:面朝相机用 `drawVertices` 把参考图细分网格(12x12)贴上;
   背向相机画深色背板 + "BACK" 文案
3. 白色边框

手势:水平拖→yaw、垂直拖→pitch、双指缩放→distance,经 onStateChanged 上抛。

性能:~288 三角形,单次 drawVertices,移动端 60fps。

### 3. 编辑器集成 `workbench/camera_editor_screen.dart`

- 用 `CameraPreview3D` 替换 `_CameraDiagram`
- `initState` 异步解码上游图 payload → ui.Image
- 单一 `_state` 真值源:滑块/手势改 `_state` → 同帧重建 3D 预览 + 数值 + prompt

### 4. 上游参考图

`workbench_screen.dart` 的 `_editCamera`:顺 `connections` 找连到本节点
`image` 端口的上游节点,取其图片 payload 传入编辑器。复刻 web `findConnectedInputImage`。
解码复用 executor 的 `_loadImageBytes`(抽为共享函数)。

### 5. 卡片快照

退出编辑器时用 `PictureRecorder` + 同一套 `CameraProjection` 离屏重绘一帧 →
`toImage()` → PNG。复用 executor `_saveImageBytes` 存为 asset 文件,
写入 `node.data['cameraPreview']`(asset 路径,非 base64,避免存档膨胀)。

卡片 `NodeCard.imagePayload`:相机节点优先取 `node.data['cameraPreview']`,
否则回退执行输出。无需改 `NodeCard`/`NodeImageThumbnail`。

## 文件清单

新增:
- `lib/features/camera/camera_projection.dart`
- `lib/features/camera/camera_preview_3d.dart`
- `test/camera_projection_test.dart`

改动:
- `lib/features/workbench/camera_editor_screen.dart`
- `lib/features/workbench/workbench_screen.dart`
- `lib/features/execution/cain_flow_node_executor.dart`(抽共享 image io)
- 上游图解析 helper

## 测试

- 单测:front(yaw=0,pitch=0)主体居中、`subjectFacingAway==false`;
  yaw=180 → `subjectFacingAway==true`;fov 增大主体变小;关键顶点坐标在合理区间
- `flutter analyze` + `flutter build`
- 手验:拖滑块画面实时变 / 拖画面滑块联动 / 无上游图占位 / 背面 BACK /
  Save 后卡片出现当前视角缩略图

## 落地顺序

1. camera_projection.dart + 单测
2. camera_preview_3d.dart 渲染
3. 编辑器集成 + 上游图 + 实时联动
4. 离屏截图 + 存 asset + 卡片缩略图
5. analyze + build + 手验
