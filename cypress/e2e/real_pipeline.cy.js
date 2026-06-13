describe("Real Pipeline Execution E2E Test", () => {
  beforeEach(() => {
    // Go to dashboard (which shows real database pipelines in our test setup)
    cy.visit("/pipelines");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  it("triggers the real demo pipeline and runs it on the local agent", () => {
    // 1. Verify 'demo' pipeline is present on the page
    cy.verifyPipelineVisible("demo");

    // 2. Trigger execution by clicking the play button
    cy.triggerPipeline("demo");
    cy.get(".alert-info").should("contain", "triggered");

    // 3. Monitor the UI for the stage status to transition to passed (green)
    // The play button triggers the build. Since the local agent is active in the background,
    // it will run git clone and task execution. We wait up to 25 seconds for completion.
    cy.get(".pipeline", { timeout: 25000 })
      .contains(".pipeline_name", "demo")
      .parents(".pipeline")
      .find(".pipeline_stage.passed")
      .should("exist");

    // 4. Extract the newly generated counter from 'Instance: X' label
    cy.get(".pipeline")
      .contains(".pipeline_name", "demo")
      .parents(".pipeline")
      .find(".pipeline_instance-label")
      .then(($label) => {
        const text = $label.text(); // e.g. "Instance: 3"
        const counter = text.match(/\d+/)[0];
        
        // Navigate directly to the Job Details Console tab matching GoCD's URL pattern
        cy.visit(`/go/tab/build/detail/demo/${counter}/build/1/default`);
        cy.get('.phx-connected', { timeout: 10000 }).should('exist');

        // 5. Verify the logs streamed successfully from the agent and contain correct task output
        cy.get("pre.whitespace-pre-wrap", { timeout: 10000 })
          .should("contain", "git init")
          .and("contain", "git fetch")
          .and("contain", "hello from pipeline demo edited");
      });
  });
});
