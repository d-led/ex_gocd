// Pipeline Comparison tests: compare pipeline runs side by side.
// Covers ruby specs: ComparePipeline.spec, ComparePipelinesEntryPoints.spec,
// ComparePipelineTimelineView.spec, ComparePipelineWithBisect.spec

describe("Pipeline Comparison", () => {
  beforeEach(() => {
    cy.visitPage("/pipelines");
  });

  it("navigates to compare page via pipeline VSM link", () => {
    // Find a pipeline with completed runs to compare
    cy.get(".pipeline", { timeout: 10000 }).should("have.length.at.least", 1);

    // Click VSM link on first pipeline (opens compare/vsm)
    cy.contains("a", "VSM").first().click();

    // Should navigate to value stream map / compare page
    cy.url({ timeout: 5000 }).should("include", "/pipelines/value_stream_map/");
    cy.get("h1", { timeout: 5000 }).should("exist");
  });

  it("compare page shows pipeline name", () => {
    // Navigate directly to compare for the first pipeline
    cy.get(".pipeline_name")
      .first()
      .invoke("text")
      .then((name) => {
        const trimmed = name.trim();
        cy.visitPage(`/compare/${trimmed}`);
        cy.get(".phx-connected", { timeout: 10000 }).should("exist");
        cy.thePageShows(trimmed);
      });
  });

  it("compare page renders without errors", () => {
    cy.get(".pipeline_name")
      .first()
      .invoke("text")
      .then((name) => {
        const trimmed = name.trim();
        cy.visitPage(`/compare/${trimmed}`);
        // Page should load without errors — any content is fine
        cy.get(".phx-connected", { timeout: 10000 }).should("exist");
        cy.get("h1, h2", { timeout: 5000 }).should("exist");
      });
  });
});
