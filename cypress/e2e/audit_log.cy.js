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

  it("can type in search filters without error", () => {
    cy.get("input[name='actor']").type("test_user");
    cy.get("input[name='actor']").should("have.value", "test_user");
    cy.get("input[name='actor']").clear();
  });

  it("updates filters on keystroke", () => {
    cy.get("input[name='action']").type("pipeline_trigger");
    cy.get("input[name='action']").should("have.value", "pipeline_trigger");
  });
});
