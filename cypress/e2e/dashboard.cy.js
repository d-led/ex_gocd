describe("Pipeline Dashboard E2E Tests", () => {
  beforeEach(() => {
    cy.visit("/pipelines");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  it("successfully loads dashboard and displays pipeline groups", () => {
    cy.verifyDashboardLoaded();
    cy.verifyPipelineVisible("build-linux");
    cy.verifyPipelineVisible("deploy-staging");
  });

  it("can filter pipelines by name via the search box", () => {
    cy.verifyDashboardLoaded();
    cy.searchPipelines("linux");
    cy.verifyPipelineVisible("build-linux");
    cy.verifyPipelineNotVisible("deploy-staging");

    cy.searchPipelines("");
    cy.verifyPipelineVisible("build-linux");
    cy.verifyPipelineVisible("deploy-staging");
  });

  it("allows triggering a pipeline execution", () => {
    cy.verifyDashboardLoaded();
    cy.triggerPipeline("build-linux");
    cy.get(".alert-info").should("contain", "triggered");
  });
});
