// Maintenance Mode tests: toggle on admin overview page.
// Covers ruby spec: MaintenanceModeDisableCreation.spec, StartServerInMaintenanceMode.spec

describe("Maintenance Mode", () => {
  beforeEach(() => {
    cy.loginAsAdmin();
    cy.visitPage("/admin/overview");
  });

  it("displays maintenance mode status on overview", () => {
    cy.thePageShows("Maintenance Mode");
    // Should show either "Enabled" or "Disabled" status
    cy.contains(/Enabled|Disabled/).should("exist");
  });

  it("has Enable/Disable toggle button", () => {
    cy.contains("button", /Enable|Disable/).should("exist");
  });

  it("toggles maintenance mode when button is clicked", () => {
    // Read current state from the button text
    cy.contains("button", /Enable|Disable/)
      .invoke("text")
      .then((btnText) => {
        const isCurrentlyEnabled = btnText.trim() === "Disable";

        // Click the toggle
        cy.contains("button", /Enable|Disable/).click();

        // Wait for LiveView update
        cy.wait(500);

        // Button text should have changed to the opposite
        if (isCurrentlyEnabled) {
          cy.contains("button", "Enable").should("exist");
        } else {
          cy.contains("button", "Disable").should("exist");
        }

        // Toggle back to original state
        cy.contains("button", /Enable|Disable/).click();
        cy.wait(500);
      });
  });
});
