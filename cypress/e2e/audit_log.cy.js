/// <reference types="cypress" />

describe("Audit Log", () => {
  beforeEach(() => {
    cy.visit("/admin/audit_log");
  });

  it("loads and provides search and date-range filters", () => {
    cy.thePageShows("Audit Log");

    cy.filterAuditLogByActor("test_user");
    cy.theAuditLogActorFilterIs("test_user");
    cy.filterAuditLogByAction("pipeline_trigger");
    cy.theAuditLogActionFilterIs("pipeline_trigger");
    cy.theAuditLogHasResourceFilters();
    cy.theAuditLogHasDateRangeFilters();
  });
});
