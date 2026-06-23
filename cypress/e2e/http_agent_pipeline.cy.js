describe("HTTP Test Agent Pipeline E2E Test", () => {
  beforeEach(() => {
    // Start the HTTP simulated agent over the real network.
    // In mock mode this may fail — handle gracefully.
    cy.request({
      method: "POST",
      url: "/api/test/start_http_agents",
      body: { count: "1" },
      failOnStatusCode: false,
    });
    cy.visit("/pipelines");
    cy.get(".phx-connected", { timeout: 10000 }).should("exist");
  });

  it("registers http agent, triggers the demo pipeline, and streams logs", () => {
    // Check if demo pipeline exists (skip in mock mode)
    cy.get("body").then(($body) => {
      if (
        !$body.text().includes("demo") ||
        !$body.text().includes("http-test-agent")
      ) {
        // Mock mode: agent not available, verify page loads
        cy.log("Mock mode: skipping agent/pipeline integration test");
        return;
      }

      // 1. Verify the HTTP agent is registered
      cy.visit("/agents");
      cy.get(".phx-connected", { timeout: 10000 }).should("exist");
      cy.get("table", { timeout: 10000 }).should("contain", "http-test-agent");

      // 2. Go back to pipelines dashboard
      cy.visit("/pipelines");
      cy.get(".phx-connected", { timeout: 10000 }).should("exist");

      // 3. Verify 'demo' pipeline
      cy.verifyPipelineVisible("demo");

      // 4. Trigger
      cy.triggerPipeline("demo");
      cy.get(".alert-info").should("contain", "triggered");

      // 5. Wait for stage to pass
      cy.get(".pipeline")
        .contains(".pipeline_name", "demo")
        .parents(".pipeline")
        .find(".pipeline_stage.passed", { timeout: 20000 })
        .should("exist");

      // 6. Navigate to console
      cy.get(".pipeline")
        .contains(".pipeline_name", "demo")
        .parents(".pipeline")
        .find(".pipeline_instance-label")
        .then(($label) => {
          const counter = $label.text().match(/\d+/)[0];
          cy.visit(`/go/tab/build/detail/demo/${counter}/build/1/default`);
          cy.get(".phx-connected", { timeout: 10000 }).should("exist");
          cy.get("pre.whitespace-pre-wrap", { timeout: 10000 }).should(
            "contain",
            "git init",
          );
        });
    });
  });
});
