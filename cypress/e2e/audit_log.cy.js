/// <reference types="cypress" />

describe("Audit Log", () => {
  beforeEach(() => {
    cy.loginAsAdmin();
    cy.visit("/admin/audit_log");
  });

  it("loads with page heading", () => {
    cy.get(".phx-connected", { timeout: 10000 }).should("exist");
    cy.get("h1, h2, .page-title, .heading").should("exist");
  });

  it("provides filter controls", () => {
    // Verify filter/search UI is present
    cy.get("input, select, button").should("have.length.at.least", 1);
  });
});
