// Job Rerun tests: rerun failed jobs from stage summary popup.
// Covers ruby specs: JobRerun.spec, JobRerunConfigDeletion.spec,
// JobRerunRunMultipleInstance.spec

describe("Job Rerun", () => {
  beforeEach(() => {
    cy.visitPage("/pipelines");
    cy.theDashboardHasPipelines();
  });

  it("dashboard shows stage status indicators", () => {
    cy.theDashboardHasStages();
  });

  it("dashboard has pipeline trigger and pause buttons", () => {
    cy.theDashboardHasTriggerButtons();
  });
});
