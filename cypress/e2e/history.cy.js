// Agent Job Run History tests.
// Covers ruby specs: job_details_spec.rb, agents_api.rb

describe("Agent Job Run History", () => {
  beforeEach(() => {
    cy.visitPage("/agents");
  });

  it("can discover an agent and navigate to its job history", () => {
    // Discover first agent — uses dynamic data, not structural assertion
    cy.get(".agent-name, .agents-table tbody tr td:first-child")
      .first()
      .invoke("text")
      .then((name) => {
        if (name && name.trim()) {
          cy.clickJobHistoryLink(name.trim());
          cy.verifyJobHistoryPage(name.trim());
        }
      });
  });
});
