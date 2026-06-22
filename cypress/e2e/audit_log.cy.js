/// <reference types="cypress" />

describe("Audit Log", () => {
  beforeEach(() => {
    cy.visit("/admin/audit_log");
  });

  it("loads and provides search and date-range filters", () => {
    cy.thePageShows("Audit Log");

    cy.theAuditLogAcceptsActorFilter();
    cy.theAuditLogAcceptsActionFilter();
    cy.theAuditLogHasResourceFilters();
    cy.theAuditLogHasDateRangeFilters();
  });
});
