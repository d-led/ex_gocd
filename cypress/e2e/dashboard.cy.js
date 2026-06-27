describe("Pipeline Dashboard", () => {
  beforeEach(() => {
    cy.visitPage("/pipelines");
  });

  it("loads and displays pipeline groups", () => {
    // Verify dashboard loads with pipeline entries — use any pipeline that exists
    cy.get(".pipeline", { timeout: 10000 }).should("have.length.at.least", 1);
    cy.get(".pipeline_name").should("have.length.at.least", 1);
  });

  it("filters pipelines by name via the search box", () => {
    // Get the first pipeline name and search for it
    cy.get(".pipeline_name")
      .first()
      .invoke("text")
      .then((name) => {
        const trimmed = name.trim();
        cy.searchPipelines(trimmed);
        cy.get(".pipeline_name").should("contain", trimmed);

        cy.searchPipelines("");
        cy.get(".pipeline").should("have.length.at.least", 1);
      });
  });

  it("triggers a pipeline execution via the play button", () => {
    // Find first pipeline with a play button and trigger it
    cy.get(".pipeline")
      .first()
      .within(() => {
        cy.get(".pipeline_btn.play").click();
      });
    // Flash should appear (may auto-dismiss quickly — check for any flash toast)
    cy.get(".toast, .alert", { timeout: 5000 }).should("exist");
  });
});
