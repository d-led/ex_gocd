describe("Agents Management E2E Tests", () => {
  beforeEach(() => {
    cy.visit("/agents");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  it("loads the agents page with toolbar and tabs", () => {
    cy.verifyActiveTab("STATIC");
    cy.get(".bulk-actions").should("exist");
    // Toolbar buttons should exist
    cy.contains("button", "DELETE").should("exist");
    cy.contains("button", "ENABLE").should("exist");
    cy.contains("button", "DISABLE").should("exist");
    cy.contains("button", "SCHEDULE TEST JOB").should("exist");
  });

  it("displays agent count stats", () => {
    cy.contains("Total").should("exist");
    cy.contains("Enabled").should("exist");
    cy.contains("Disabled").should("exist");
  });

  it("can switch between static and elastic agent tabs", () => {
    cy.selectAgentTab("ELASTIC");
    cy.verifyActiveTab("ELASTIC");
    cy.selectAgentTab("STATIC");
    cy.verifyActiveTab("STATIC");
  });

  it("bulk delete is gated by confirmation dialog", () => {
    cy.contains("button", "DELETE").should("have.attr", "data-confirm");
  });

  it("has checkboxes for agent selection", () => {
    cy.get(".checkbox-cell input").should("exist");
  });

  it("can filter agents via search", () => {
    cy.get(".search-box input").type("dam2");
    cy.contains("dam2.fritz.box").should("exist");
  });

  it("schedule test job button is clickable", () => {
    cy.contains("button", "SCHEDULE TEST JOB").click();
    // Should show flash message about scheduling
    cy.get(".alert-info").should("contain", "scheduled");
  });
});
