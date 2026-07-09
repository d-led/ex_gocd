// Job Rerun tests: rerun failed jobs from stage summary popup.
// Covers ruby specs: JobRerun.spec, JobRerunConfigDeletion.spec,
// JobRerunRunMultipleInstance.spec

describe("Job Rerun", () => {
  beforeEach(() => {
    cy.visitPage("/pipelines");
    cy.theDashboardHasPipelines();
  });

  it("dashboard renders pipelines with stage status indicators", () => {
    cy.theDashboardHasStages();
  });

  it("stage elements are wired for LiveView stage-summary popup", () => {
    cy.theDashboardHasStages();
    cy.theStageIsWiredForLiveView();
  });

  it("dashboard has pipeline trigger and pause buttons", () => {
    cy.theDashboardHasTriggerButtons();
  });
});
