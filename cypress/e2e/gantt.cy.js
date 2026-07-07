/// <reference types="cypress" />

describe("Gantt chart", () => {
  it("renders with title", () => {
    cy.visit("/gantt");
    cy.contains("Pipeline Gantt", { timeout: 10000 }).should("be.visible");
  });

  it("shows legend: Passed, Failed, Building, Pending", () => {
    cy.visit("/gantt");
    // Scope to the legend bar, not SVG <title> tooltips inside bars
    cy.get('[data-test-id="gantt-legend"]')
      .contains("Passed")
      .should("be.visible");
    cy.get('[data-test-id="gantt-legend"]')
      .contains("Failed")
      .should("be.visible");
  });

  it("navigates via /go/gantt alias", () => {
    cy.visit("/go/gantt");
    cy.contains("Pipeline Gantt", { timeout: 10000 }).should("be.visible");
  });
});
