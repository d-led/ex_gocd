# VSM (Value Stream Map) — Feature Parity Plan

> **⚠️ SUPERSEDED** — VSM is complete. See `docs/comprehensive_parity_plan.md` for current state.

*Generated 2026-06-21. Kept for historical reference.*

## GoCD VSM Reference

GoCD renders an interactive D3.js force-directed graph. Key features:
- Material nodes (SCM triggers) on the left
- Pipeline nodes (with stage statuses) in center/right
- Directed edges showing dependency flow (material→pipeline, upstream→downstream)
- Fan-in: diamond dependency detector — marks nodes where multiple upstreams converge
- Fan-out: marks pipelines that trigger multiple downstreams
- Node colors: green=Passed, red=Failed, yellow=Building, grey=Unknown/NotRun
- Trigger info panel on hover: who triggered, when, what materials were used
- Clickable nodes: drill down to pipeline counter → stage details
- Pipeline activity page links to VSM for each run

## Current ex_gocd State

| Component | Status |
|-----------|--------|
| Data layer (`ValueStreamMap`) | ✅ Builds levels, nodes, parents, dependents, instances |
| API endpoints (JSON) | ✅ Pipeline + Material VSM, `.json` format rewrite |
| LiveView page | ✅ Basic page with SVG connectors |
| JS VSMGraph hook | ✅ SVG line drawing between nodes |
| Router entries | ✅ Both `/go/` and non-prefixed paths |
| Links from pipeline activity | ✅ "VSM" button per counter |
| Links from stage details | ✅ Pipeline counter links to VSM |
| Fan-in detection | ✅ `count_fan_in/1` — counts upstream pipelines |
| Fan-out marking | ✅ `fan_out` from `length(downstream_names)` |
| Trigger attribution | ✅ `trigger_info`: triggered_by, triggered_at, materials |
| Material revision details | ❌ No clickable commit links |
| Stage status colors | ⚠️ Partial — needs passed/failed/building on VSM nodes |
| Dashboard → VSM link | ❌ No VSM link from pipeline cards |
| Professional visual styling | ❌ Basic SVG, no D3 interaction |

## Implementation Plan

### Phase 1: Data Layer (server side)
- [x] `ValueStreamMap` — add trigger attribution (who, when, material revisions) per instance
- [x] `ValueStreamMap` — mark fan-in nodes (count incoming parents > 1)
- [x] `ValueStreamMap` — mark fan-out nodes (count non-empty dependents > 1)
- [x] Add `trigger_info` to each pipeline instance in VSM JSON

### Phase 2: API
- [x] Ensure `/api/pipelines/value_stream_map/:name/:counter.json` returns enriched data (inline in build_db_pipeline_vsm)

### Phase 3: UI Rendering
- [x] VSM node cards: pipeline name, counter, stage statuses with colors
- [x] Material node cards: repo URL, branch, latest revision
- [x] Trigger info panel with triggered_by, triggered_at, materials
- [x] Fan-in (FI) and Fan-out (FO) badges on pipeline nodes
- [x] Trigger info panel with triggered_by, triggered_at, materials
- [x] Fan-in (FI) and Fan-out (FO) badges on pipeline nodes
- [x] Clickable pipeline nodes → `/pipelines/value_stream_map/:name/:counter`
- [x] Clickable material nodes → `/materials/value_stream_map/:fp/:rev`
- [x] Material revision → clickable to `modifications` page

### Phase 4: Integration
- [x] Dashboard pipeline card: VSM link per pipeline instance (already existed)
- [x] Stage details page: "View in VSM" via breadcrumb counter link (already existed)
- [x] Pipeline activity: VSM button per counter (already existed)
- [x] Breadcrumbs on VSM page: Pipelines > pipeline > counter > VSM

### Phase 5: Polish
- [x] Responsive: mobile-friendly padding, stacked layout, flexible widths
- [x] Accessibility: aria-labels on all graph nodes (status_dot_label)
- [x] Cypress E2E test for VSM flow (`cypress/e2e/vsm.cy.js`)
