// Pipeline Locking tests.
// Covers ruby specs: pipeline_api_spec.rb, stage_details_spec.rb

describe("Pipeline Locking", () => {
  const pipeline = "demo";

  beforeEach(() => {
    cy.visitPage("/pipelines");
    cy.theDashboardHasPipelines();
  });

  it("given a pipeline, when it is not locked, then it is schedulable", () => {
    cy.verifyPipelineIsNotLocked(pipeline);
  });

  it("given an unlocked pipeline, when I unlock it, then it stays unlocked", () => {
    cy.unlockPipeline(pipeline);
    cy.verifyPipelineIsNotLocked(pipeline);
  });

  it("given an unlocked pipeline, when triggered via API, then it is accepted", () => {
    cy.verifyPipelineIsNotLocked(pipeline);
    cy.request({
      method: "POST",
      url: `/api/pipelines/${pipeline}/schedule`,
      headers: {
        accept: "application/vnd.go.cd+json",
        "X-GoCD-Confirm": "true",
      },
    }).then((resp) => {
      expect(resp.status).to.eq(202);
    });
  });
});
