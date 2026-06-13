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
- Concrete node executor for `Text`, `TextChat`, `ImageGenerate`, and
  `ImageSave`.
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
4. Under **Runtime**, set the request timeout and retry count, and pick the
   active chat and image models.

Settings persist through MMKV and survive app restart.

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

## Not Yet Supported

- Video generation.
- Async NewAPI-style polling.
- Downloading remote image URLs to local files.
- The full original web node set.
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
