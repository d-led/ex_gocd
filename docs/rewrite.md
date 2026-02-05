# Plan

## Motivation

- GoCD is an outstanding Continuous Delivery server with outstanding language, concepts and implementation, yet the stack is somewhat outdated.

## Design and Styling Approach

### Core Principle: Visual Fidelity to GoCD

We maintain pixel-level fidelity to the original GoCD UI. This is a rewrite, not a redesign. Users should feel immediately at home.

### CSS Strategy

**Direct conversion from GoCD source**:
- Copy SCSS files from `gocd/server/src/main/webapp/WEB-INF/rails/webpack/views/`
- Convert SCSS to standard CSS (replace variables, remove mixins, expand media queries)
- Preserve exact values: colors, spacing, font sizes, transitions
- Keep GoCD's class naming conventions where possible
- Store in `assets/css/gocd/` to clearly mark origin

**What we copy**:
- Layout CSS (site_header, navigation, footers)
- Component styles (dropdowns, buttons, cards, modals)
- Color schemes and theme variables
- Typography and font specifications
- Responsive breakpoints and mobile styles
- Animation and transition timings
- Accessibility features (focus states, ARIA support)

**Conversion process**:
1. Identify SCSS file in GoCD source
2. Copy to `assets/css/gocd/[component].css`
3. Replace SCSS variables with CSS values (from `_variables.scss`)
4. Expand mixins inline
5. Convert nested selectors to flat CSS
6. Test against original GoCD at each breakpoint
7. Document source file in header comment

**Example conversion**:
```scss
// GoCD source: site_header.scss
.site-header {
  background: $site-header;  // #000728
  @media (min-width: $screen-md) {  // 768px
    height: 40px;
  }
}
```

```css
/* Converted from gocd/server/.../site_header.scss */
.site-header {
  background: #000728;
}
@media (min-width: 768px) {
  .site-header {
    height: 40px;
  }
}
```

### DaisyUI Role

**NOT used for GoCD UI components**. DaisyUI is available but secondary:
- Use for internal admin tools (if we build any)
- Use for developer-facing debugging UIs
- Do NOT use for user-facing GoCD interfaces
- Pipeline dashboard, agents, materials, etc. use pure GoCD CSS

**Why this approach**:
- GoCD has a distinctive, professional UI that users know
- Rewriting === preserving the experience
- DaisyUI would make it look generic/different
- GoCD's CSS is well-crafted and battle-tested

### Layout Structure

Follow GoCD's exact component hierarchy:
- Site header (fixed, 40px on desktop, 50px on mobile)
- Main navigation (left: menu items, right: help + user)
- Content area (dashboard, agents, materials, etc.)
- Modals and overlays (for confirmations, forms)

### Responsive Design

Match GoCD's breakpoints exactly:
- Mobile: < 768px
- Tablet: 768px - 991px  
- Desktop: >= 992px

Preserve GoCD's mobile menu behavior:
- Hamburger button on mobile
- Slide-out navigation
- Touch-friendly 44px tap targets

### Component Mapping

| GoCD Component | Our Implementation | CSS Source |
|----------------|-------------------|------------|
| Site Header | `layouts.ex` `site_header/1` | `site_header.css` |
| Navigation | Part of site_header | `site_menu/index.scss` → CSS |
| Dashboard | `dashboard_live.ex` | TBD from GoCD |
| Pipeline Cards | LiveView component | TBD from GoCD |
| Dropdowns | Custom LiveView | `dropdown.css` (adapted) |

### Testing Visual Fidelity

For each component:
1. Open original GoCD: `http://localhost:8153/go/pipelines`
2. Open our version: `http://localhost:4000/`
3. Compare side-by-side at each breakpoint
4. Verify spacing, colors, fonts, hover states
5. Check keyboard navigation and accessibility
6. Adjust CSS until pixel-perfect

### When to Deviate

Only deviate from GoCD's CSS when:
- Adapting React/Mithril components to LiveView (structure only, keep styling)
- Removing Java/Spring-specific elements (server-side rendering artifacts)
- Adding Phoenix-specific features (LiveView loading states)
- Improving accessibility beyond GoCD's baseline

Always document deviations and reasoning.

## Rough Plan

- to counter the modern dilution of the concepts and revive GoCD, let's rewrite it into [Phoenix Framework](https://www.phoenixframework.org/) ([docs](https://hexdocs.pm/phoenix/overview.html)) and keep the overall architecture and UI style of GoCD but rewrite it into the current favorite [DaisyUI](https://daisyui.com/docs/install/phoenix/?lang=en) in Phoenix, with [LiveView](https://hexdocs.pm/phoenix_live_view/welcome.html) for simple live view updates.
- try to avoid javascript and focus on rewriting the UI into LiveView.
- use LiveView PubSub for things to be distributed to all connected LiveView clients e.g. for notifications. Where applicable and doable, use [LiveView Streams](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#stream/4), e.g. for logs.
- as a plan, let's keep a [status.md](./status.md) where we'll put a table of all directories and files from [gocd source](../../gocd) and will keep track of the corresponding places in [this source](..) to build an incremental phoenix-rewrite (pun intended).
- For the agent, let's by default build it in Go, built without `cgo` as a standalone statically linked binary
- As for SCM systems, let's only focus on git but not exclude the option to implement others.
- for the rest, let's keep the overall architecture, but use [Elixir](https://elixirschool.com/en/lessons/advanced/otp_concurrency)/[Phoenix](https://elixirschool.com/blog/tag/phoenix)-native patterns, e.g like [GenStateMachine](https://hexdocs.pm/gen_state_machine/GenStateMachine.html) and [GenServer](https://elixirschool.com/en/lessons/advanced/otp_concurrency). Polling is just a delayed self-message in GenServer.
- We'll slowly and continuously build it up, concentrating on the same testability, test coverage as the original GoCD. We can also follow the testing strategy.
- As for the database, we'll stick to [Ecto](https://hexdocs.pm/phoenix/ecto.html), run postgres in docker compose locally, but support / have examples for both sqlite and postgres in the repo.
- We'll use [Phoenix telemetry](https://hexdocs.pm/phoenix/telemetry.html) to observe both the server but also the domain events / spans, if possible. That way we can try to minimize the dependencies as well.
- When finishing each atomic task, add the most important entries in terse form in [status.md](./status.md) "Progress Log". Do not add something to the progress log if it's already part of it.
- Make sure to make the app still work for a variety of screens, touch screen and keep it accessible.
- TEST at all levels that make sense! Try to stay close to the specification in the original GoCD repo. Test [LiveViews](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html) and [Ecto](https://hexdocs.pm/ecto/testing-with-ecto.html) apart from the unit and integration tests of modules. Make sure the tests run in Github Actions and report a table of results.

## agent links

- https://daisyui.com/llms.txt
- [AGENTS.md](../AGENTS.md)
