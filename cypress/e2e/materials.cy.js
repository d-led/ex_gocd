describe("Materials Page E2E Tests", () => {
  beforeEach(() => {
    // Visit materials page directly and wait for LiveView connection
    cy.visit("/materials");
    // Ensure LiveView has connected successfully
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  it("should load the materials page successfully", () => {
    cy.verifyMaterialsPageLoaded();
    cy.get("h1").should("contain", "Materials");
  });

  it("should display configured SCM materials cards with correct badges and details", () => {
    // Check that Git SCM card details from mock data exist
    cy.verifyMaterialVisible("https://github.com/gocd/gocd.git");
    cy.get(".material-card").first().within(() => {
      cy.get(".material-type-badge").should("contain", "git");
      cy.get(".material-status").should("contain", "Active (polling)");
      cy.get(".material-detail-item").should("contain", "Branch:").and("contain", "master");
    });
  });

  it("should filter the materials list using the search bar", () => {
    // Search for docs repo SCM
    cy.searchMaterials("docs.git");
    cy.verifyMaterialVisible("https://github.com/gocd/docs.git");
    cy.verifyMaterialNotVisible("https://github.com/gocd/gocd.git");

    // Search for nonexistent repo
    cy.searchMaterials("nonexistent-scm-repo");
    cy.get(".dashboard-message").should("contain", "No materials found");
  });

  it("should link pipeline badges back to the dashboard with search pre-filled", () => {
    // Find doc build material
    cy.searchMaterials("docs-build");
    
    // Click on the docs-build pipeline badge link
    cy.clickMaterialPipelineBadge("docs-build");
    
    // Should redirect to dashboard /pipelines
    cy.url().should("include", "/pipelines?search=docs-build");
    
    // Ensure dashboard page is loaded and pipeline-search input is pre-populated
    cy.verifyDashboardLoaded();
    cy.get("#pipeline-search").should("have.value", "docs-build");
    
    // Ensure only the selected pipeline is visible on dashboard
    cy.verifyPipelineVisible("docs-build");
    cy.verifyPipelineNotVisible("build-linux");
  });
});
