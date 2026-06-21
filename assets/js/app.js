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

      // Clear existing connection paths
      const paths = svg.querySelectorAll(".vsm-path");
      paths.forEach(p => p.remove());

      // Adjust SVG size to match scrollable area
      svg.setAttribute("width", this.el.scrollWidth);
      svg.setAttribute("height", this.el.scrollHeight);

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

        dependents.forEach(depId => {
          const target = nodeMap[depId];
          if (!target) return;

          const x1 = source.x + source.width;
          const y1 = source.y + source.height / 2;
          const x2 = target.x;
          const y2 = target.y + target.height / 2;

          const dx = Math.max(40, (x2 - x1) / 2);

          const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
          path.setAttribute("d", `M ${x1} ${y1} C ${x1 + dx} ${y1}, ${x2 - dx} ${y2}, ${x2} ${y2}`);
          path.setAttribute("class", "vsm-path");
          
          const isHighlight = source.isCurrent || target.isCurrent;
          path.setAttribute("stroke", isHighlight ? "#943a9e" : "#2fa8b6");
          path.setAttribute("stroke-width", isHighlight ? "3" : "2");
          path.setAttribute("fill", "none");
          path.setAttribute("marker-end", isHighlight ? "url(#arrow-current)" : "url(#arrow)");
          
          svg.appendChild(path);
        });
      });
    });
  }
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

