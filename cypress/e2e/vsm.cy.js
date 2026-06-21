describe("Value Stream Map E2E Tests", () => {
  beforeEach(() => {
    cy.visit("/pipelines/value_stream_map/build-linux/1");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  it("loads pipeline VSM with breadcrumbs", () => {
    // Breadcrumbs: Pipelines > build-linux > 1 > VSM
    cy.contains("Pipelines").should("exist");
    cy.contains("build-linux").should("exist");
    cy.contains("1").should("exist");
  });

  it("renders material node with repo name", () => {
    // Material node shows the git repo
    cy.get(".vsm-node").contains("Material").should("exist");
    cy.contains("gocd.git").should("exist");
  });

  it("renders pipeline node with stage status dots", () => {
    // Pipeline node shows stages as status dots
    cy.get(".vsm-node").contains("Pipeline").should("exist");
    // Stage dots should have aria-labels
    cy.get('[aria-label*="compile"]').should("exist");
    cy.get('[aria-label*="test"]').should("exist");
    cy.get('[aria-label*="package"]').should("exist");
  });

  it("marks current node with 'Current' badge", () => {
    cy.contains("Current").should("exist");
  });

  it("renders trigger info on current pipeline node", () => {
    cy.contains("Trigger").should("exist");
  });

  it("renders SVG connectors between nodes", () => {
    cy.get("#vsm-svg").should("exist");
  });

  it("can navigate to pipeline activity via breadcrumb", () => {
    cy.contains("a", "build-linux").click();
    cy.url().should("include", "/pipeline/activity/build-linux");
  });

  it("loads material VSM page", () => {
    cy.visit("/materials/value_stream_map/8d78bc9f6c661806/abcd1234ef");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
    // Material breadcrumbs
    cy.contains("Materials").should("exist");
    cy.contains("gocd.git").should("exist");
    // Material nodes and dependent pipelines
    cy.contains("Pipeline").should("exist");
  });
});
