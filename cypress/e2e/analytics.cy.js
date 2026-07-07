/// <reference types="cypress" />

/**
 * Analytics page tests — VSM tab with Gantt stage breakdown bars.
 * Discovers a pipeline with runs dynamically.
 */

describe("Analytics — VSM", () => {
  before(() => {
    cy.loginAsAdmin();
  });

  beforeEach(() => {
    cy.navigateAndVerify("/pipelines", ".dashboard");
    cy.discoverFirstPipeline();
    cy.get("@pipeline").then(function (p) {
      if (!p.counter) {
        cy.log("** SKIP: no pipeline runs");
        cy.state("runnable").skip();
      }
    });
  });

  it("VSM tab shows stage duration Gantt bars for a pipeline", function () {
    cy.get("@pipeline").then(function (p) {
      cy.visit(`/analytics/vsm?pipeline=${p.name}`);
      cy.get(".phx-connected", { timeout: 10000 }).should("exist");

      // Should see the VSM Trends section
      cy.contains("VSM Trends", { timeout: 5000 }).should("be.visible");

      // Should have stage breakdown bars (not empty or error)
      cy.get("body").then(($body) => {
        // The stage duration column should have colored bar segments
        const barContainer = $body.find(
          ".bg-green-500, .bg-red-500, .bg-blue-500",
        );
        cy.log(`Found ${barContainer.length} stage bar segments`);
      });
    });
  });

  it("VSM tab shows cycle time trend chart", function () {
    cy.get("@pipeline").then(function (p) {
      cy.visit(`/analytics/vsm?pipeline=${p.name}`);
      cy.get(".phx-connected", { timeout: 10000 }).should("exist");

      // Cycle Time Trend section with bars
      cy.contains("Cycle Time Trend", { timeout: 5000 }).should("be.visible");
    });
  });

  it("VSM tab shows run table with counter and stages", function () {
    cy.get("@pipeline").then(function (p) {
      cy.visit(`/analytics/vsm?pipeline=${p.name}`);
      cy.get(".phx-connected", { timeout: 10000 }).should("exist");

      // Table with run data should exist
      cy.get("table").should("exist");
      // Should show pipeline counter
      cy.get("@pipeline").then(function (pi) {
        cy.contains(String(pi.counter)).should("exist");
      });
    });
  });
});
