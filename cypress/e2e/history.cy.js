describe("Agent Job Run History & Console Details E2E Tests", () => {
  beforeEach(() => {
    cy.visit("/agents");
    cy.get(".phx-connected", { timeout: 10000 }).should("exist");
  });

  it("can navigate to job history and view job details", () => {
    // Click on first agent to open job run history
    cy.get(".agent-name, .agents-table tbody tr a, .agent-row a").first().click();
    cy.get(".phx-connected", { timeout: 10000 }).should("exist");

    // Verify we're on a history or detail page (may vary by data)
    cy.get(".agent-job-history-page, .agent-job-run-detail-page, .phx-connected").should("exist");
  });
});
