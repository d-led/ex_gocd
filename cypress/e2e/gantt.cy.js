/// <reference types="cypress" />

/**
 * Stage Duration Chart tests (match GoCD's stage stats graph).
 * Discovers a pipeline with runs dynamically — no hardcoded names.
 */

describe("Stage Duration Chart", () => {
  before(() => {
    cy.loginAsAdmin();
  });

  beforeEach(() => {
    // Discover a pipeline with runs
    cy.navigateAndVerify("/pipelines", ".dashboard");
    cy.discoverFirstPipeline();
    cy.get("@pipeline").then(function (p) {
      if (!p.counter) {
        cy.log("** SKIP: no pipeline runs");
        cy.state("runnable").skip();
      }
    });
  });

  it("renders with pipeline name in title", function () {
    cy.get("@pipeline").then(function (p) {
      cy.visit(`/stage-duration/${p.name}`);
      cy.get('[data-test-id="gantt-title"]', { timeout: 10000 })
        .should("be.visible")
        .and("contain", p.name);
    });
  });

  it("shows stage duration charts or empty state", function () {
    cy.get("@pipeline").then(function (p) {
      cy.visit(`/stage-duration/${p.name}`);
      // Either charts render with legend, or the no-data message shows
      cy.get("body").then(($body) => {
        const hasPassed = $body.text().includes("Passed");
        const hasNoRuns = $body.text().includes("No pipeline runs");
        expect(hasPassed || hasNoRuns, "should show charts or no-runs message")
          .to.be.true;
      });
    });
  });

  it("navigates via /go/gantt/:name alias", function () {
    cy.get("@pipeline").then(function (p) {
      cy.visit(`/go/stage-duration/${p.name}`);
      cy.get('[data-test-id="gantt-title"]', { timeout: 10000 })
        .should("be.visible")
        .and("contain", p.name);
    });
  });
});
