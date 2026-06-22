// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/ex_gocd"
import topbar from "../vendor/topbar"
import {ConsoleScroller} from "./hooks/console_scroller"

const AgentsUpdates = {
  mounted() {
    // Path only: Phoenix Socket builds full URL and appends /websocket transport itself.
    // Using a full ws:// URL can cause the client to request /socket/websocket/websocket.
    this.agentsSocket = new Socket("/socket", {params: {}})
    this.agentsSocket.connect()
    this.agentsChannel = this.agentsSocket.channel("agents:updates", {})
    this.agentsChannel.on("agents_updated", () => {
      this.pushEvent("refresh_agents", {})
    })
    this.agentsChannel.join()
      .receive("ok", () => {})
      .receive("error", () => {})
  },
  destroyed() {
    if (this.agentsChannel) this.agentsChannel.leave()
    if (this.agentsSocket) this.agentsSocket.disconnect()
  }
}

const VSMGraph = {
  mounted() {
    this._persistentHighlight = null;
    this.drawLines();
    this.resizeObserver = new ResizeObserver(() => this.drawLines());
    this.resizeObserver.observe(this.el);
    window.addEventListener("resize", this.handleResize = () => this.drawLines());
  },
  updated() {
    this.drawLines();
  },
  destroyed() {
    if (this.resizeObserver) this.resizeObserver.disconnect();
    window.removeEventListener("resize", this.handleResize);
  },
  drawLines() {
    requestAnimationFrame(() => {
      const svg = this.el.querySelector("#vsm-svg");
      if (!svg) return;

      // Clear existing paths & hit areas; reset persistent highlight on redraw
      const oldPaths = svg.querySelectorAll(".vsm-path, .vsm-hit");
      oldPaths.forEach(p => p.remove());
      this._persistentHighlight = null;

      // Size SVG to the visible container area (client, not scroll)
      // so paths don't force horizontal scroll in narrow/mobile view.
      svg.setAttribute("width", this.el.clientWidth);
      svg.setAttribute("height", Math.max(this.el.clientHeight, this.el.scrollHeight));
      svg.style.overflow = "visible";

      const wrapperRect = this.el.getBoundingClientRect();
      const nodes = this.el.querySelectorAll(".vsm-node");
      const nodeMap = {};

      nodes.forEach(node => {
        const id = node.dataset.id;
        const rect = node.getBoundingClientRect();
        nodeMap[id] = {
          el: node,
          x: rect.left - wrapperRect.left + this.el.scrollLeft,
          y: rect.top - wrapperRect.top + this.el.scrollTop,
          width: rect.width,
          height: rect.height,
          isCurrent: node.classList.contains("border-[#943a9e]")
        };
      });

      // Detect narrow / vertically-stacked layout (mobile / narrow browser)
      const nodeArr = Object.values(nodeMap);
      const narrow = detectNarrowLayout(nodeArr);

      // Bus lane X coordinate for narrow-mode routing.
      // Use the LEFT side so arrowheads point right into targets and their
      // bases extend left (outside node bounding boxes, visible above z-index).
      let busX = 0;
      if (narrow && nodeArr.length > 0) {
        const minLeft = Math.min(...nodeArr.map(n => n.x));
        busX = Math.max(20, minLeft - 48);
      }

      // Render paths for each dependency link
      nodes.forEach(node => {
        const sourceId = node.dataset.id;
        const source = nodeMap[sourceId];
        if (!source) return;

        let dependents = [];
        try {
          dependents = JSON.parse(node.dataset.dependents || "[]");
        } catch (e) {
          console.error(e);
        }

        dependents.forEach((depId, depIdx) => {
          const target = nodeMap[depId];
          if (!target) return;

          const sx = source.x + source.width;
          const sy = source.y + source.height / 2;
          const tx = target.x;
          const ty = target.y + target.height / 2;

          const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
          const isHighlight = source.isCurrent || target.isCurrent;

          let pathD;
          if (narrow) {
            // Left-side sewage-pipe: exit source LEFT edge → bus on the left →
            // down/up the bus → enter target LEFT edge.
            // Arrow points RIGHT into target, base extends LEFT (visible).
            const stagger = depIdx * 5;
            const bx = busX + stagger;
            const lx = source.x; // source left edge

            pathD = `M ${lx} ${sy} L ${bx} ${sy} L ${bx} ${ty} L ${tx} ${ty}`;
          } else {
            // Wide mode: cubic bezier with natural approach angle
            const dx = Math.max(40, (tx - sx) / 2);
            pathD = `M ${sx} ${sy} C ${sx + dx} ${sy}, ${tx - dx} ${sy}, ${tx} ${ty}`;
          }

          path.setAttribute("d", pathD);
          path.setAttribute("class", "vsm-path");
          path.setAttribute("stroke", isHighlight ? "#943a9e" : "#2fa8b6");
          path.setAttribute("stroke-width", isHighlight ? "3" : "2");
          path.setAttribute("fill", "none");
          path.setAttribute("stroke-linejoin", "round");
          path.setAttribute("marker-end", isHighlight ? "url(#arrow-current)" : "url(#arrow)");
          path.style.transition = "opacity 0.2s";

          svg.appendChild(path);

          // Invisible wide hit area for touch / hover on mobile & desktop
          const hit = document.createElementNS("http://www.w3.org/2000/svg", "path");
          hit.setAttribute("d", pathD);
          hit.setAttribute("class", "vsm-hit");
          hit.setAttribute("stroke", "transparent");
          hit.setAttribute("stroke-width", "24");
          hit.setAttribute("fill", "none");
          hit.setAttribute("stroke-linecap", "round");
          hit.setAttribute("stroke-linejoin", "round");
          hit.style.pointerEvents = "stroke";
          hit.style.cursor = "pointer";

          const self = this;
          hit.addEventListener("mouseenter", () => self._highlight(path, svg));
          hit.addEventListener("mouseleave", () => self._unhighlight(svg));
          hit.addEventListener("click", (e) => {
            e.stopPropagation();
            self._togglePersistent(path, svg);
          });

          svg.appendChild(hit);
        });
      });
    });
  },

  // ── interactive arrow highlight / dim ──────────────────────────

  _highlight(path, svg) {
    const all = svg.querySelectorAll(".vsm-path");
    all.forEach(p => {
      if (p === path) {
        p.style.opacity = "1";
        p.setAttribute("stroke-width", p.dataset.origWidth || p.getAttribute("stroke-width"));
      } else {
        p.style.opacity = "0.18";
        if (!p.dataset.origWidth) p.dataset.origWidth = p.getAttribute("stroke-width");
      }
    });
  },

  _unhighlight(svg) {
    if (this._persistentHighlight) {
      this._highlight(this._persistentHighlight, svg);
      return;
    }
    const all = svg.querySelectorAll(".vsm-path");
    all.forEach(p => {
      p.style.opacity = "1";
      p.setAttribute("stroke-width", p.dataset.origWidth || p.getAttribute("stroke-width"));
    });
  },

  _togglePersistent(path, svg) {
    if (this._persistentHighlight === path) {
      this._persistentHighlight = null;
      this._unhighlight(svg);
    } else {
      this._persistentHighlight = path;
      this._highlight(path, svg);
    }
  },
}

/** Detect vertical-stack layout: nodes are stacked in one column (narrow viewport). */
function detectNarrowLayout(nodes) {
  if (nodes.length < 2) return false;
  const centers = nodes.map(n => n.x + n.width / 2);
  const span = Math.max(...centers) - Math.min(...centers);
  // If all node centers are within ~half a node width of each other horizontally,
  // the layout is effectively vertical.
  const avgWidth = nodes.reduce((s, n) => s + n.width, 0) / nodes.length;
  return span < avgWidth * 0.6;
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {AgentsUpdates, VSMGraph, ConsoleScroller, ...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// --- Mobile navigation toggle (burger menu) ---
;(function() {
  const navbtn = document.querySelector('.navbtn')
  const mainNav = document.getElementById('main-navigation')
  const bar = navbtn ? navbtn.querySelector('.bar') : null
  if (!navbtn || !mainNav || !bar) return

  let isOpen = false

  function close() {
    isOpen = false
    navbtn.setAttribute('aria-expanded', 'false')
    navbtn.setAttribute('aria-label', 'Open navigation menu')
    mainNav.removeAttribute('aria-expanded')
    bar.classList.remove('animate')
    document.body.classList.remove('menu-open')
    document.documentElement.style.overflow = ''
  }

  function open() {
    isOpen = true
    navbtn.setAttribute('aria-expanded', 'true')
    navbtn.setAttribute('aria-label', 'Close navigation menu')
    mainNav.setAttribute('aria-expanded', 'true')
    bar.classList.add('animate')
    document.body.classList.add('menu-open')
    document.documentElement.style.overflow = 'hidden'
  }

  function toggle() { isOpen ? close() : open() }

  navbtn.addEventListener('click', toggle)

  // Close on Escape
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && isOpen) { close(); navbtn.focus() }
  })

  // Handle clicks inside the mobile nav: close on links, toggle admin sub-menu
  mainNav.addEventListener('click', (e) => {
    if (!isOpen) return

    const dropDown = e.target.closest('li.is-drop-down')
    const clickedAnchor = e.target.closest('a')

    // Mobile: toggle admin sub-menu on tap (instead of hover)
    if (dropDown && window.innerWidth < 768 && clickedAnchor && clickedAnchor.parentElement === dropDown && !e.target.closest('.sub-navigation')) {
      e.preventDefault()
      dropDown.classList.toggle('sub-open')
      return
    }

    // Close menu when any nav link is clicked
    if (clickedAnchor) close()
  })

  // Close on resize above mobile breakpoint
  window.addEventListener('resize', () => {
    if (isOpen && window.innerWidth >= 768) close()
  })
})()

// --- Desktop admin dropdown: viewport-aware positioning ---
;(function() {
  const dropDownLi = document.querySelector('li.is-drop-down')
  if (!dropDownLi) return

  const subNav = dropDownLi.querySelector('.sub-navigation')
  if (!subNav) return

  function reposition() {
    // Reset — let CSS defaults (left:0, position:absolute) apply
    subNav.classList.remove('anchor-right')
    subNav.style.left = ''
    subNav.style.right = ''
    subNav.style.position = ''

    // Force layout so we measure the natural position
    // eslint-disable-next-line no-unused-expressions
    subNav.offsetHeight

    const rect = subNav.getBoundingClientRect()
    const vpW = window.innerWidth

    // If it fits naturally, we're done
    if (rect.right <= vpW && rect.left >= 0) return

    // Try right-anchoring (right edge of dropdown = right edge of parent li)
    subNav.classList.add('anchor-right')
    // eslint-disable-next-line no-unused-expressions
    subNav.offsetHeight
    const rectR = subNav.getBoundingClientRect()

    if (rectR.left >= 0) {
      // Right-anchored fits — done
      return
    }

    // Still overflows left → use fixed positioning pinned to viewport right
    subNav.classList.remove('anchor-right')
    subNav.style.position = 'fixed'
    subNav.style.top = rect.top + 'px'
    subNav.style.left = Math.max(0, vpW - rect.width - 16) + 'px'

    // Last resort: if still too wide, allow horizontal scroll
    // eslint-disable-next-line no-unused-expressions
    subNav.offsetHeight
    const rectF = subNav.getBoundingClientRect()
    if (rectF.left < 0) {
      subNav.style.left = '0px'
      subNav.style.maxWidth = vpW + 'px'
      subNav.style.overflowX = 'auto'
    }
  }

  function resetPosition() {
    subNav.classList.remove('anchor-right')
    subNav.style.left = ''
    subNav.style.right = ''
    subNav.style.position = ''
    subNav.style.top = ''
    subNav.style.maxWidth = ''
    subNav.style.overflowX = ''
  }

  dropDownLi.addEventListener('mouseenter', reposition)
  dropDownLi.addEventListener('mouseleave', resetPosition)

  // Recalculate on resize if visible
  window.addEventListener('resize', () => {
    const display = getComputedStyle(subNav).display
    if (display === 'flex') reposition()
  })
})()

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

