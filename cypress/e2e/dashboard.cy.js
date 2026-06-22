describe("Pipeline Dashboard", () => {
  beforeEach(() => {
    cy.visitPage("/pipelines");
  });

  it("loads and displays pipeline groups", () => {
    cy.theDashboardShows("demo", "upstream-lib");
  });

  it("filters pipelines by name via the search box", () => {
    cy.theDashboardShows("demo", "upstream-lib");
    cy.iSearchPipelines("upstream");
    cy.theDashboardShows("upstream-lib");
    cy.theDashboardDoesNotShow("demo");

    cy.iSearchPipelines("");
    cy.theDashboardShows("demo", "upstream-lib");
  });

  it("triggers a pipeline execution via the play button", () => {
    cy.theDashboardShows("demo");
    cy.iTriggerPipelineRun("demo");
    cy.theFlashSays("triggered");
  });
});
