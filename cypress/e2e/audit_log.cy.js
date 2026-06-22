/// <reference types="cypress" />

describe("Audit Log", () => {
  beforeEach(() => {
    cy.visit("/admin/audit_log");
  });

  it("loads and provides search and date-range filters", () => {
    cy.thePageShows("Audit Log");

    // Search filters
    cy.get("input[name='actor']").type("test_user").should("have.value", "test_user");
    cy.get("input[name='action']").type("pipeline_trigger").should("have.value", "pipeline_trigger");
    cy.get("input[name='resource_type']").should("exist");
    cy.get("input[name='resource_name']").should("exist");

    // Date range filters
    cy.get("input[name='date_from']").should("exist");
    cy.get("input[name='date_to']").should("exist");
  });
});
