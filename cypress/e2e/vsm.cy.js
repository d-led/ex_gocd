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
      cy.theVSMStageIndicatorShows("compile");
      cy.theVSMStageIndicatorShows("test");

      cy.thePageShows("deploy-staging");
    });

    it("renders SVG connectors across multiple VSM levels", () => {
      cy.theVSMSvgIsRendered();
      cy.theVSMHasLevels(2);
    });

    it("breadcrumb link navigates to pipeline activity", () => {
      cy.clickLink("build-linux");
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
      cy.theVSMRendersOnMobile();
    });
  });

  describe("Dashboard integration", () => {
    it("navigates from the dashboard VSM link to a pipeline VSM", () => {
      cy.visitPage("/pipelines");
      cy.clickLink("VSM");
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

      cy.insideVSMNode("component-a", () => {
        cy.theVSMStageIndicatorShows("build");
      });
      cy.insideVSMNode("component-b", () => {
        cy.theVSMStageIndicatorShows("build");
      });

      // integration-pipeline has stage indicators from its upstream pipelines
      cy.insideVSMNode("integration-pipeline", () => {
        cy.theVSMStageIndicatorShows("integrate");
      });
    });

    it("marks upstream-lib as current and shows the diamond spans 4 VSM levels", () => {
      cy.insideVSMNode("upstream-lib", () => {
        cy.thePageShows("Current");
      });
      cy.theVSMHasExactlyLevels(4);
    });
  });
});
