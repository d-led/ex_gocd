describe("Agents Management", () => {
  beforeEach(() => {
    cy.visitPage("/agents");
  });

  it("loads with agent table and controls", () => {
    cy.get(".agents-page, .phx-connected", { timeout: 10000 }).should("exist");
    cy.get(".agents-table").should("exist");
    // Check that agent rows exist
    cy.get(".agents-table tbody tr, .agent-row").should(
      "have.length.at.least",
      1,
    );
  });

  it("displays agent count statistics", () => {
    cy.get(".agents-page").should("contain", "Total");
    cy.get(".agents-page").should("contain", "Enabled");
    cy.get(".agents-page").should("contain", "Disabled");
  });

  it("shows agent search/filter functionality", () => {
    // Get first agent name and filter by it
    cy.get(".agent-name, .agents-table tbody tr td:first-child")
      .first()
      .invoke("text")
      .then((name) => {
        const trimmed = (name || "").trim();
        const query = trimmed || "agent";
        cy.get(
          'input[type="text"], #agent-search, input[placeholder*="Filter"]',
        )
          .first()
          .type(query, { force: true });
        cy.get(".agents-table tbody tr, .agent-row").should(
          "have.length.at.least",
          1,
        );
      });
  });

  it("has tab navigation for agent types", () => {
    // Check if tabs exist (STATIC/ELASTIC or similar)
    cy.get('.tab-button, [role="tab"]').should("have.length.at.least", 1);
  });
});
