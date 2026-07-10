// Pipeline Comparison tests.
// Covers ruby specs: compare_pipelines_spec.rb

describe("Pipeline Comparison", () => {
  beforeEach(() => {
    cy.visitPage("/pipelines");
    cy.theDashboardHasPipelines();
  });

  it("navigates to VSM from dashboard", () => {
    cy.navigateToVSMFromDashboard();
    cy.url({ timeout: 5000 }).should("include", "/pipelines/value_stream_map/");
    cy.get("h1", { timeout: 5000 }).should("exist");
  });

  it("compare page loads for a pipeline", () => {
    cy.get(".pipeline_name")
      .first()
      .invoke("text")
      .then((name) => {
        cy.goToComparePage(name.trim());
        cy.theComparePageLoaded();
      });
  });
});
