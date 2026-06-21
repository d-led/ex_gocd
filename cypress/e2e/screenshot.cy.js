/// <reference types="cypress" />

/**
 * Auto-screenshot spec for ex_gocd documentation.
 * Run via: bash scripts/update-screenshots-cypress.sh
 * (NOT included in default `npm run cypress:run`)
 *
 * Every test discovers what's available dynamically — no hardcoded pipeline names.
 * If preconditions aren't met, the test skips with a log message instead of failing.
 */

const READY = { timeout: 10000 };

/**
 * Visit /pipelines, discover the first pipeline name + counter,
 * then invoke `cb(name, counter)`.  If no pipeline exists, skip the test.
 */
function withPipeline(runnable, cb) {
  cy.visit("/pipelines");
  cy.get(".phx-connected", READY);
  cy.get("body").then(($body) => {
    const nameEl = $body.find(".pipeline_name").first();
    if (!nameEl.length) {
      cy.log("** SKIP: no pipelines on dashboard");
      runnable.skip();
      return;
    }
    const name = nameEl.text().trim();

    const labelEl = $body.find(".pipeline_instance-label").first();
    let counter = null;
    if (labelEl.length) {
      const match = labelEl.text().match(/(\d+)/);
      if (match) counter = match[1];
    }

    cy.log(`Pipeline: ${name} counter=${counter || "?"}`);
    cb(name, counter);
  });
}

describe("Auto screenshot", () => {
  // ── Dashboard ────────────────────────────────────────────────

  it("dashboard", function () {
    cy.visit("/pipelines");
    cy.get(".phx-connected", READY);
    cy.get(".dashboard").should("exist");
    cy.appScreenshot("dashboard");
  });

  // ── Agents ───────────────────────────────────────────────────

  it("agents (static tab)", function () {
    cy.visit("/agents");
    cy.get(".phx-connected", READY);
    cy.get(".agents-page").should("exist");
    cy.appScreenshot("agents");
  });

  // ── Materials ────────────────────────────────────────────────

  it("materials", function () {
    cy.visit("/materials");
    cy.get(".phx-connected", READY);
    cy.get(".materials-page").should("exist");
    cy.appScreenshot("materials");
  });

  // ── Admin ────────────────────────────────────────────────────

  it("admin", function () {
    cy.visit("/admin");
    cy.get(".phx-connected", READY);
    cy.appScreenshot("admin");
  });

  // ── Analytics ────────────────────────────────────────────────

  it("analytics", function () {
    cy.visit("/analytics");
    cy.get(".phx-connected", READY);
    cy.appScreenshot("analytics");
  });

  // ── Pipeline activity ────────────────────────────────────────

  it("pipeline activity", function () {
    withPipeline(this, (name) => {
      cy.visit(`/pipeline/activity/${name}`);
      cy.get(".phx-connected", READY);
      cy.appScreenshot("pipeline-activity");
    });
  });

  // ── Pipeline config wizard ───────────────────────────────────

  it("pipeline config", function () {
    withPipeline(this, (name) => {
      cy.visit(`/go/admin/pipelines/${name}/edit/materials`);
      cy.get(".phx-connected", READY);
      cy.appScreenshot("pipeline-config");
    });
  });

  // ── Stage details ────────────────────────────────────────────

  it("stage details", function () {
    withPipeline(this, (name, counter) => {
      if (!counter) {
        cy.log("** SKIP: no pipeline counter (no completed runs)");
        this.skip();
        return;
      }
      const url = `/go/pipelines/${name}/${counter}/build/1`;
      cy.request({ url, failOnStatusCode: false }).then((resp) => {
        if (resp.status !== 200) {
          cy.log(`** SKIP: stage details returned ${resp.status}`);
          this.skip();
          return;
        }
        cy.visit(url);
        cy.get(".phx-connected", READY);
        cy.appScreenshot("stage-details");
      });
    });
  });

  // ── Job details (console log) ────────────────────────────────

  it("job details", function () {
    withPipeline(this, (name, counter) => {
      if (!counter) {
        cy.log("** SKIP: no pipeline counter (no completed runs)");
        this.skip();
        return;
      }
      const url = `/go/tab/build/detail/${name}/${counter}/build/1/default`;
      cy.request({ url, failOnStatusCode: false }).then((resp) => {
        if (resp.status !== 200) {
          cy.log(`** SKIP: job details returned ${resp.status}`);
          this.skip();
          return;
        }
        cy.visit(url);
        cy.get(".phx-connected", READY);
        cy.appScreenshot("job-details");
      });
    });
  });

  // ── VSM ──────────────────────────────────────────────────────

  it("value stream map", function () {
    withPipeline(this, (name, counter) => {
      if (!counter) {
        cy.log("** SKIP: no pipeline counter (no completed runs)");
        this.skip();
        return;
      }
      const url = `/go/pipelines/value_stream_map/${name}/${counter}`;
      cy.request({ url, failOnStatusCode: false }).then((resp) => {
        if (resp.status !== 200) {
          cy.log(`** SKIP: VSM returned ${resp.status}`);
          this.skip();
          return;
        }
        cy.visit(url);
        cy.get(".phx-connected", READY);
        cy.appScreenshot("vsm");
      });
    });
  });

  // ── Compare ──────────────────────────────────────────────────

  it("compare", function () {
    withPipeline(this, (name, counter) => {
      if (!counter) {
        cy.log("** SKIP: no pipeline counter (no completed runs)");
        this.skip();
        return;
      }
      const from = Math.max(1, Number(counter) - 1);
      const url = `/go/compare/${name}/${from}/with/${counter}`;
      cy.request({ url, failOnStatusCode: false }).then((resp) => {
        if (resp.status !== 200) {
          cy.log(`** SKIP: compare returned ${resp.status}`);
          this.skip();
          return;
        }
        cy.visit(url);
        cy.get(".compare-page, .phx-connected", READY);
        cy.appScreenshot("compare");
      });
    });
  });

  // ── Mobile navigation ────────────────────────────────────────

  it("dashboard mobile", function () {
    cy.viewport(375, 812);
    cy.visit("/pipelines");
    cy.get(".phx-connected", READY);
    cy.get(".site-header").should("be.visible");
    cy.appScreenshot("dashboard-mobile");
  });
});
