describe("Agents Management E2E Tests", () => {
  beforeEach(() => {
    cy.visit("/agents");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  it("loads the agents page and displays agent tabs", () => {
    cy.verifyActiveTab("STATIC");
    cy.verifyAgentExists("build-agent-01.example.com");
  });

  it("can switch between static and elastic agent tabs", () => {
    cy.selectAgentTab("ELASTIC");
    cy.verifyActiveTab("ELASTIC");
    cy.verifyAgentExists("elastic-agent-k8s-abc123");
    cy.verifyAgentNotExist("build-agent-01.example.com");
  });

  it("can filter agents using the search box", () => {
    cy.get(".search-box input").type("vanilla");
    cy.verifyAgentExists("vanilla-agent");
    cy.verifyAgentNotExist("build-agent-01.example.com");
  });

  it("supports bulk selection and bulk actions (enable/disable)", () => {
    cy.verifyAgentState("build-agent-01.example.com", "idle");
    
    // Toggle first agent
    cy.toggleAgentSelection("build-agent-01.example.com");
    cy.performBulkAction("disable");
    cy.get(".alert-info").should("contain", "disabled");

    cy.toggleAgentSelection("build-agent-01.example.com");
    cy.performBulkAction("enable");
    cy.get(".alert-info").should("contain", "enabled");
  });
});
