// Pipeline Dashboard tests.
// Covers ruby specs: new_pipeline_dashboard_spec.rb, dashboard_stage_overview_spec.rb

describe("Pipeline Dashboard", () => {
  beforeEach(() => {
    cy.visitPage("/pipelines");
    cy.theDashboardHasPipelines();
  });

  it("shows pipeline groups with stage status indicators", () => {
    cy.theDashboardHasStages();
  });

  it("filters pipelines by name via the search box", () => {
    cy.get(".pipeline_name")
      .first()
      .invoke("text")
      .then((name) => {
        const trimmed = name.trim();
        cy.searchPipelines(trimmed);
        cy.verifyPipelineVisible(trimmed);

        cy.searchPipelines("");
        cy.theDashboardHasPipelines();
      });
  });

  it("can trigger a pipeline execution via the play button", () => {
    cy.get(".pipeline")
      .first()
      .within(() => {
        cy.get(".pipeline_btn.play").click();
      });
    cy.get(".toast, .alert", { timeout: 5000 }).should("exist");
  });

  it("has pipeline trigger and pause buttons", () => {
    cy.theDashboardHasTriggerButtons();
  });
});
