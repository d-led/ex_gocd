describe("Pipeline Dashboard", () => {
  beforeEach(() => {
    cy.visitPage("/pipelines");
  });

  it("loads and displays pipeline groups", () => {
    cy.theDashboardShows("build-linux", "deploy-staging");
  });

  it("filters pipelines by name via the search box", () => {
    cy.theDashboardShows("build-linux", "deploy-staging");
    cy.searchPipelines("linux");
    cy.theDashboardShows("build-linux");
    cy.theDashboardDoesNotShow("deploy-staging");

    cy.searchPipelines("");
    cy.theDashboardShows("build-linux", "deploy-staging");
  });

  it("triggers a pipeline execution via the play button", () => {
    cy.theDashboardShows("build-linux");
    cy.triggerPipeline("build-linux");
    cy.theFlashSays("triggered");
  });
});
