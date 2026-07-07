/// <reference types="cypress" />

describe("Gantt chart", () => {
  it("renders with title", () => {
    cy.visit("/gantt");
    cy.contains("Pipeline Gantt", { timeout: 10000 }).should("be.visible");
  });

  it("shows legend: Passed, Failed", () => {
    cy.visit("/gantt");
    cy.contains("Passed", { timeout: 10000 }).should("be.visible");
    cy.contains("Failed", { timeout: 10000 }).should("be.visible");
  });

  it("navigates via /go/gantt alias", () => {
    cy.visit("/go/gantt");
    cy.contains("Pipeline Gantt", { timeout: 10000 }).should("be.visible");
  });
});
