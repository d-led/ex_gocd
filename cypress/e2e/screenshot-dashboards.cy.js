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
  // ── Jaeger: Trace Search ────────────────────────────────────

  it("jaeger search", function () {
    cy.request({ url: JAEGER_SEARCH, failOnStatusCode: false }).then((resp) => {
      if (resp.status !== 200) {
        cy.log(`** SKIP: Jaeger not reachable (${resp.status})`);
        this.skip();
        return;
      }
      cy.visit(JAEGER_SEARCH);
      // Jaeger might not have .phx-connected; wait for the search form
      cy.get("form[role='search'], .jaeger-ui-filter, input[placeholder*='Search'], header", READY);
      cy.appScreenshot("jaeger-search");
    });
  });

  // ── Jaeger: Find a trace for ex_gocd ────────────────────────

  it("jaeger trace", function () {
    cy.request({ url: JAEGER_SEARCH, failOnStatusCode: false }).then((resp) => {
      if (resp.status !== 200) {
        cy.log("** SKIP: Jaeger not reachable");
        this.skip();
        return;
      }
      // Search for ex_gocd traces
      cy.visit(`${JAEGER_SEARCH}?service=ex_gocd&lookback=1h&limit=20`);
      cy.get("header", READY);
      cy.wait(2000); // let trace results load
      cy.appScreenshot("jaeger-trace-search");
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
      cy.wait(2000); // let dashboard panels render
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
        cy.log(`** SKIP: Grafana Service Overview not reachable (${resp.status})`);
        this.skip();
        return;
      }
      cy.visit(`${GRAFANA}/d/ci-service-overview`);
      cy.get("header, .main-view, .dashboard-container", READY);
      cy.wait(2000);
      cy.appScreenshot("grafana-service-overview");
    });
  });

  // ── Grafana: Logs ───────────────────────────────────────────

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
      cy.visit(`${GRAFANA}/d/ci-logs`);
      cy.get("header, .main-view, .dashboard-container", READY);
      cy.wait(2000);
      cy.appScreenshot("grafana-logs");
    });
  });
});
