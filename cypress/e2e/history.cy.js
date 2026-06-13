describe("Agent Job Run History & Console Details E2E Tests", () => {
  beforeEach(() => {
    cy.visit("/agents");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  it("can navigate to job history and view job details", () => {
    // Click on build-agent-01.example.com to open job run history
    cy.clickJobHistoryLink("build-agent-01.example.com");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
    cy.verifyJobHistoryPage("build-agent-01.example.com");

    // Click on a job name cell to view console logs (e.g. mock runs)
    // In mock data, there will be some runs displayed. Let's select one
    cy.get(".job-link").first().click();
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
    
    // Check that we are on the console detail view
    cy.get(".agent-job-run-detail-page").should("exist");
    cy.get(".console-log").should("exist");
  });
});
