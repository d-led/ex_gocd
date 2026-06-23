describe("HTTP Test Agent Pipeline E2E Test", () => {
  beforeEach(() => {
    cy.startHttpAgents(1);
    cy.goToDashboard();
  });

  it("registers http agent, triggers the demo pipeline, and streams logs", () => {
    cy.whenPageHasAll(["demo", "http-test-agent"], () => {
      // Verify the agent registered
      cy.goToAgents();
      cy.verifyAgentExists("http-test-agent");

      // Trigger the demo pipeline
      cy.goToDashboard();
      cy.verifyPipelineVisible("demo");
      cy.triggerPipeline("demo");
      cy.theFlashSays("triggered");

      // Wait for the build stage to pass
      cy.thePipelineStagePassed("demo");

      // Navigate to the job console and verify logs
      cy.navigateToJobConsole("demo", "build", "1", "default", "git init");
    });
  });
});
