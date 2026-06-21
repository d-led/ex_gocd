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

  it("should display configured SCM materials cards with correct SCM logo and details when expanded", () => {
    // SCM card docs.git fingerprint
    const fingerprint = "8d78bc9f6c661806";
    cy.verifyMaterialVisible("https://github.com/gocd/docs.git");
    cy.verifySCMType(fingerprint, "git");
    
    // Expand card
    cy.expandMaterialCard(fingerprint);
    
    // Verify attributes inside expanded section
    cy.verifyAutoUpdateStatus(fingerprint, "Active (polling)");
    cy.verifyBranchName(fingerprint, "master");
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

  it("should link pipeline links inside Usages modal back to the dashboard with search pre-filled", () => {
    const fingerprint = "f828d66cdfa6d522"; // docs.git fingerprint
    
    // Open Usages modal
    cy.openUsagesModal(fingerprint);
    
    // Check usages modal content
    cy.verifyUsagesModalContains("docs-build");
    
    // Click on the docs-build pipeline link inside the usages modal
    cy.clickUsagesModalPipelineLink("docs-build");
    
    // Should redirect to dashboard /pipelines
    cy.url().should("include", "/pipelines?search=docs-build");
    
    // Ensure dashboard page is loaded and pipeline-search input is pre-populated
    cy.verifyDashboardLoaded();
    cy.get("#pipeline-search").should("have.value", "docs-build");
    
    // Ensure only the selected pipeline is visible on dashboard
    cy.verifyPipelineVisible("docs-build");
    cy.verifyPipelineNotVisible("build-linux");
  });

  it("should open Modifications modal, show historical list, filter by search, and close", () => {
    const fingerprint = "8d78bc9f6c661806"; // gocd.git fingerprint
    
    // Open Modifications modal
    cy.openModificationsModal(fingerprint);
    
    // Verify it contains historical modifications
    cy.verifyModificationsModalContains("upgrade actions and fix compilation warnings");
    
    // Search in modifications modal
    cy.searchModificationsInModal("upgrade");
    cy.verifyModificationsModalContains("upgrade actions");
    
    // Close the modal
    cy.closeModificationsModal();
  });
});
