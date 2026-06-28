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

  describe("back-button navigation integrity", () => {
    it("stage icons remain clickable after navigating Back from a stage details page", () => {
      // Find a pipeline with stages
      cy.get(".pipeline_stages .pipeline_stage", { timeout: 10000 })
        .first()
        .click();

      // Should show stage summary popup
      cy.get(".stage-summary", { timeout: 5000 }).should("exist");

      // Click through to stage details
      cy.contains("a", "View Stage Details", { timeout: 5000 }).click();

      // Verify we're on a stage details page
      cy.url({ timeout: 5000 }).should("include", "/pipelines/");

      // Navigate Back
      cy.go("back");
      cy.url({ timeout: 5000 }).should("include", "/pipelines");

      // Wait for LiveView to reconnect after bfcache restore
      cy.wait(1000);

      // Stage icons should be clickable again
      cy.get(".pipeline_stages .pipeline_stage", { timeout: 10000 })
        .first()
        .click();

      // Popup should appear again
      cy.get(".stage-summary", { timeout: 5000 }).should("exist");
    });

    it("admin dropdown hovers work after navigating Back", () => {
      // Navigate to a sub-page first
      cy.get(".pipeline_name", { timeout: 5000 })
        .first()
        .click();

      cy.url({ timeout: 5000 }).should("include", "/pipelines/");

      // Navigate Back
      cy.go("back");
      cy.wait(1000);

      // Hover over admin dropdown
      cy.get("li.is-drop-down", { timeout: 5000 }).trigger("mouseenter");
      cy.get(".sub-navigation", { timeout: 5000 }).should("be.visible");

      cy.get("li.is-drop-down").trigger("mouseleave");
    });
  });
});
