// Pipeline Configuration tests.
// Covers ruby specs: pipeline_settings_spec.rb, pipeline_creation_wizard_spec.rb

describe("Pipeline Configuration", () => {
  beforeEach(() => {
    cy.loginAsAdmin();
    cy.goToPipelineMaterials("demo");
  });

  it("validates and rejects a non-existent pipeline dependency", () => {
    cy.addMaterial();
    cy.selectMaterialType("dependency");
    cy.validateWithNonexistentPipelineDependency();
  });
});
