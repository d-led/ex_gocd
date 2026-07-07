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

  it("shows stage duration charts with Passed/Failed legend", function () {
    cy.get("@pipeline").then(function (p) {
      cy.visit(`/stage-duration/${p.name}`);
      cy.contains("Passed", { timeout: 10000 }).should("be.visible");
      cy.contains("Failed", { timeout: 10000 }).should("be.visible");
      // At least one SVG chart rendered
      cy.get("svg").should("exist");
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
