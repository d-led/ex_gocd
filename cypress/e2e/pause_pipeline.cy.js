describe("Pipeline Pause/Unpause", () => {
  beforeEach(() => {
    cy.loginAsAdmin();
    cy.visitPage("/pipelines");
    // Wait for dashboard to render
    cy.get(".dashboard", { timeout: 10000 }).should("exist");
    cy.get(".pipeline", { timeout: 10000 }).should("have.length.at.least", 1);

    // Ensure at least one pipeline is unpaused — unpause the first paused one if needed
    cy.get("body").then(($body) => {
      const pauseBtns = $body.find(".pipeline_btn.pause");
      if (pauseBtns.length === 0) {
        // All pipelines are paused — unpause the first one
        cy.get(".pipeline_btn.unpause").first().click();
        cy.get(".toast, .alert", { timeout: 5000 }).should("be.visible");
        cy.get(".pipeline_btn.pause", { timeout: 5000 }).should("exist");
      }
    });
  });

  // ── Helpers ──────────────────────────────────────────────────────

  const openPauseModal = () => {
    cy.get(".pipeline_btn.pause").first().click();
    cy.get("#pause-modal", { timeout: 5000 }).should("be.visible");
    cy.get("#pause-modal").should("contain", "Pause pipeline");
  };

  const modalShouldBeClosed = () => {
    cy.get("#pause-modal").should("not.exist");
  };

  // ── Close via X (cross) button ──────────────────────────────────

  it("opens pause modal and closes via X (cross) button", () => {
    openPauseModal();

    // Click the × close button in the modal header
    cy.get("#pause-modal .close-btn").click();

    modalShouldBeClosed();
  });

  // ── Close via CLOSE button ──────────────────────────────────────

  it("opens pause modal and closes via CLOSE button", () => {
    openPauseModal();

    cy.get("#pause-modal-close").click();

    modalShouldBeClosed();
  });

  // ── Close via clicking outside (backdrop / phx-click-away) ──────

  it("opens pause modal and closes via clicking outside (click-away)", () => {
    openPauseModal();

    // Click the backdrop area (outside the modal)
    cy.get("#pause-modal-backdrop").click("topLeft");

    modalShouldBeClosed();
  });

  // ── Cycle: open → close via X → open → close via CLOSE → open → submit ──

  it("can open and close the modal multiple times without getting stuck", () => {
    // Round 1: close via X
    openPauseModal();
    cy.get("#pause-modal .close-btn").click();
    modalShouldBeClosed();

    // Round 2: close via CLOSE button
    openPauseModal();
    cy.get("#pause-modal-close").click();
    modalShouldBeClosed();

    // Round 3: close via click-away
    openPauseModal();
    cy.get("#pause-modal-backdrop").click("topLeft");
    modalShouldBeClosed();

    // Round 4: type a reason but then close via X (cancel — decide not to pause)
    openPauseModal();

    cy.get("#pause-cause-input").type("under maintenance");
    // Decide not to — close via X
    cy.get("#pause-modal .close-btn").click();
    modalShouldBeClosed();

    // Pipeline should still be unpaused (not changed state)
    cy.get(".pipeline").first().find(".pipeline_btn.pause", { timeout: 5000 }).should("exist");
  });

  // ── Submit pause → verify paused state → unpause ────────────────

  it("pauses a pipeline with a reason and then unpauses it", () => {
    openPauseModal();

    // Type a reason and submit
    cy.get("#pause-cause-input").type("scheduled maintenance window");
    cy.get("#pause-modal-ok").click();

    modalShouldBeClosed();

    // Flash message should confirm pause
    cy.get(".toast, .alert", { timeout: 5000 }).should("be.visible");

    // The FIRST pipeline should now be paused — its button should be unpause
    cy.get(".pipeline")
      .first()
      .within(() => {
        cy.get(".pipeline_btn.unpause", { timeout: 5000 }).should("exist");
        cy.get(".pipeline_pause-message", { timeout: 5000 }).should("exist");
      });

    // Now unpause the first pipeline
    cy.get(".pipeline").first().find(".pipeline_btn.unpause").click();

    // Flash message should confirm unpause
    cy.get(".toast, .alert", { timeout: 5000 }).should("be.visible");

    // The first pipeline should be unpaused now
    cy.get(".pipeline")
      .first()
      .within(() => {
        cy.get(".pipeline_btn.pause", { timeout: 5000 }).should("exist");
      });
  });

  // ── Cancel without entering a reason ────────────────────────────

  it("can cancel pausing — closing the modal does not change pipeline state", () => {
    // First, note the current state of the first pipeline
    cy.get(".pipeline")
      .first()
      .then(($pipeline) => {
        // Record whether this pipeline was already paused or not
        const wasPaused = $pipeline.find(".pipeline_btn.unpause").length > 0;

        openPauseModal();

        // Don't type anything, just close
        cy.get("#pause-modal-close").click();

        modalShouldBeClosed();

        // State should be unchanged — still paused if it was paused, still
        // unpaused if it was unpaused
        if (wasPaused) {
          cy.get(".pipeline").first().find(".pipeline_btn.unpause").should("exist");
        } else {
          cy.get(".pipeline").first().find(".pipeline_btn.pause").should("exist");
        }
      });
  });
});
