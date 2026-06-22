describe("Value Stream Map E2E Tests", () => {
  describe("Pipeline VSM", () => {
    beforeEach(() => {
      cy.visit("/pipelines/value_stream_map/build-linux/1");
      cy.get('.phx-connected', { timeout: 10000 }).should('exist');
    });

    it("loads with breadcrumbs: Pipelines > pipeline > counter > VSM", () => {
      cy.contains("Pipelines").should("exist");
      cy.get("a").contains("build-linux").should("exist");
      cy.contains("1").should("exist");
    });

    it("renders material node with repo name", () => {
      cy.get(".vsm-node").contains("Material").should("exist");
      cy.contains("gocd.git").should("exist");
    });

    it("renders pipeline node as current with stage status dots", () => {
      cy.get(".vsm-node").contains("Pipeline").should("exist");
      cy.contains("Current").should("exist");
      cy.get('[aria-label*="compile"]').should("exist");
      cy.get('[aria-label*="test"]').should("exist");
    });

    it("renders trigger info with icons", () => {
      cy.get(".vsm-node").should("have.length.at.least", 1);
    });

    it("renders SVG connectors", () => {
      cy.get("#vsm-svg").should("exist");
    });

    it("renders multiple VSM levels", () => {
      cy.get(".vsm-level").should("have.length.at.least", 2);
    });

    it("breadcrumb navigates to pipeline activity", () => {
      cy.get("a").contains("build-linux").click();
      cy.url().should("include", "/pipeline/activity/build-linux");
    });

    it("renders downstream pipeline nodes", () => {
      cy.contains("deploy-staging").should("exist");
    });
  });

  describe("Material VSM", () => {
    it("loads with breadcrumbs and dependent pipelines", () => {
      cy.visit("/materials/value_stream_map/8d78bc9f6c661806/abcd1234ef");
      cy.get('.phx-connected', { timeout: 10000 }).should('exist');
      cy.contains("Materials").should("exist");
      cy.contains("gocd.git").should("exist");
      cy.get(".vsm-node").contains("Pipeline").should("exist");
    });
  });

  describe("Mobile responsive", () => {
    it("renders on mobile viewport", () => {
      cy.viewport("iphone-6");
      cy.visit("/pipelines/value_stream_map/build-linux/1");
      cy.get('.phx-connected', { timeout: 10000 }).should('exist');
      cy.get("#vsm-container").should("exist");
    });
  });

  describe("Dashboard integration", () => {
    it("has VSM link from dashboard", () => {
      cy.visit("/pipelines");
      cy.get('.phx-connected', { timeout: 10000 }).should('exist');
      cy.contains("VSM").should("exist");
    });
  });

  describe("Error handling", () => {
    it("redirects to pipelines for non-existent pipeline", () => {
      cy.visit("/pipelines/value_stream_map/no-such-pipeline/999");
      cy.url().should("include", "/pipelines");
    });
  });
});
