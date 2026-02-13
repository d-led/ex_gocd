# GoCD CSS/HTML Conversion Plan

## Goal

Nearly pixel-perfect rewrite of GoCD UI in Phoenix LiveView by converting GoCD's SCSS/CSS and HTML structure with maximum automation, minimal JavaScript (phx-hooks only where needed).

## Why the Previous Script Failed

`scripts/convert_gocd_css.sh` runs a Node converter that compiles all `**/*.scss` under `gocd/server/.../new_stylesheets`. It fails because:

1. **Root bundle**: `frameworks.scss` is processed first (or in arbitrary order); it `@import`s Rails-specific files that don't exist in that tree: `foundation_and_overrides`, `bourbon/core/bourbon`, `font-awesome-glyphs` (Rails/ERB).
2. **Deep dependency chain**: `single_page_apps/new_dashboard.scss` → `shared/common` → `shared/mixins` → Foundation, Bourbon, Font Awesome glyphs. So even compiling only dashboard pulls in Rails/framework deps.

## Strategy

### 1. Entry-point conversion (not glob-all)

- **Do not** compile every `.scss` file. Compile only **entry points** we care about:
  - `single_page_apps/new_dashboard.scss` → `dashboard.css`
  - `single_page_apps/agents.scss` → `agents.css`
  - Optionally: shared/header as a separate entry for site_header (or it comes in via dashboard).
- Each entry is compiled with Sass; imports are resolved. Output one CSS file per entry.

### 2. Stubs for missing Rails/framework deps

Place stub files in `tools/converter/stubs/` so that Sass resolution finds them instead of the missing Rails assets:

| Stub | Purpose |
|------|--------|
| `foundation_and_overrides.scss` | Empty; satisfies `@import "foundation_and_overrides"` in frameworks. We don't compile frameworks; kept for any entry that might pull it. |
| `_font-awesome-glyphs.scss` | Empty; satisfies shared/mixins and any file that expects FA glyph mixins. |
| `_font-awesome-sprockets.scss` | Empty; satisfies `@import "font-awesome-sprockets"` in new_dashboard. |
| `shared/_mixins.scss` | **Critical.** Replaces the original shared/mixins that imports Foundation/Bourbon/FA. Defines: `rem-calc`, `image-url` (Rails helpers), `animation`, `truncate-to-lines`, `commit-message`, `sort-cursor`, `grip-icon`, `unselectable`, and **stub** `icon-before` / `icon-after` (output minimal CSS so layout compiles; real icons can be added in ex_gocd via Heroicons/FA later). Imports only: go-variables, variables, settings (from source), and Bourbon (from node_modules) for `ellipsis`, `clearfix`. |

Stub load path is prepended so our stubs override the real files where we want (e.g. shared/mixins).

### 3. Source paths

- **Primary**: `gocd/server/src/main/webapp/WEB-INF/rails/app/assets/new_stylesheets` (dashboard, agents, shared, components).
- **Optional later**: `gocd/server/.../webpack/views/global` (theme, variables, measures) for additional standalone SCSS if we want to align with the React/TS build.

### 4. Post-process

- Run **PostCSS + Autoprefixer** on compiled CSS (already in converter).
- Optionally: replace `url("/images/...")` from stubbed `image-url` with Phoenix asset paths if we need correct asset URLs.

### 5. Integration in ex_gocd

- Converter output goes to `assets/css/gocd/` (e.g. `dashboard.css`, `agents.css`).
- `app.css` (Tailwind) already `@import`s `./gocd/site_header.css`, `./gocd/dropdown.css`, `./gocd/dashboard.css`, `./agents.css`, `./agent_job_history.css`. After conversion, we can replace hand-maintained dashboard/agents CSS with converted output and fix any remaining differences (e.g. logo URL, icon placeholders).

## Tooling

- **Current**: Node script `tools/converter/css-convert.js` + `scripts/convert_gocd_css.sh`.
- **Changes**:
  - Converter: support **entry-point mode** (only compile given files; output path derived from entry name).
  - Converter: **exclude** `frameworks.scss` when using glob; when using entry points, do not glob.
  - Add **stubs** under `tools/converter/stubs/` and prepend to Sass `loadPaths`.
  - Add **bourbon** to `package.json` (for ellipsis, clearfix in stub mixins).
  - Define **rem-calc** and **image-url** in stub mixins so that shared/header and shared/common compile without Rails/Foundation.

## HTML / LiveView

- Keep matching GoCD's DOM structure and class names so converted CSS applies without change (see rewrite.md "Component Mapping").
- Prefer LiveView and `phx-*` over custom JS; use phx-hooks only where necessary (e.g. dropdown close on outside click already done in LiveView).

## Test coverage (GoCD-aligned)

Tests in `test/mix/tasks/convert_gocd_css_test.exs` are specified to match GoCD’s behaviour:

- **GoCD spec**: `WebpackAssetsServiceTest.shouldGetCSSAssetPathsFromManifestJson` expects CSS for entry points `single_page_apps/agents` and `single_page_apps/new_dashboard` → `agents.css`, `new_dashboard.css`. Our converter uses the same entry points and output basenames.
- **Tests**: (1) Entry-point mode produces exactly those two CSS files. (2) Compiled output contains expanded variables and header comment. (3) Idempotency: second run yields the same output set. (4) Missing entry point causes non-zero exit.

When adding or removing entry points, update `ENTRY_POINT_OUTPUT_BASENAMES` and `ENTRY_TO_OUTPUT_BASENAME` in `css-convert.js`, `@gocd_entry_points` in the Mix task, and `convert_gocd_css.sh` ENTRIES so script, Mix task, and tests stay in sync. Output names: `new_dashboard.scss` → `dashboard.css`, `agents.scss` → `agents.css` (for app imports).

## Checked-in converted CSS (see if anything changes)

Converted CSS is committed under `assets/css/gocd/`:

- `dashboard.css` — from `single_page_apps/new_dashboard.scss`
- `agents.css` — from `single_page_apps/agents.scss`

`app.css` imports these via `./gocd/dashboard.css` and `./gocd/agents.css`.

**To see if conversion output changed** (e.g. after a GoCD or converter update):

1. Run conversion (fixtures or real GoCD source):
   - `mix convert.gocd.css` → uses fixtures, writes to `assets/css/gocd`
   - `mix convert.gocd.css /path/to/gocd/.../new_stylesheets` → uses real GoCD SCSS
   - Or `./scripts/convert_gocd_css.sh` (defaults to gocd repo path and shows git diff)
2. Run `git diff assets/css/gocd` (or `git diff -- assets/css/gocd/dashboard.css assets/css/gocd/agents.css`).
3. If there are changes, review and commit the updated CSS.

So we can always diff converted output against the last committed version.

## Success criteria

- `./scripts/convert_gocd_css.sh` runs without error.
- Output CSS in `assets/css/gocd/` can be imported and dashboard/agents pages render with correct layout and colors; icons may be placeholders until we add Heroicons/FA.
- Side-by-side with GoCD at same breakpoints: same structure, spacing, colors, typography (nearly pixel-perfect).

## References

- [rewrite.md](./rewrite.md) – Design and Styling Approach, Component Mapping.
- [prioritization.md](./prioritization.md) – Phase 1 (Dashboard UI) complete; CSS conversion supports ongoing pixel fidelity.
- GoCD new_stylesheets: `gocd/server/src/main/webapp/WEB-INF/rails/app/assets/new_stylesheets/`.
