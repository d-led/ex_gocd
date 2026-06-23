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
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/ex_gocd";
import topbar from "../vendor/topbar";

const AgentsUpdates = {
  mounted() {
    // Path only: Phoenix Socket builds full URL and appends /websocket transport itself.
    // Using a full ws:// URL can cause the client to request /socket/websocket/websocket.
    this.agentsSocket = new Socket("/socket", { params: {} });
    this.agentsSocket.connect();
    this.agentsChannel = this.agentsSocket.channel("agents:updates", {});
    this.agentsChannel.on("agents_updated", () => {
      this.pushEvent("refresh_agents", {});
    });
    this.agentsChannel
      .join()
      .receive("ok", () => {})
      .receive("error", () => {});
  },
  destroyed() {
    if (this.agentsChannel) this.agentsChannel.leave();
    if (this.agentsSocket) this.agentsSocket.disconnect();
  },
};

const VSMGraph = {
  mounted() {
    this._persistentHighlight = null;

    // ── zoom/pan state (desktop only) ──────────────────────────
    this._zoom = 1;
    this._panX = 0;
    this._panY = 0;
    this._dragging = false;
    this._dragStartX = 0;
    this._dragStartY = 0;
    this._dragPanX = 0;
    this._dragPanY = 0;
    this._lastTouches = null;
    this._lastTouchDist = 0;
    this._pinchZoomStart = 1;

    this._isDesktop = () => window.innerWidth >= 768;
    this._transformGroup = () => this.el.querySelector("#vsm-transform-group");
    this._svg = () => this.el.querySelector("#vsm-svg");

    this.drawLines();

    this.resizeObserver = new ResizeObserver(() => {
      this.drawLines();
      if (this._isDesktop()) this._scheduleAutoFit();
    });
    this.resizeObserver.observe(this.el);
    window.addEventListener(
      "resize",
      (this.handleResize = () => {
        this.drawLines();
        if (this._isDesktop()) this._autoFit();
      }),
    );

    // ── mouse wheel zoom ───────────────────────────────────────
    this._onWheel = (e) => {
      if (!this._isDesktop()) return;
      e.preventDefault();

      const rect = this.el.getBoundingClientRect();
      const mx = e.clientX - rect.left;
      const my = e.clientY - rect.top;
      const factor = e.deltaY < 0 ? 1.1 : 1 / 1.1;

      this._zoomTo(mx, my, factor);
    };
    this.el.addEventListener("wheel", this._onWheel, { passive: false });

    // ── mouse drag pan ─────────────────────────────────────────
    this._onMouseDown = (e) => {
      if (!this._isDesktop()) return;
      // Don't start drag on interactive elements (buttons, links, etc.)
      if (e.target.closest("button, a, input, .vsm-node")) return;
      this._dragging = true;
      this._dragStartX = e.clientX;
      this._dragStartY = e.clientY;
      this._dragPanX = this._panX;
      this._dragPanY = this._panY;
      this.el.style.cursor = "grabbing";
    };
    this._onMouseMove = (e) => {
      if (!this._dragging) return;
      this._panX = this._dragPanX + (e.clientX - this._dragStartX);
      this._panY = this._dragPanY + (e.clientY - this._dragStartY);
      this._applyTransform();
      this.drawLines();
    };
    this._onMouseUp = () => {
      if (!this._dragging) return;
      this._dragging = false;
      this.el.style.cursor = this._isDesktop() ? "grab" : "";
    };
    this.el.addEventListener("mousedown", this._onMouseDown);
    window.addEventListener("mousemove", this._onMouseMove);
    window.addEventListener("mouseup", this._onMouseUp);

    // ── touch pan + pinch zoom ─────────────────────────────────
    this._onTouchStart = (e) => {
      if (!this._isDesktop()) return;
      if (e.touches.length === 1) {
        this._dragging = true;
        this._dragStartX = e.touches[0].clientX;
        this._dragStartY = e.touches[0].clientY;
        this._dragPanX = this._panX;
        this._dragPanY = this._panY;
      } else if (e.touches.length === 2) {
        this._dragging = false;
        this._lastTouches = [e.touches[0], e.touches[1]];
        this._lastTouchDist = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY,
        );
        this._pinchZoomStart = this._zoom;
        const cx = (e.touches[0].clientX + e.touches[1].clientX) / 2;
        const cy = (e.touches[0].clientY + e.touches[1].clientY) / 2;
        const rect = this.el.getBoundingClientRect();
        this._pinchCx = cx - rect.left;
        this._pinchCy = cy - rect.top;
        this._pinchPanX = this._panX;
        this._pinchPanY = this._panY;
      }
    };
    this._onTouchMove = (e) => {
      if (!this._isDesktop()) return;
      if (e.touches.length === 1 && this._dragging) {
        this._panX = this._dragPanX + (e.touches[0].clientX - this._dragStartX);
        this._panY = this._dragPanY + (e.touches[0].clientY - this._dragStartY);
        this._applyTransform();
        this.drawLines();
      } else if (e.touches.length === 2) {
        const dist = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY,
        );
        if (this._lastTouchDist > 0) {
          const scale = (dist / this._lastTouchDist) * this._pinchZoomStart;
          this._zoom = Math.min(3, Math.max(0.25, scale));
          const cx = (e.touches[0].clientX + e.touches[1].clientX) / 2;
          const cy = (e.touches[0].clientY + e.touches[1].clientY) / 2;
          const rect = this.el.getBoundingClientRect();
          const newCx = cx - rect.left;
          const newCy = cy - rect.top;
          this._panX = this._pinchPanX + (newCx - this._pinchCx);
          this._panY = this._pinchPanY + (newCy - this._pinchCy);
          this._applyTransform();
          this.drawLines();
        }
      }
    };
    this._onTouchEnd = () => {
      this._dragging = false;
      this._lastTouchDist = 0;
    };
    this.el.addEventListener("touchstart", this._onTouchStart, { passive: false });
    this.el.addEventListener("touchmove", this._onTouchMove, { passive: false });
    this.el.addEventListener("touchend", this._onTouchEnd);

    // ── zoom control buttons ───────────────────────────────────
    const zoomIn = this.el.querySelector("#vsm-zoom-in");
    const zoomOut = this.el.querySelector("#vsm-zoom-out");
    const zoomFit = this.el.querySelector("#vsm-zoom-fit");

    if (zoomIn) {
      zoomIn.addEventListener("click", () => {
        const rect = this.el.getBoundingClientRect();
        this._zoomTo(rect.width / 2, rect.height / 2, 1.25);
      });
    }
    if (zoomOut) {
      zoomOut.addEventListener("click", () => {
        const rect = this.el.getBoundingClientRect();
        this._zoomTo(rect.width / 2, rect.height / 2, 1 / 1.25);
      });
    }
    if (zoomFit) {
      zoomFit.addEventListener("click", () => this._autoFit());
    }

    // ── initial desktop cursor ─────────────────────────────────
    if (this._isDesktop()) {
      this.el.style.cursor = "grab";
      this._autoFit();
    }
  },

  updated() {
    this.drawLines();
    if (this._isDesktop()) this._autoFit();
  },

  destroyed() {
    if (this.resizeObserver) this.resizeObserver.disconnect();
    window.removeEventListener("resize", this.handleResize);
    this.el.removeEventListener("wheel", this._onWheel);
    this.el.removeEventListener("mousedown", this._onMouseDown);
    window.removeEventListener("mousemove", this._onMouseMove);
    window.removeEventListener("mouseup", this._onMouseUp);
    this.el.removeEventListener("touchstart", this._onTouchStart);
    this.el.removeEventListener("touchmove", this._onTouchMove);
    this.el.removeEventListener("touchend", this._onTouchEnd);
  },

  // ── zoom/pan helpers ─────────────────────────────────────────────

  /** Zoom toward a point (mx, my) in container coordinates. */
  _zoomTo(mx, my, factor) {
    const newZoom = Math.min(3, Math.max(0.25, this._zoom * factor));
    // Keep the point under the cursor fixed
    this._panX = mx - (mx - this._panX) * (newZoom / this._zoom);
    this._panY = my - (my - this._panY) * (newZoom / this._zoom);
    this._zoom = newZoom;
    this._applyTransform();
    this.drawLines();
  },

  /** Fit the entire graph within the container's padding box. */
  _autoFit() {
    const group = this._transformGroup();
    if (!group) return;
    const elStyle = getComputedStyle(this.el);
    const padLeft = parseFloat(elStyle.paddingLeft) || 0;
    const padRight = parseFloat(elStyle.paddingRight) || 0;
    const padTop = parseFloat(elStyle.paddingTop) || 0;
    const padBottom = parseFloat(elStyle.paddingBottom) || 0;
    const innerW = this.el.clientWidth - padLeft - padRight;
    const innerH = this.el.clientHeight - padTop - padBottom;
    if (innerW < 20 || innerH < 20) return;

    // Clear transform to measure natural node positions
    group.style.transform = "";

    const containerRect = this.el.getBoundingClientRect();
    const nodes = this.el.querySelectorAll(".vsm-node");
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    nodes.forEach((n) => {
      const r = n.getBoundingClientRect();
      const x = r.left - containerRect.left + this.el.scrollLeft;
      const y = r.top - containerRect.top + this.el.scrollTop;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x + r.width > maxX) maxX = x + r.width;
      if (y + r.height > maxY) maxY = y + r.height;
    });
    if (!isFinite(minX)) return;

    const contentW = maxX - minX;
    const contentH = maxY - minY;

    const scaleX = innerW / Math.max(contentW, 1);
    const scaleY = innerH / Math.max(contentH, 1);
    const scale = Math.min(scaleX, scaleY, 1); // never exceed 1 on auto-fit

    this._zoom = Math.max(0.25, scale);
    this._panX = padLeft + (innerW - contentW * this._zoom) / 2 - minX * this._zoom;
    this._panY = padTop + (innerH - contentH * this._zoom) / 2 - minY * this._zoom;

    this._applyTransform();
    this.drawLines();
  },

  /** Schedule auto-fit after layout settles. */
  _scheduleAutoFit() {
    if (this._autoFitTimer) clearTimeout(this._autoFitTimer);
    this._autoFitTimer = setTimeout(() => this._autoFit(), 100);
  },

  /** Apply current zoom/pan to the transform group. */
  _applyTransform() {
    const group = this._transformGroup();
    if (!group) return;
    group.style.transform = `translate(${this._panX}px, ${this._panY}px) scale(${this._zoom})`;
  },

  // ── path drawing ──────────────────────────────────────────────────

  drawLines() {
    setTimeout(() => {
      const svg = this._svg();
      if (!svg) return;

      const oldPaths = svg.querySelectorAll(".vsm-path");
      oldPaths.forEach((p) => p.remove());
      this._persistentHighlight = null;

      svg.setAttribute("width", this.el.clientWidth);
      svg.setAttribute(
        "height",
        Math.max(this.el.clientHeight, this.el.scrollHeight),
      );
      svg.style.overflow = "visible";

      const zoom = this._isDesktop() ? this._zoom : 1;
      const wrapperRect = this.el.getBoundingClientRect();
      const nodes = this.el.querySelectorAll(".vsm-node");
      const nodeMap = {};

      nodes.forEach((node) => {
        const id = node.dataset.id;
        const rect = node.getBoundingClientRect();
        // Convert screen-space coords to SVG coords (divide by zoom,
        // as SVG is inside the same CSS-transformed group as nodes)
        nodeMap[id] = {
          el: node,
          x: (rect.left - wrapperRect.left + this.el.scrollLeft) / zoom,
          y: (rect.top - wrapperRect.top + this.el.scrollTop) / zoom,
          width: rect.width / zoom,
          height: rect.height / zoom,
          isCurrent: node.classList.contains("border-[#943a9e]"),
        };
      });

      const nodeArr = Object.values(nodeMap);
      const narrow = detectNarrowLayout(nodeArr);

      let busX = 0;
      if (narrow && nodeArr.length > 0) {
        const minLeft = Math.min(...nodeArr.map((n) => n.x));
        busX = Math.max(20, minLeft - 48);
      }

      nodes.forEach((node) => {
        const sourceId = node.dataset.id;
        const source = nodeMap[sourceId];
        if (!source) return;

        let dependents = [];
        try {
          dependents = JSON.parse(node.dataset.dependents || "[]");
        } catch {}

        dependents.forEach((depId, depIdx) => {
          const target = nodeMap[depId];
          if (!target) return;

          const sx = source.x + source.width;
          const sy = source.y + source.height / 2;
          const tx = target.x;
          const ty = target.y + target.height / 2;

          const isHighlight = source.isCurrent || target.isCurrent;

          let pathD;
          if (narrow) {
            const stagger = depIdx * 5;
            const bx = busX + stagger;
            const lx = source.x;
            pathD = `M ${lx} ${sy} L ${bx} ${sy} L ${bx} ${ty} L ${tx} ${ty}`;
          } else {
            const dx = Math.max(40, (tx - sx) / 2);
            pathD = `M ${sx} ${sy} C ${sx + dx} ${sy}, ${tx - dx} ${sy}, ${tx} ${ty}`;
          }

          // Invisible hit path — 20px wide for easy hover/tap
          const hit = document.createElementNS(
            "http://www.w3.org/2000/svg",
            "path",
          );
          hit.setAttribute("d", pathD);
          hit.setAttribute("class", "vsm-path");
          hit.setAttribute("stroke", "transparent");
          hit.setAttribute("stroke-width", "20");
          hit.setAttribute("fill", "none");
          hit.setAttribute("stroke-linecap", "round");
          hit.setAttribute("stroke-linejoin", "round");
          hit.setAttribute("pointer-events", "all");
          hit.style.cursor = "pointer";
          hit.style.transition = "opacity 0.2s";
          hit.dataset.sourceId = sourceId;
          hit.dataset.targetId = depId;

          // Visible path — thin coloured line + arrowhead
          const vis = document.createElementNS(
            "http://www.w3.org/2000/svg",
            "path",
          );
          vis.setAttribute("d", pathD);
          vis.setAttribute("class", "vsm-path");
          vis.setAttribute("stroke", isHighlight ? "#943a9e" : "#2fa8b6");
          vis.setAttribute("stroke-width", isHighlight ? "2" : "1.5");
          vis.setAttribute("fill", "none");
          vis.setAttribute("stroke-linejoin", "round");
          vis.setAttribute(
            "marker-end",
            isHighlight ? "url(#arrow-current)" : "url(#arrow)",
          );
          vis.style.pointerEvents = "none";
          vis.style.transition = "opacity 0.2s";
          vis.dataset.sourceId = sourceId;
          vis.dataset.targetId = depId;

          const self = this;
          hit.addEventListener("mouseenter", () => self._highlight(hit, svg));
          hit.addEventListener("mouseleave", () => self._unhighlight(svg));
          hit.addEventListener("click", (e) => {
            e.stopPropagation();
            self._togglePersistent(hit, svg);
          });

          svg.appendChild(hit);
          svg.appendChild(vis);
        });
      });
    }, 0);
  },

  // ── interactive arrow highlight / dim ──────────────────────────

  _highlight(path, svg) {
    const src = path.dataset.sourceId;
    const tgt = path.dataset.targetId;
    svg.querySelectorAll(".vsm-path").forEach((p) => {
      const isHit = p.getAttribute("stroke") === "transparent";
      if (isHit) {
        p.style.opacity = "1";
        return;
      }
      if (p.dataset.sourceId === src && p.dataset.targetId === tgt) {
        p.style.opacity = "1";
      } else {
        p.style.opacity = "0.15";
      }
    });
    this._setNodeHighlight(src, true);
    this._setNodeHighlight(tgt, true);
  },

  _unhighlight(svg) {
    if (this._persistentHighlight) {
      this._highlight(this._persistentHighlight, svg);
      return;
    }
    svg.querySelectorAll(".vsm-path").forEach((p) => {
      p.style.opacity = "1";
    });
    this.el
      .querySelectorAll(".vsm-node")
      .forEach((n) => n.classList.remove("vsm-path-highlighted"));
  },

  _setNodeHighlight(nodeId, on) {
    if (!nodeId) return;
    const node = this.el.querySelector(`.vsm-node[data-id="${nodeId}"]`);
    if (node) {
      if (on) node.classList.add("vsm-path-highlighted");
      else node.classList.remove("vsm-path-highlighted");
    }
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
};

/** Detect vertical-stack layout: nodes are stacked in one column (narrow viewport). */
function detectNarrowLayout(nodes) {
  if (nodes.length < 2) return false;
  const centers = nodes.map((n) => n.x + n.width / 2);
  const span = Math.max(...centers) - Math.min(...centers);
  // If all node centers are within ~half a node width of each other horizontally,
  // the layout is effectively vertical.
  const avgWidth = nodes.reduce((s, n) => s + n.width, 0) / nodes.length;
  return span < avgWidth * 0.6;
}

const ConsoleScroller = {
  mounted() {
    this.scrollIfFollowing();
    this.updateFoldVisibility();
    window.addEventListener("update-folds", this.boundUpdateFolds);
  },
  updated() {
    this.scrollIfFollowing();
    this.updateFoldVisibility();
  },
  destroyed() {
    window.removeEventListener("update-folds", this.boundUpdateFolds);
  },
  scrollIfFollowing() {
    const follow = this.el.dataset.follow;
    if (follow === undefined || follow === "true") {
      this.el.scrollTop = this.el.scrollHeight;
    }
  },
  updateFoldVisibility() {
    const container = this.el;
    const collapsedIds = new Set();
    container.querySelectorAll(".fold-start.collapsed").forEach((f) => {
      collapsedIds.add(f.dataset.foldId);
    });
    container.querySelectorAll(".log-row").forEach((row) => {
      if (row.classList.contains("fold-start")) return;
      const parents = (row.dataset.foldParents || "")
        .split(" ")
        .filter(Boolean);
      const hidden = parents.some((id) => collapsedIds.has(id));
      row.classList.toggle("hidden", hidden);
    });
  },
  boundUpdateFolds() {
    this.updateFoldVisibility();
  },
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { AgentsUpdates, VSMGraph, ConsoleScroller, ...colocatedHooks },
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// --- Mobile navigation toggle (burger menu) ---
(function () {
  const navbtn = document.querySelector(".navbtn");
  const mainNav = document.getElementById("main-navigation");
  const bar = navbtn ? navbtn.querySelector(".bar") : null;
  if (!navbtn || !mainNav || !bar) return;

  let isOpen = false;

  function close() {
    isOpen = false;
    navbtn.setAttribute("aria-expanded", "false");
    navbtn.setAttribute("aria-label", "Open navigation menu");
    mainNav.removeAttribute("aria-expanded");
    bar.classList.remove("animate");
    document.body.classList.remove("menu-open");
    document.documentElement.style.overflow = "";
  }

  function open() {
    isOpen = true;
    navbtn.setAttribute("aria-expanded", "true");
    navbtn.setAttribute("aria-label", "Close navigation menu");
    mainNav.setAttribute("aria-expanded", "true");
    bar.classList.add("animate");
    document.body.classList.add("menu-open");
    document.documentElement.style.overflow = "hidden";
  }

  function toggle() {
    isOpen ? close() : open();
  }

  navbtn.addEventListener("click", toggle);

  // Close on Escape
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && isOpen) {
      close();
      navbtn.focus();
    }
  });

  // Handle clicks inside the mobile nav: close on links, toggle admin sub-menu
  mainNav.addEventListener("click", (e) => {
    if (!isOpen) return;

    const dropDown = e.target.closest("li.is-drop-down");
    const clickedAnchor = e.target.closest("a");

    // Mobile: toggle admin sub-menu on tap (instead of hover)
    if (
      dropDown &&
      window.innerWidth < 768 &&
      clickedAnchor &&
      clickedAnchor.parentElement === dropDown &&
      !e.target.closest(".sub-navigation")
    ) {
      e.preventDefault();
      dropDown.classList.toggle("sub-open");
      return;
    }

    // Close menu when any nav link is clicked
    if (clickedAnchor) close();
  });

  // Close on resize above mobile breakpoint
  window.addEventListener("resize", () => {
    if (isOpen && window.innerWidth >= 768) close();
  });
})();

// --- Desktop admin dropdown: viewport-aware positioning ---
(function () {
  const dropDownLi = document.querySelector("li.is-drop-down");
  if (!dropDownLi) return;

  const subNav = dropDownLi.querySelector(".sub-navigation");
  if (!subNav) return;

  function reposition() {
    // Reset — let CSS defaults (left:0, position:absolute) apply
    subNav.classList.remove("anchor-right");
    subNav.style.left = "";
    subNav.style.right = "";
    subNav.style.position = "";

    // Force layout so we measure the natural position
    subNav.offsetHeight;

    const rect = subNav.getBoundingClientRect();
    const vpW = window.innerWidth;

    // If it fits naturally, we're done
    if (rect.right <= vpW && rect.left >= 0) return;

    // Try right-anchoring (right edge of dropdown = right edge of parent li)
    subNav.classList.add("anchor-right");
    subNav.offsetHeight;
    const rectR = subNav.getBoundingClientRect();

    if (rectR.left >= 0) {
      // Right-anchored fits — done
      return;
    }

    // Still overflows left → use fixed positioning pinned to viewport right
    subNav.classList.remove("anchor-right");
    subNav.style.position = "fixed";
    subNav.style.top = rect.top + "px";
    subNav.style.left = Math.max(0, vpW - rect.width - 16) + "px";

    // Last resort: if still too wide, allow horizontal scroll
    subNav.offsetHeight;
    const rectF = subNav.getBoundingClientRect();
    if (rectF.left < 0) {
      subNav.style.left = "0px";
      subNav.style.maxWidth = vpW + "px";
      subNav.style.overflowX = "auto";
    }
  }

  function resetPosition() {
    subNav.classList.remove("anchor-right");
    subNav.style.left = "";
    subNav.style.right = "";
    subNav.style.position = "";
    subNav.style.top = "";
    subNav.style.maxWidth = "";
    subNav.style.overflowX = "";
  }

  dropDownLi.addEventListener("mouseenter", reposition);
  dropDownLi.addEventListener("mouseleave", resetPosition);

  // Recalculate on resize if visible
  window.addEventListener("resize", () => {
    const display = getComputedStyle(subNav).display;
    if (display === "flex") reposition();
  });
})();

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (_e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
