// Pipeline Pause/Unpause tests.
// Covers ruby specs: pipeline_history_spec.rb, pipeline_api_spec.rb

describe("Pipeline Pause", () => {
  beforeEach(() => {
    cy.loginAsAdmin();
    cy.visitPage("/pipelines");
    cy.theDashboardHasPipelines();

    // Ensure at least one pipeline is unpaused
    cy.get("body").then(($body) => {
      if ($body.find(".pipeline_btn.pause").length === 0) {
        cy.get(".pipeline_btn.unpause").first().click();
        cy.get(".toast, .alert", { timeout: 5000 }).should("be.visible");
        cy.get(".pipeline_btn.pause", { timeout: 5000 }).should("exist");
      }
    });
  });

  it("opens pause modal and closes via X button", () => {
    cy.openPauseModal();
    cy.closePauseModalViaX();
    cy.thePauseModalIsClosed();
  });

  it("opens pause modal and closes via CLOSE button", () => {
    cy.openPauseModal();
    cy.closePauseModalViaButton();
    cy.thePauseModalIsClosed();
  });

  it("opens pause modal and closes via clicking outside", () => {
    cy.openPauseModal();
    cy.closePauseModalViaBackdrop();
    cy.thePauseModalIsClosed();
  });

  it("can open and close the modal multiple times", () => {
    cy.openPauseModal();
    cy.closePauseModalViaX();
    cy.thePauseModalIsClosed();

    cy.openPauseModal();
    cy.closePauseModalViaButton();
    cy.thePauseModalIsClosed();

    cy.openPauseModal();
    cy.closePauseModalViaBackdrop();
    cy.thePauseModalIsClosed();
  });
});

