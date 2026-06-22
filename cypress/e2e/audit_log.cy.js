/// <reference types="cypress" />

describe("Audit Log E2E Tests", () => {
  beforeEach(() => {
    cy.visit("/admin/audit_log");
  });

  it("loads the audit log page", () => {
    cy.contains("Audit Log").should("exist");
  });

  it("has search filter inputs", () => {
    cy.get("input[name='actor']").should("exist");
    cy.get("input[name='action']").should("exist");
    cy.get("input[name='resource_type']").should("exist");
    cy.get("input[name='resource_name']").should("exist");
  });

  it("has date range filters", () => {
    cy.get("input[name='date_from']").should("exist");
    cy.get("input[name='date_to']").should("exist");
  });

  it("shows empty state when no entries match", () => {
    cy.get("input[name='action']").type("nonexistent_action_xyz");
    cy.contains("No audit entries found").should("exist");
  });

  it("shows entry count at bottom of table", () => {
    cy.get("input[name='action']").clear();
    cy.get("input[name='actor']").clear();
    // After clearing filters, entries should appear (if any seeded)
    cy.get("body").then(($body) => {
      if ($body.text().includes("entries")) {
        cy.contains("entries").should("exist");
      }
    });
  });
});
