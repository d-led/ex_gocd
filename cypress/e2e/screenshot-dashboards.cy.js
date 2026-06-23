/// <reference types="cypress" />

/**
 * Auto-screenshot spec for Jaeger & Grafana dashboards.
 * Run via: bash scripts/update-screenshots-dashboards-cypress.sh
 * (NOT included in default `npm run cypress:run`)
 *
 * Uses absolute URLs — independent of ex_gocd baseUrl.
 * Gracefully skips if services are not reachable.
 */

const READY = { timeout: 10000 };

const JAEGER_SEARCH = "http://localhost:16686/search";
const GRAFANA = "http://localhost:3000";

describe("Auto screenshot — dashboards", () => {
  // ── Jaeger: Search results for ex_gocd service ──────────────

  it("jaeger search results", function () {
    cy.request({ url: JAEGER_SEARCH, failOnStatusCode: false }).then((resp) => {
      if (resp.status !== 200) {
        cy.log(`** SKIP: Jaeger not reachable (${resp.status})`);
        this.skip();
        return;
      }
      cy.visit(`${JAEGER_SEARCH}?service=ex_gocd&lookback=24h&limit=20`);
      cy.get("header", READY);
      cy.contains("button", "Find Traces").click();
      // Wait, then check if any results appeared
      cy.wait(3000);
      cy.get("body").then(($body) => {
        const hasResults =
          $body.find('[data-testid="trace"]').length > 0 ||
          $body.find('a[href*="/trace/"]').length > 0 ||
          $body.find("table tbody tr").length > 0;
        if (!hasResults) {
          cy.log("** SKIP: no traces found for ex_gocd in last 24h");
          this.skip();
          return;
        }
      });
      cy.appScreenshot("jaeger-search-results");
    });
  });

  // ── Jaeger: Trace detail (pipeline trigger trace) ──────────

  it("jaeger trace detail", function () {
    // Use Jaeger API to find the richest pipeline.trigger trace
    const api =
      "http://localhost:16686/api/traces?service=ex_gocd&limit=20&lookback=24h";
    cy.request({ url: api, failOnStatusCode: false }).then((resp) => {
      if (resp.status !== 200 || !resp.body.data || !resp.body.data.length) {
        cy.log("** SKIP: Jaeger API returned no traces");
        this.skip();
        return;
      }
      // Prefer a trace with pipeline.trigger AND the most spans (richest waterfall)
      let best = null;
      for (const t of resp.body.data) {
        const ops = (t.spans || []).map((s) => s.operationName);
        const hasTrigger = ops.some((o) => o === "pipeline.trigger");
        const score = (hasTrigger ? 1000 : 0) + (t.spans || []).length;
        if (!best || score > best._score) {
          best = t;
          best._score = score;
        }
      }
      if (!best) {
        cy.log("** SKIP: no suitable trace found");
        this.skip();
        return;
      }
      const ops = (best.spans || []).map((s) => s.operationName);
      cy.log(
        `Trace: ${best.traceID} (${ops.length} spans: ${ops.slice(0, 8).join(", ")}...)`,
      );
      cy.visit(`http://localhost:16686/trace/${best.traceID}`);
      cy.get("header", READY);
      cy.wait(3000);
      cy.appScreenshot("jaeger-trace-detail");
    });
  });

  // ── Jaeger: Agent trace (separate service) ──────────────────

  it("jaeger agent trace", function () {
    const api =
      "http://localhost:16686/api/traces?service=gocd-agent&limit=5&lookback=24h";
    cy.request({ url: api, failOnStatusCode: false }).then((resp) => {
      if (resp.status !== 200 || !resp.body.data || !resp.body.data.length) {
        cy.log("** SKIP: no agent traces found");
        this.skip();
        return;
      }
      // Pick the trace with the most spans
      let best = null;
      for (const t of resp.body.data) {
        if (!best || (t.spans || []).length > (best.spans || []).length) {
          best = t;
        }
      }
      if (!best) {
        cy.log("** SKIP: no suitable agent trace");
        this.skip();
        return;
      }
      const ops = (best.spans || []).map((s) => s.operationName);
      cy.log(
        `Agent trace: ${best.traceID} (${ops.length} spans: ${ops.join(", ")})`,
      );
      cy.visit(`http://localhost:16686/trace/${best.traceID}`);
      cy.get("header", READY);
      cy.wait(2000);
      cy.appScreenshot("jaeger-agent-trace");
    });
  });

  // ── Grafana: Pipeline Observability (default home) ──────────

  it("grafana pipeline observability", function () {
    cy.request({ url: `${GRAFANA}/`, failOnStatusCode: false }).then((resp) => {
      if (resp.status !== 200) {
        cy.log(`** SKIP: Grafana not reachable (${resp.status})`);
        this.skip();
        return;
      }
      cy.visit(GRAFANA);
      cy.get("header, .main-view, .dashboard-container, .page-header", READY);
      cy.wait(3000); // let stat panels fetch Jaeger data
      cy.appScreenshot("grafana-pipeline-obs");
    });
  });

  // ── Grafana: Service Overview ───────────────────────────────

  it("grafana service overview", function () {
    cy.request({
      url: `${GRAFANA}/d/ci-service-overview`,
      failOnStatusCode: false,
    }).then((resp) => {
      if (resp.status !== 200) {
        cy.log(
          `** SKIP: Grafana Service Overview not reachable (${resp.status})`,
        );
        this.skip();
        return;
      }
      cy.visit(`${GRAFANA}/d/ci-service-overview`);
      cy.get("header, .main-view, .dashboard-container", READY);
      cy.wait(3000);
      cy.appScreenshot("grafana-service-overview");
    });
  });

  // ── Grafana: Logs viewer ────────────────────────────────────

  it("grafana logs", function () {
    cy.request({
      url: `${GRAFANA}/d/ci-logs`,
      failOnStatusCode: false,
    }).then((resp) => {
      if (resp.status !== 200) {
        cy.log(`** SKIP: Grafana Logs not reachable (${resp.status})`);
        this.skip();
        return;
      }
      // Expand to 7 days to increase chance of log data
      cy.visit(`${GRAFANA}/d/ci-logs?from=now-7d&to=now`);
      cy.get("header, .main-view, .dashboard-container", READY);
      cy.wait(4000); // Loki queries can be slow
      cy.appScreenshot("grafana-logs");
    });
  });
});
