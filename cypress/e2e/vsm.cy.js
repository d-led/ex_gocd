describe("Value Stream Map", () => {
  describe("Pipeline VSM", () => {
    beforeEach(() => {
      cy.visitPage("/pipelines/value_stream_map/build-linux/1");
    });

    it("loads with breadcrumbs and renders material, pipeline, and downstream nodes", () => {
      cy.thePageShows("Pipelines");
      cy.thePageShows("build-linux");
      cy.thePageShows("1");

      cy.theVSMShowsNode("Material");
      cy.thePageShows("gocd.git");

      cy.theVSMShowsNode("Pipeline");
      cy.thePageShows("Current");
      cy.get('[aria-label*="compile"]').should("exist");
      cy.get('[aria-label*="test"]').should("exist");

      cy.thePageShows("deploy-staging");
    });

    it("renders SVG connectors across multiple VSM levels", () => {
      cy.theVSMSvgIsRendered();
      cy.theVSMHasLevels(2);
    });

    it("breadcrumb link navigates to pipeline activity", () => {
      cy.iClickLink("build-linux");
      cy.theUrlContains("/pipeline/activity/build-linux");
    });
  });

  describe("Material VSM", () => {
    it("loads with breadcrumbs showing the material and dependent pipelines", () => {
      cy.visitPage("/materials/value_stream_map/8d78bc9f6c661806/abcd1234ef");
      cy.thePageShows("Materials");
      cy.thePageShows("gocd.git");
      cy.theVSMShowsNode("Pipeline");
    });
  });

  describe("Mobile responsive", () => {
    it("renders the VSM container on a mobile viewport", () => {
      cy.viewport("iphone-6");
      cy.visitPage("/pipelines/value_stream_map/build-linux/1");
      cy.theElementIsVisible("#vsm-container");
    });
  });

  describe("Dashboard integration", () => {
    it("navigates from the dashboard VSM link to a pipeline VSM", () => {
      cy.visitPage("/pipelines");
      cy.iClickLink("VSM");
      cy.theUrlContains("/pipelines/value_stream_map/");
      cy.theVSMSvgIsRendered();
    });
  });

  describe("Error handling", () => {
    it("redirects to pipelines when the pipeline does not exist", () => {
      cy.visit("/pipelines/value_stream_map/no-such-pipeline/999");
      cy.theUrlContains("/pipelines");
    });
  });

  describe("Diamond fan-in/fan-out VSM", () => {
    beforeEach(() => {
      cy.visitPage("/pipelines/value_stream_map/upstream-lib/3");
    });

    it("shows fan-out to component-a and component-b", () => {
      cy.thePageShows("component-a");
      cy.thePageShows("component-b");
    });

    it("shows fan-in to integration-pipeline with stage indicators on downstream nodes", () => {
      cy.thePageShows("integration-pipeline");

      cy.get('[data-id="component-a"]').within(() => {
        cy.get('[aria-label*="build"]').should("exist");
      });
      cy.get('[data-id="component-b"]').within(() => {
        cy.get('[aria-label*="build"]').should("exist");
      });

      // integration-pipeline has stage indicators from its upstream pipelines
      cy.get('[data-id="integration-pipeline"]').within(() => {
        cy.get('[aria-label*="integrate"]').should("exist");
      });
    });

    it("marks upstream-lib as current and shows the diamond spans 4 VSM levels", () => {
      cy.get('[data-id="upstream-lib"]').within(() => {
        cy.thePageShows("Current");
      });
      cy.get(".vsm-level").should("have.length", 4);
    });
  });
});
