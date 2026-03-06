# PRD: Canvas Third Tab - UI Builder Plane

## Document Status
- Status: Draft v0.1
- Author: AI assistant (for initial draft)
- Date: 2026-03-06

## Problem Statement
Today, the canvas page appears optimized for building and running workflow logic, but it lacks a lightweight, user-facing interaction layer for manual operations. Teams need a simple way to expose controls (buttons, basic content, status values) without building a separate frontend.

We need a third tab on the canvas page that allows users to build a minimal UI surface directly in canvas. This surface should support markdown, tables, and buttons. Button clicks should trigger manual runs on the current canvas and support dynamic values via memory.

## Goals
- Add a third tab on canvas dedicated to a simple, embeddable UI.
- Provide UI blocks for:
  - Markdown
  - Tables
  - Buttons
- Allow button actions to trigger manual runs on the associated canvas.
- Enable dynamic values through memory reads/writes so UI content can change over time.
- Keep authoring and runtime experience simple enough for non-frontend users.

## Non-Goals
- Building a full low-code app builder or general-purpose form engine.
- Supporting arbitrary custom HTML/CSS/JS.
- Creating complex component types beyond markdown/tables/buttons in v1.
- Replacing existing canvas tabs or execution views.
- Multi-page navigation or routing in v1.

## Target Users
- Canvas builders who want lightweight operator controls.
- Internal operators who need "click-to-run" actions with visible context.
- Technical users who want dynamic, memory-backed status displays.

## Primary Use Cases
1. **Runbook buttons**
   - Operator clicks "Re-sync" or "Restart job" button.
   - Canvas starts a manual run with optional payload.
2. **Status dashboard**
   - Markdown + table renders memory-driven values (last run time, error count, queue depth).
3. **Guided operations**
   - Markdown provides instructions, buttons perform actions, table confirms results.

## UX Overview
### Information Architecture
- Add a new third tab on canvas page (working name: `UI`).
- Tab has two sub-modes:
  - **Build mode**: arrange/edit blocks and wire button actions.
  - **Preview mode**: interact with the rendered UI as an end user.

### UI Block Types (v1)
1. **Markdown block**
   - Author raw markdown.
   - Supports interpolation from memory (e.g., `{{memory.last_status}}`).
2. **Table block**
   - Define columns and source data from memory path(s).
   - Render simple rows (string/number/boolean values in v1).
3. **Button block**
   - Label, optional style variant, optional confirmation text.
   - On click, triggers manual run for current canvas.
   - Can pass payload generated from static values plus memory interpolation.

### Authoring Experience
- Add/delete/reorder blocks in a vertical list.
- Inline block config panels.
- Basic validation with clear, actionable errors.
- Save updates together with canvas metadata.

### Runtime Experience
- Render blocks in configured order.
- Button press shows pending/success/error state.
- Manual run result reference visible (run ID + link to execution details).

## Functional Requirements
### FR1: Third Tab Presence
- System must render a third tab on the canvas page for UI builder.
- Tab availability controlled by feature flag in v1 rollout.

### FR2: UI Definition Storage
- System must persist a per-canvas UI definition (schema-based JSON).
- UI definition includes version field for future migration.

### FR3: Markdown Rendering
- System must render markdown safely (sanitized output).
- System must support memory interpolation for markdown content.
- If interpolation path is missing, system should render fallback placeholder and log warning.

### FR4: Table Rendering
- System must render tables with configured columns and memory-backed data source.
- System must handle empty data gracefully (empty state message).
- System must reject unsupported nested object render in v1 with clear error.

### FR5: Button to Manual Run
- Clicking a button must trigger a manual run of the current canvas.
- Button config supports:
  - Static payload
  - Memory-interpolated payload
  - Optional confirmation prompt
- System must protect against double-submit (disable while request pending).

### FR6: Memory Read/Write Integration
- UI blocks can read memory values at render-time.
- Button action can write to memory before and/or after run trigger (optional hooks in v1.1; defer if needed).
- Memory operations must be scoped to current canvas context.

### FR7: Permissions and Security
- Only authorized users can edit UI definitions.
- Users without run permission can view UI but cannot trigger button actions.
- Markdown and interpolation must prevent script injection.
- Manual run endpoints must retain existing authz checks.

### FR8: Observability
- Emit events for:
  - UI tab viewed
  - Button clicked
  - Manual run requested
  - Manual run request outcome
- Include canvas ID, block ID, user ID (where policy permits), request ID.

## Data Model (Draft)
```json
{
  "version": 1,
  "blocks": [
    {
      "id": "blk_1",
      "type": "markdown",
      "config": {
        "content": "## Status\nLast run: {{memory.last_run_at}}"
      }
    },
    {
      "id": "blk_2",
      "type": "table",
      "config": {
        "columns": [
          { "key": "name", "label": "Name" },
          { "key": "value", "label": "Value" }
        ],
        "rowsPath": "memory.metrics_rows",
        "emptyMessage": "No metrics yet"
      }
    },
    {
      "id": "blk_3",
      "type": "button",
      "config": {
        "label": "Run Sync",
        "variant": "primary",
        "confirmText": "Run sync now?",
        "action": {
          "type": "manual_run",
          "payloadTemplate": {
            "mode": "sync",
            "requestedBy": "{{memory.current_user}}"
          }
        }
      }
    }
  ]
}
```

## API / Backend Requirements (Draft)
- Add API field on canvas resource for `ui_definition`.
- Add validation endpoint or shared schema validation on save.
- Reuse existing manual run endpoint for button actions.
- Add interpolation and memory-resolver service in UI-render path (or backend-prepared payload path).

## Performance Requirements
- UI tab initial load should be comparable to existing canvas tabs.
- Button click to manual run request acknowledgment target: under 1 second p95 (excluding run completion).
- Rendering should degrade gracefully with large tables (define soft row cap in v1).

## Accessibility Requirements
- Keyboard accessible tab navigation and buttons.
- Screen-reader labels for block actions and state changes.
- Sufficient contrast for button variants and table text.

## Risks & Mitigations
- **Risk:** Unsafe markdown/interpolation output.
  - **Mitigation:** Strict sanitization + escaped rendering by default.
- **Risk:** Confusion between build and preview modes.
  - **Mitigation:** explicit mode toggle and visual distinction.
- **Risk:** Memory schema inconsistency causing broken UI.
  - **Mitigation:** validation helpers + inline error indicators + preview diagnostics.
- **Risk:** Repeated clicks causing duplicate runs.
  - **Mitigation:** pending lock and idempotency key support where available.

## Rollout Plan
1. Feature flag behind internal/staff tenants.
2. Pilot with selected canvases.
3. Observe button-run reliability, UX friction, and schema breakages.
4. Expand gradually; publish quickstart examples.

## Success Metrics
- % of canvases with UI tab configured.
- Weekly active users interacting with UI tab.
- Button click -> manual run success rate.
- Median setup time for first working button.
- Reduction in need for separate ad-hoc operator scripts/pages.

## Open Questions
1. Should memory writes from button actions be included in v1 or deferred to v1.1?
2. Is table source limited to array-of-objects only in v1?
3. Do we need per-button role restrictions beyond existing run permissions?
4. Should "preview mode" be viewable by users without edit permission by default?
5. Where should interpolation execute (frontend only, backend only, or hybrid)?
6. Should button actions support post-run polling and status badges in v1?

## Out of Scope (Explicitly Deferred)
- Rich input components (text fields, dropdowns, date pickers).
- Conditional visibility rules between components.
- Multi-step forms and client-side workflow logic.
- External API calls directly from UI blocks.

## Next Step Suggestions
- Convert this PRD into:
  1. technical design doc (architecture + schema + APIs),
  2. UX wireframes for Build/Preview mode,
  3. implementation milestones and test plan.
