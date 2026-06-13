# Flutter Minimum Runnable Chain Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn the current Flutter port from an MVP scaffold into a runnable local workflow that can execute `Text -> TextChat/ImageGenerate -> ImageSave` without Python or WebView.

**Architecture:** Keep the existing boundaries: MMKV remains behind `LocalKvStore`, runtime state remains signal-driven, and provider calls remain direct Dart requests. Add the smallest missing production path: editable provider settings, real HTTP provider client, concrete node executor, persisted logs, and workbench Run wiring.

**Tech Stack:** Flutter/Dart, `signals`, `mmkv`, `path_provider`, `dart:io` HTTP, local files, Flutter unit/widget tests.

---

## Current Baseline

- `flutter analyze` passes.
- `flutter test --reporter expanded` passes with 24 tests.
- Existing implemented skeletons:
  - workflow JSON models and repository
  - MMKV storage adapter boundary
  - workbench graph UI and signals
  - provider request builders for OpenAI-compatible and Gemini
  - execution plan and serial workflow runner
  - media asset repository
  - logs panel and settings panel
- Known gaps:
  - no real HTTP provider client
  - no concrete node executor for `Text`, `TextChat`, `ImageGenerate`, `ImageSave`
  - Run button does not call `WorkflowRunner`
  - settings page is mostly read-only
  - logs are not persisted to MMKV
  - retry policy and request timeout are not user-configurable
  - thumbnails are passthrough placeholders

## Non-Goals For This Plan

- Do not add video generation.
- Do not add async NewAPI-style polling.
- Do not implement every original web node.
- Do not introduce a Python service.
- Do not add WebView.
- Do not embed media payloads into workflow JSON.

## Target User Flow

1. User opens Flutter app.
2. User configures one provider and one model in Settings.
3. User runs the default graph or an imported simple graph.
4. `Text` emits prompt text.
5. `TextChat` or `ImageGenerate` builds a provider request and sends it directly from Dart.
6. Text/image response is stored in node outputs.
7. `ImageSave` stores generated image bytes or image URL metadata through `MediaRepository`.
8. Logs show request lifecycle and sanitized failures.

---

## Phase A: Settings That Can Drive Execution

### Task A1: Add Runtime Settings Model

**Files:**
- Modify: `cain_flow_mob/lib/features/settings/provider_settings.dart`
- Test: `cain_flow_mob/test/features/settings/provider_settings_test.dart`

**Steps:**
1. Add `RuntimeSettings` with:
   - `requestTimeoutSeconds`
   - `retryCount`
   - `activeChatModelId`
   - `activeImageModelId`
2. Add it to `ProviderSettings`.
3. Preserve backward compatibility when JSON has no `runtime`.
4. Add tests for default values and round-trip persistence.
5. Run:
   ```powershell
   flutter test test/features/settings/provider_settings_test.dart --reporter expanded
   ```

**Success Criteria:**
- Provider settings can define timeout, retry, and active model selection.
- Existing provider settings JSON still loads.

### Task A2: Make Settings Screen Editable

**Files:**
- Modify: `cain_flow_mob/lib/features/settings/settings_screen.dart`
- Test: `cain_flow_mob/test/features/settings/settings_screen_test.dart`

**Steps:**
1. Add text fields for provider name, endpoint, API key, and protocol.
2. Add text fields/dropdowns for model name, model ID, task type, protocol, and provider binding.
3. Add timeout and retry numeric controls.
4. Save edits through `ProviderSettingsRepository`.
5. Mask API key in read-only summaries.
6. Add widget tests for editing and saving a provider/model.

**Success Criteria:**
- A user can configure at least one OpenAI-compatible or Google provider in-app.
- Settings survive reload through the repository.

---

## Phase B: Real Provider HTTP Client

### Task B1: Implement Cancellable Provider Client

**Files:**
- Modify: `cain_flow_mob/lib/core/network/provider_client.dart`
- Test: `cain_flow_mob/test/core/network/provider_client_test.dart`

**Steps:**
1. Add `ProviderRequestOptions` with timeout and cancellation token.
2. Add `ProviderCancellationToken` with `cancel()` and `isCanceled`.
3. Implement `DartIoProviderClient` using `dart:io` `HttpClient`.
4. Encode request body as JSON.
5. Decode response body as UTF-8.
6. Close the underlying request/client when canceled where possible.
7. Map timeout and cancellation to sanitized `ProviderError`.
8. Add tests using a local `HttpServer`.

**Success Criteria:**
- Direct Dart HTTP requests work without `/proxy`.
- Timeout and cancellation are represented distinctly.
- Authorization headers and URL keys are never exposed in error output.

### Task B2: Add Retry Wrapper

**Files:**
- Create: `cain_flow_mob/lib/core/network/retrying_provider_client.dart`
- Test: `cain_flow_mob/test/core/network/retrying_provider_client_test.dart`

**Steps:**
1. Create a wrapper around `ProviderClient`.
2. Retry only transient categories:
   - timeout
   - rate limit
   - server
3. Do not retry auth, forbidden, model not found, or invalid request.
4. Respect cancellation before every retry.
5. Add tests for retry count and non-retryable errors.

**Success Criteria:**
- Retry behavior is deterministic and test-covered.
- Retry count can later be driven by settings.

---

## Phase C: Concrete Node Executor

### Task C1: Add Execution Context Services

**Files:**
- Create: `cain_flow_mob/lib/features/execution/execution_services.dart`
- Modify: `cain_flow_mob/lib/features/execution/node_executor.dart`
- Test: `cain_flow_mob/test/features/execution/node_executor_test.dart`

**Steps:**
1. Add `ExecutionServices` containing:
   - `ProviderSettingsRepository`
   - `ProviderClient`
   - `MediaRepository`
   - `LogSignals`
2. Pass services into the concrete executor constructor.
3. Keep `WorkflowRunner` independent from services.

**Success Criteria:**
- Runner stays orchestration-only.
- Concrete node behavior can access provider settings, network, media, and logs.

### Task C2: Implement Text Node Execution

**Files:**
- Create: `cain_flow_mob/lib/features/execution/cain_flow_node_executor.dart`
- Test: `cain_flow_mob/test/features/execution/cain_flow_node_executor_test.dart`

**Steps:**
1. Implement `Text` node:
   - read `data.text`
   - fallback to top-level `extra.text`
   - output `{ "text": value }`
2. Add tests for both current `data` and legacy top-level values.

**Success Criteria:**
- Prompt nodes produce text output without network.

### Task C3: Implement TextChat Node Execution

**Files:**
- Modify: `cain_flow_mob/lib/features/execution/cain_flow_node_executor.dart`
- Test: `cain_flow_mob/test/features/execution/cain_flow_node_executor_test.dart`

**Steps:**
1. Resolve model from node `data.apiConfigId`, `extra.apiConfigId`, or runtime active chat model.
2. Resolve provider from node `data.providerId`, `extra.providerId`, or model provider IDs.
3. Build request through `ProviderRequestBuilder.buildChatRequest`.
4. Send through `ProviderClient`.
5. Parse OpenAI-compatible text from `choices[0].message.content`.
6. Parse Gemini text from `candidates[0].content.parts[].text`.
7. Output `{ "text": parsedText }`.
8. Log request start, success, and sanitized failure.

**Success Criteria:**
- `Text -> TextChat` can run in tests with a fake provider client.

### Task C4: Implement ImageGenerate Node Execution

**Files:**
- Modify: `cain_flow_mob/lib/features/execution/cain_flow_node_executor.dart`
- Test: `cain_flow_mob/test/features/execution/cain_flow_node_executor_test.dart`

**Steps:**
1. Resolve prompt from input `prompt`, node `data.prompt`, or `extra.prompt`.
2. Resolve model/provider like `TextChat`, using active image model fallback.
3. Build image request through `ProviderRequestBuilder.buildImageRequest`.
4. Parse OpenAI-style image URL or base64 JSON.
5. Parse Gemini image part if present.
6. For base64 image data, save bytes through `MediaRepository`.
7. For URL-only response, output URL metadata without downloading in this task.
8. Output `{ "image": imagePayload }`.

**Success Criteria:**
- `Text -> ImageGenerate` can run with fake provider responses.
- Base64 image results are stored as local media assets.

### Task C5: Implement ImageSave Node Execution

**Files:**
- Modify: `cain_flow_mob/lib/features/execution/cain_flow_node_executor.dart`
- Test: `cain_flow_mob/test/features/execution/cain_flow_node_executor_test.dart`

**Steps:**
1. Read image input from `inputs["image"]`.
2. If input is a local `MediaAsset` payload, pass it through.
3. If input is base64 bytes, save it through `MediaRepository`.
4. If input is URL metadata, store metadata in outputs without downloading.
5. Output `{ "image": savedPayload }`.

**Success Criteria:**
- `ImageGenerate -> ImageSave` has a concrete local persistence path.

---

## Phase D: Wire Run Button To Execution

### Task D1: Convert Workbench Session To Workflow Document

**Files:**
- Create: `cain_flow_mob/lib/features/workbench/workbench_workflow_mapper.dart`
- Test: `cain_flow_mob/test/features/workbench/workbench_workflow_mapper_test.dart`

**Steps:**
1. Map `WorkbenchNode` to `FlowNode`.
2. Map `WorkbenchConnection` to `FlowConnection`.
3. Preserve node type, position, title, and port names.
4. Add tests for the default graph.

**Success Criteria:**
- Current visible graph can be passed to `WorkflowRunner`.

### Task D2: Add Workbench Execution Controller

**Files:**
- Create: `cain_flow_mob/lib/features/workbench/workbench_execution_controller.dart`
- Modify: `cain_flow_mob/lib/features/workbench/workbench_screen.dart`
- Test: `cain_flow_mob/test/features/workbench/workbench_execution_controller_test.dart`

**Steps:**
1. Create controller that owns:
   - `ExecutionSignals`
   - `WorkflowRunner`
   - cancellation token
2. On Run:
   - build workflow from workbench signals
   - start runner
   - update workbench run state
3. On Stop:
   - cancel runner
   - update workbench run state
4. Write logs for run start, completion, failure, and cancellation.
5. Add tests with fake executor.

**Success Criteria:**
- AppBar Run invokes the real runner path.
- Stop cancels active execution.

---

## Phase E: Persist Logs And Improve Failure Visibility

### Task E1: Persist Log Ring To LocalKvStore

**Files:**
- Modify: `cain_flow_mob/lib/features/logs/log_signals.dart`
- Create: `cain_flow_mob/lib/features/logs/log_repository.dart`
- Test: `cain_flow_mob/test/features/logs/log_repository_test.dart`

**Steps:**
1. Add JSON serialization for `LogEntry`.
2. Add `LogRepository` using `StorageKeys.logRing`.
3. Add load/save methods.
4. Keep ring buffer capacity at 200.
5. Test round-trip and malformed JSON fallback.

**Success Criteria:**
- Logs survive app restart.
- Logs remain sanitized.

### Task E2: Show Execution Status In Inspector

**Files:**
- Modify: `cain_flow_mob/lib/features/workbench/workbench_screen.dart`
- Test: `cain_flow_mob/test/widget_test.dart`

**Steps:**
1. Show active execution state in the canvas status chip.
2. Show selected node execution state in the inspector.
3. Add tests for status labels using injected/fake controller where practical.

**Success Criteria:**
- Users can see failed, canceled, skipped, running, and completed states.

---

## Phase F: Import/Export Workflow For Real

### Task F1: Add Text-Based Import/Export Dialog

**Files:**
- Modify: `cain_flow_mob/lib/features/settings/settings_screen.dart`
- Modify: `cain_flow_mob/lib/features/workflow/workflow_archive.dart`
- Test: `cain_flow_mob/test/features/settings/settings_screen_test.dart`

**Steps:**
1. Replace sample-only export with export of current workbench graph.
2. Add multiline JSON input for import.
3. Validate JSON before applying.
4. On import, update workbench signals.
5. Save imported workflow through repository.
6. Log success or sanitized failure.

**Success Criteria:**
- Users can paste workflow JSON and load it into the workbench.
- Users can export the current graph JSON.

---

## Phase G: Verification And Smoke Checklist

### Task G1: Full Flutter Verification

**Files:**
- Modify: `cain_flow_mob/README.md`

**Steps:**
1. Run:
   ```powershell
   flutter analyze
   ```
2. Run:
   ```powershell
   flutter test --reporter expanded
   ```
3. Update README with:
   - provider setup steps
   - run workflow steps
   - import/export steps
   - known unsupported features

**Success Criteria:**
- Analysis is clean.
- Tests pass.
- README describes how to run a simple workflow without Python.

### Task G2: Manual Smoke Checklist

**Manual Checks:**
- Launch app on desktop.
- Open Settings.
- Add provider and model.
- Run `Text -> TextChat`.
- Run `Text -> ImageGenerate -> ImageSave` with fake/test provider where real credentials are unavailable.
- Stop a running workflow.
- Confirm logs show sanitized errors.
- Restart app and confirm settings/logs/media metadata persist.

**Success Criteria:**
- The Flutter app demonstrates a real no-Python execution path.

