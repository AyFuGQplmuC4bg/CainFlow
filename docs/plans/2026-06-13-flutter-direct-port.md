# Flutter Direct Port Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Port CainFlow to a native Flutter application without the Python service, using MMKV for local persistence and signals for runtime state.

**Architecture:** Flutter owns the UI, workflow state, persistence, media assets, and provider requests directly. The first milestone builds the app shell, storage/state adapters, and a usable workbench skeleton before migrating node execution.

**Tech Stack:** Flutter/Dart, MMKV, signals, direct HTTP provider adapters, local file media storage, Flutter widget/unit tests.

---

## Fixed Targets

- No Python backend dependency.
- No WebView wrapper for core functionality.
- MMKV stores structured local data: settings, workflow index, workflow JSON, session state, logs, and media indexes.
- Large media files are stored in the app documents directory, with MMKV holding only metadata and asset keys.
- signals owns reactive runtime state for workbench, workflow, selection, execution, settings, media, and logs.
- Existing CainFlow workflow JSON remains import-compatible where practical.
- Implementation proceeds in small verifiable milestones.

## Phase 1: Flutter Foundation

**Files:**
- Modify: `cain_flow_mob/pubspec.yaml`
- Replace: `cain_flow_mob/lib/main.dart`
- Create: `cain_flow_mob/lib/app/cain_flow_app.dart`
- Create: `cain_flow_mob/lib/app/theme/cain_flow_theme.dart`
- Create: `cain_flow_mob/lib/features/workbench/workbench_screen.dart`
- Create: `cain_flow_mob/lib/features/workbench/workbench_signals.dart`
- Create: `cain_flow_mob/lib/core/storage/local_kv_store.dart`
- Modify: `cain_flow_mob/test/widget_test.dart`

**Steps:**
1. Add runtime dependencies for `signals` and MMKV.
2. Replace the default counter app with the CainFlow app shell.
3. Add a restrained, dense workbench-first UI.
4. Create the first signals-backed workbench state.
5. Create an MMKV-facing storage adapter boundary.
6. Update widget tests to assert the CainFlow shell renders.
7. Run `flutter pub get`, `flutter analyze`, and `flutter test`.

**Success Criteria:**
- The Flutter app no longer shows the template counter UI.
- The first screen is a CainFlow workbench shell.
- State is exposed through signals, not setState-only app state.
- Local persistence has a dedicated adapter boundary ready for MMKV.
- Analysis and tests pass or failures are documented with exact output.

## Phase 2: Workflow Data Model

**Files:**
- Create: `cain_flow_mob/lib/core/models/workflow_document.dart`
- Create: `cain_flow_mob/lib/core/models/flow_node.dart`
- Create: `cain_flow_mob/lib/core/models/flow_connection.dart`
- Create: `cain_flow_mob/lib/features/workflow/workflow_repository.dart`
- Create: `cain_flow_mob/test/core/models/workflow_document_test.dart`

**Steps:**
1. Write tests for decoding a minimal CainFlow workflow JSON.
2. Implement models that preserve unknown node fields.
3. Implement encode/decode round-tripping.
4. Add a workflow repository using the storage adapter.
5. Verify existing-style workflow data can be imported and saved.

**Success Criteria:**
- Unknown fields survive round-trip serialization.
- Nodes, connections, canvas, and version decode reliably.
- Repository can save/load workflows without media payloads.

## Phase 3: Workbench MVP

**Files:**
- Create: `cain_flow_mob/lib/features/workbench/widgets/node_card.dart`
- Create: `cain_flow_mob/lib/features/workbench/widgets/connection_layer.dart`
- Create: `cain_flow_mob/lib/features/nodes/node_definition.dart`
- Create: `cain_flow_mob/lib/features/nodes/node_registry.dart`
- Modify: `cain_flow_mob/lib/features/workbench/workbench_screen.dart`

**Steps:**
1. Add a small Dart node registry for the first node types.
2. Render nodes from signals-backed state.
3. Add pan and zoom state.
4. Draw connection lines with `CustomPainter`.
5. Add basic node selection and movement.
6. Add tests for registry and basic controller behavior.

**Success Criteria:**
- Users can see a node graph, move nodes, and select nodes.
- Connections render independently from node widgets.
- The workbench remains usable on desktop and mobile widths.

## Phase 4: MMKV Persistence

**Files:**
- Modify: `cain_flow_mob/lib/core/storage/local_kv_store.dart`
- Create: `cain_flow_mob/lib/core/storage/mmkv_local_kv_store.dart`
- Create: `cain_flow_mob/lib/core/storage/storage_keys.dart`
- Create: `cain_flow_mob/lib/features/workflow/workflow_autosave.dart`

**Steps:**
1. Wrap MMKV behind a narrow interface.
2. Persist settings, workflow index, active workflow, and session state.
3. Add debounce autosave triggered by signals effects.
4. Add migration version key.
5. Add fake storage tests.

**Success Criteria:**
- Storage callers do not depend on MMKV APIs directly.
- Workbench state can survive app restart.
- Tests can run without native MMKV by using a fake adapter.

## Phase 5: Provider Requests Without Python

**Files:**
- Create: `cain_flow_mob/lib/core/network/provider_client.dart`
- Create: `cain_flow_mob/lib/core/network/provider_error.dart`
- Create: `cain_flow_mob/lib/features/settings/provider_settings.dart`
- Create: `cain_flow_mob/lib/features/execution/provider_request_builder.dart`

**Steps:**
1. Implement provider settings models.
2. Implement OpenAI-compatible request building.
3. Implement Gemini request building.
4. Add timeout, cancellation, and sanitized error mapping.
5. Store provider settings in MMKV.

**Success Criteria:**
- Text and image-capable provider requests can be built in Dart.
- API keys are masked in logs.
- No `/proxy` route or Python service is required.

## Phase 6: Execution Engine

**Files:**
- Create: `cain_flow_mob/lib/features/execution/execution_plan.dart`
- Create: `cain_flow_mob/lib/features/execution/workflow_runner.dart`
- Create: `cain_flow_mob/lib/features/execution/node_executor.dart`
- Create: `cain_flow_mob/lib/features/execution/execution_signals.dart`

**Steps:**
1. Write tests for dependency ordering.
2. Implement execution plans from nodes and connections.
3. Implement serial execution first.
4. Add cancellation and per-node status.
5. Add retry and branch skip behavior after serial execution is stable.

**Success Criteria:**
- Text and image generation chains execute end-to-end.
- Node status updates are signal-driven.
- Failed, canceled, skipped, and completed states are distinct.

## Phase 7: Media Assets

**Files:**
- Create: `cain_flow_mob/lib/features/media/media_repository.dart`
- Create: `cain_flow_mob/lib/features/media/media_asset.dart`
- Create: `cain_flow_mob/lib/features/media/thumbnail_service.dart`

**Steps:**
1. Store imported/generated media as app files.
2. Store only asset metadata in MMKV.
3. Generate thumbnails for previews.
4. Clean orphaned assets.
5. Add memory release points when closing workflows.

**Success Criteria:**
- Workflow JSON does not grow with embedded image/video data.
- Media previews survive restart.
- Deleting workflows can clean owned assets safely.

## Phase 8: Settings, Logs, and Release Readiness

**Files:**
- Create: `cain_flow_mob/lib/features/settings/settings_screen.dart`
- Create: `cain_flow_mob/lib/features/logs/log_signals.dart`
- Create: `cain_flow_mob/lib/features/logs/log_panel.dart`
- Modify: `cain_flow_mob/README.md`

**Steps:**
1. Add provider, model, proxy, timeout, and retry settings.
2. Add log capture and display.
3. Add import/export workflow actions.
4. Add desktop/mobile smoke checklist.
5. Run full Flutter verification.

**Success Criteria:**
- MVP users can configure providers and run a simple workflow.
- Logs explain provider and execution failures.
- The app can be tested without the Web/Python version running.
