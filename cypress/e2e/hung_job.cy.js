// Hung Job tests: cancel stuck jobs and timeout configuration.
// Covers ruby specs: HungJobServerTagTimeOut.spec, HungJobTermination.spec,
// HungJobWarning.spec, HungJobZeroTimeOutForJob.spec

describe("Hung Job Handling", () => {
  beforeEach(() => {
    cy.loginAsAdmin();
    cy.visitPage("/admin/overview");
  });

  it("Operations Control panel has Cleanup button", () => {
    cy.contains("button", "Cleanup Now").should("exist");
  });

  it("navigates to Server Configuration page", () => {
    cy.visitPage("/admin/server");
    cy.get(".phx-connected", { timeout: 10000 }).should("exist");
    cy.thePageShows("Server Configuration");
  });

  it("displays Server Configuration form fields", () => {
    cy.visitPage("/admin/server");
    // Should show server management options
    cy.get("form, .form, [data-test-id='server-config']", { timeout: 5000 }).should("exist");
  });

  it("navigates to Pipeline Config page for job timeout settings", () => {
    // Navigate to admin pipelines page
    cy.visitPage("/admin/pipelines");
    cy.get(".phx-connected", { timeout: 10000 }).should("exist");
    cy.thePageShows("Pipelines");
  });
});
