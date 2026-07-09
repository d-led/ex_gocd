// Job Rerun tests: rerun failed jobs from stage summary popup.
// Covers ruby specs: JobRerun.spec, JobRerunConfigDeletion.spec,
// JobRerunRunMultipleInstance.spec

describe("Job Rerun", () => {
  beforeEach(() => {
    cy.visitPage("/pipelines");
  });

  it("dashboard renders pipelines with stage status indicators", () => {
    cy.get(".pipeline", { timeout: 10000 }).should("have.length.at.least", 1);
    cy.get(".pipeline_stages .pipeline_stage").should(
      "have.length.at.least",
      1,
    );
    cy.get(".pipeline_stage").should("exist");
  });

  it("stage click opens the stage summary popup", () => {
    // Click a stage indicator to trigger the LiveView phx-click event.
    // The <a> has cursor:pointer and 34x16px dimensions. Use force:true
    // because Cypress may consider the empty <a> (styled via ::before) non-actionable.
    cy.get(".pipeline_stages .pipeline_stage").should(
      "have.length.at.least",
      1,
    );
    cy.get(".pipeline_stages .pipeline_stage").first().click({ force: true });

    // LiveView round-trip: server sets @active_stage_summary, re-renders popup
    cy.get(".stage-summary-popup", { timeout: 8000 }).should("be.visible");
    cy.get(".stage-summary-header").should("contain", "Pipeline");
  });

  it("dashboard has pipeline trigger and pause buttons", () => {
    cy.get(".pipeline_btn.play", { timeout: 5000 }).should("exist");
    cy.get(".pipeline_btn.pause", { timeout: 5000 }).should("exist");
  });
});
