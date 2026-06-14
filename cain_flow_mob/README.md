# CainFlow Mobile

Native Flutter port of CainFlow. The mobile app owns workflow UI, signals state,
MMKV-backed metadata, local media files, provider request construction, and the
first serial execution engine without a Python service or WebView wrapper.

## Current Scope

- Workbench-first Flutter shell with selectable and draggable graph nodes.
- Workflow JSON models with round-trip preservation for unknown fields.
- MMKV storage boundary through `LocalKvStore`.
- Autosaved workbench session snapshots.
- Direct OpenAI-compatible and Gemini request builders.
- Real `dart:io` HTTP provider client with timeout, cancellation, and a
  transient-only retry wrapper.
- Concrete node executor for `Text`, `TextChat`, `ImageGenerate`,
  `ImageImport`, `ImagePreview`, and `ImageSave`.
- Mobile-friendly graph editing: add nodes (picker), point-select connections
  with type/cycle validation, edit parameters in a bottom sheet, and delete
  nodes/connections.
- Per-node model selection and custom JSON params injected into requests.
- Async image protocol (`newApiImageAsync`): submit → poll → resolve URL, with
  configurable poll interval, timeout, and cancellation.
- Image import from the device gallery and on-canvas thumbnails (local files via
  `Image.file`, remote URLs via `cached_network_image`).
- Lightweight multi-workflow management: create, switch, rename, delete.
- Run/Stop wired to the real serial workflow runner with canvas and inspector
  status.
- Local media repository that stores bytes as app files and keeps only metadata
  in MMKV.
- Editable provider/model settings and persisted, sanitized logs.

## Configure A Provider

1. Open Settings (gear icon in the AppBar).
2. Under **Providers**, tap **Add provider** and fill in name, endpoint, API
   key, and protocol (`openai` or `google`). The API key is masked everywhere
   except the edit dialog.
3. Under **Models**, tap **Add model** and set name, model ID, task type
   (`chat` or `image`), protocol, and the provider binding.
4. Under **Runtime**, set the request timeout and retry count, the async poll
   interval and timeout (for `newApiImageAsync` models), and pick the active
   chat and image models.

Settings persist through MMKV and survive app restart.

## Edit A Graph On Device

- **Add node**: use the **Add node** button in the Workflows rail, or long-press
  empty canvas, then pick a node type.
- **Connect**: tap an output port (it highlights), then tap a compatible input
  port. Type mismatches, self-connections, and cycles are rejected with a
  toast. A new edge replaces an existing one on the same input port.
- **Edit parameters**: tap a node to open its bottom-sheet form. Fields are
  driven by the node definition (text, multiline, number, select, model picker,
  custom JSON params, image picker).
- **Delete**: the node sheet has a delete action; connections are removed by
  re-wiring their input port.

## Build A Creation Chain

The core node set covers a text/image creation chain:

- `Text` → static prompt text.
- `TextChat` → chat completion (OpenAI-compatible or Gemini), with optional
  system prompt and custom params.
- `ImageImport` → pick a local image; stored via `MediaRepository`.
- `ImageGenerate` → text-to-image; supports the async protocol below.
- `ImagePreview` → passes its input image through and renders a canvas
  thumbnail.
- `ImageSave` → persists base64 bytes locally or keeps URL metadata.

## Async Image Models (`newApiImageAsync`)

For providers that return a task id instead of an inline image:

1. Add a provider/model with protocol `newApiImageAsync`.
2. `ImageGenerate` submits the task, then polls status on the configured
   interval until `completed`/`failed` or the timeout elapses.
3. Pressing **Stop** cancels polling between attempts.

## Manage Workflows

The Workflows rail lists saved workflows. Use **New workflow** to start an empty
graph, tap a saved entry to switch (the current graph is flushed first), and
long-press an entry to rename or delete it. Deleting a workflow cleans up its
orphaned media.

## Run A Workflow (No Python)

1. The default graph is `Text -> ImageGenerate -> ImageSave`. For a chat-only
   run, import a `Text -> TextChat` graph (see below).
2. Press **Run** in the AppBar. The workbench converts the visible graph to a
   `WorkflowDocument` and executes it serially:
   - `Text` emits prompt text.
   - `TextChat` / `ImageGenerate` build a provider request and send it directly
     from Dart.
   - `ImageSave` persists base64 image bytes through `MediaRepository`, or keeps
     URL metadata without downloading.
3. Watch the canvas status chip (Ready / Running / Completed / Failed /
   Canceled) and the per-node status in the inspector.
4. Press **Stop** to cancel an in-flight run.

## Import / Export Workflows

- In Settings under **Workflow JSON**, press **Export graph** to dump the
  current workbench graph as JSON.
- Paste workflow JSON into the import field and press **Import into workbench**
  to validate, load it into the canvas, and save it through the repository.
  Invalid JSON shows an inline error and is logged.

## Platform Permissions

`ImageImport` uses the device photo library:

- **Android**: `READ_MEDIA_IMAGES` is declared in the manifest (Android 13+
  uses the system Photo Picker, which needs no runtime grant).
- **iOS**: `NSPhotoLibraryUsageDescription` is set in `Info.plist`.

## Not Yet Supported

- Video generation and video async protocols (veo / doubao).
- Control-flow nodes (condition / loop).
- Statistics, prompt library, history, and help panels.
- Image cropping / painting.
- `text-merge` / `text-split` / `image-resize` / `image-merge` /
  `image-compare` nodes.
- Config ZIP import/export, provider health checks, parallel execution, and
  undo/redo.
- Embedding media payloads inside workflow JSON.

## Verify

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:APPDATA='F:\code\CainFlow\.dart_appdata'
$env:DART_SUPPRESS_ANALYTICS='true'
$env:FLUTTER_SUPPRESS_ANALYTICS='true'
flutter analyze
flutter test --reporter expanded
```
