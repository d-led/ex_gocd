describe("HTTP Test Agent Pipeline E2E Test", () => {
  beforeEach(() => {
    // Start the HTTP simulated agent over the real network
    cy.request("POST", "/api/test/start_http_agents", { count: "1" });
    
    // Go to dashboard
    cy.visit("/pipelines");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  it("registers http agent, triggers the demo pipeline, and streams logs", () => {
    // 1. Verify the HTTP agent is registered and present on the agents page
    cy.visit("/agents");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
    cy.get("table", { timeout: 10000 }).should("contain", "http-test-agent");

    // 2. Go back to pipelines dashboard
    cy.visit("/pipelines");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');

    // 3. Verify 'demo' pipeline is present on the page
    cy.verifyPipelineVisible("demo");

    // 4. Trigger execution by clicking the play button
    cy.triggerPipeline("demo");
    cy.get(".alert-info").should("contain", "triggered");

    // 5. Monitor the UI for the stage status to transition to passed (green)
    cy.get(".pipeline")
      .contains(".pipeline_name", "demo")
      .parents(".pipeline")
      .find(".pipeline_stage.passed", { timeout: 20000 })
      .should("exist");

    // 6. Navigate directly to the Job Details Console tab
    cy.get(".pipeline")
      .contains(".pipeline_name", "demo")
      .parents(".pipeline")
      .find(".pipeline_instance-label")
      .then(($label) => {
        const text = $label.text();
        const counter = text.match(/\d+/)[0];
        
        cy.visit(`/go/tab/build/detail/demo/${counter}/build/1/default`);
        cy.get('.phx-connected', { timeout: 10000 }).should('exist');

        // 7. Verify the logs streamed successfully from the HTTP agent
        cy.get("pre.whitespace-pre-wrap", { timeout: 10000 })
          .should("contain", "Preparing build workspace...")
          .and("contain", "Executing build task: mix test")
          .and("contain", "Build completed successfully.");
      });
  });
});
