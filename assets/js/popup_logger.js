// Client-side notification logger — watches Phoenix flash messages.
// Uses MutationObserver on #flash-group to capture flash (info/error) popups.
// Stores in localStorage, max 20 entries.
//
// Each entry: { timestamp: ISO-8601, type: "info"|"error", message: String }

const STORAGE_KEY = "ex_gocd_popup_log";
const MAX_ENTRIES = 20;

function loadLog() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
  } catch {
    return [];
  }
}

function saveLog(log) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(log.slice(-MAX_ENTRIES)));
  } catch {
    // silently ignore (storage full / private browsing)
  }
}

function pushEntry(type, message) {
  const log = loadLog();
  const trimmed = String(message || "").replace(/\s+/g, " ").trim().slice(0, 500);
  // Don't log duplicates of the last entry
  if (log.length > 0) {
    const last = log[log.length - 1];
    if (last.type === type && last.message === trimmed) return;
  }
  log.push({ timestamp: new Date().toISOString(), type, message: trimmed });
  saveLog(log);
  renderLogUI(log);
}

function startWatching() {
  const group = document.getElementById("flash-group");
  if (!group) return setTimeout(startWatching, 200);

  // Extract readable text from a flash element.
  // Flash structure: div#flash-info[role=alert] > div.alert > div > p{message}
  const extractFlashText = function (el) {
    const p = el.querySelector("p");
    if (p) return p.textContent.trim();
    const text = el.textContent.trim();
    return text || null;
  };

  const observer = new MutationObserver(function (mutations) {
    for (const m of mutations) {
      for (const node of m.addedNodes) {
        if (node.nodeType !== Node.ELEMENT_NODE) continue;

        if (node.id === "flash-info" || node.querySelector?.("#flash-info")) {
          const flashEl = node.id === "flash-info" ? node : node.querySelector("#flash-info");
          if (!flashEl || flashEl.style.display === "none") continue;
          const msg = extractFlashText(flashEl);
          if (msg) pushEntry("info", msg);
        }

        if (node.id === "flash-error" || node.querySelector?.("#flash-error")) {
          const flashEl = node.id === "flash-error" ? node : node.querySelector("#flash-error");
          if (!flashEl || flashEl.style.display === "none") continue;
          const msg = extractFlashText(flashEl);
          if (msg) pushEntry("error", msg);
        }
      }

      // Attribute changes: flash becomes visible via phx-mounted
      for (const m of mutations) {
        if (m.type !== "attributes") continue;
        const el = m.target;
        if (!el.id || !el.id.startsWith("flash-")) continue;
        if (el.style.display !== "none" && el.offsetParent !== null) {
          const msg = extractFlashText(el);
          if (msg) {
            const type = el.id === "flash-error" ? "error" : "info";
            pushEntry(type, msg);
          }
        }
      }
    }
  });

  observer.observe(group, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["style", "class", "hidden"],
  });
}

// Start when DOM is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", startWatching);
} else {
  startWatching();
}

// Debug helpers
window.__exGocdPopups = function () { return loadLog(); };
window.__exGocdClearPopups = function () { saveLog([]); renderLogUI([]); };

// ── Footer dropdown UI ──────────────────────────────────────────

function renderLogUI(log) {
  const logger = document.getElementById("flash-logger-toggle");
  const list = document.getElementById("flash-logger-list");
  const countBadge = document.getElementById("flash-logger-count");
  if (!logger || !list) return;

  if (log.length === 0) {
    logger.style.display = "none";
    return;
  }

  logger.style.display = "";
  if (countBadge) {
    countBadge.textContent = log.length > 99 ? "99+" : log.length;
    countBadge.classList.remove("hidden");
  }

  list.innerHTML = log
    .slice()
    .reverse()
    .map(function (e) {
      var ts = e.timestamp.replace("T", " ").slice(0, 19);
      var icon = e.type === "error" ? "❌" : "ℹ️";
      var textCls = e.type === "error" ? "text-red-700" : "text-gray-800";
      var bgCls = e.type === "error" ? "bg-red-50" : "bg-white";
      return (
        '<div class="px-3 py-1.5 border-b border-gray-100 ' +
        bgCls +
        '">' +
        '<span class="text-gray-400">' +
        ts +
        "</span> " +
        icon +
        ' <span class="' +
        textCls +
        '">' +
        escHtml(e.message) +
        "</span></div>"
      );
    })
    .join("");
}

function escHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// Restore existing log on page load
document.addEventListener("DOMContentLoaded", function () {
  renderLogUI(loadLog());

  // Esc to close dropdown
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") {
      var dd = document.getElementById("flash-logger-dropdown");
      if (dd && !dd.classList.contains("hidden")) dd.classList.add("hidden");
    }
  });

  // Click outside to close dropdown
  document.addEventListener("click", function (e) {
    var toggle = document.getElementById("flash-logger-toggle");
    var dd = document.getElementById("flash-logger-dropdown");
    if (!dd || dd.classList.contains("hidden")) return;
    if (toggle && toggle.contains(e.target)) return;
    if (!dd.contains(e.target)) dd.classList.add("hidden");
  });
});
