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

    it("draws dependency arrows between connected nodes", () => {
      cy.theVSMSvgIsRendered();
      cy.vsmArrowsShouldBeDrawn(6);
    });

    it("highlights the arrow and connected nodes when hovering over it", () => {
      cy.hoverOnArrowBetween("ex_gocd", "upstream-lib");

      cy.arrowBetweenShouldBeHighlighted("ex_gocd", "upstream-lib");
      cy.allOtherArrowsShouldBeDimmed("ex_gocd", "upstream-lib");
      cy.nodesShouldGlow("ex_gocd", "upstream-lib");
      cy.nodeShouldNotGlow("integration-pipeline");

      // Visual proof — screenshot shows the glow + dimming
      cy.screenshot("vsm-hover-glow", { capture: "viewport" });
    });

    it("restores all arrows and removes the glow when moving the mouse away", () => {
      cy.hoverOnArrowBetween("ex_gocd", "upstream-lib");
      cy.moveMouseAwayFromArrowBetween("ex_gocd", "upstream-lib");

      cy.allArrowsShouldBeBright();
      cy.noNodesShouldGlow();

      // Visual proof — screenshot shows everything restored
      cy.screenshot("vsm-mouseleave-restored", { capture: "viewport" });
    });

    it("keeps the highlight after a tap so mobile users can inspect the arrow", () => {
      cy.tapOnArrowBetween("ex_gocd", "upstream-lib");

      cy.nodesShouldGlow("ex_gocd", "upstream-lib");
      cy.allOtherArrowsShouldBeDimmed("ex_gocd", "upstream-lib");

      // A second tap dismisses the highlight
      cy.tapOnArrowBetween("ex_gocd", "upstream-lib");
      cy.noNodesShouldGlow();
      cy.allArrowsShouldBeBright();
    });

    it("highlights different fan-out arrows independently", () => {
      cy.hoverOnArrowBetween("upstream-lib", "component-a");

      cy.nodesShouldGlow("upstream-lib", "component-a");
      cy.arrowBetweenShouldBeHighlighted("upstream-lib", "component-a");
      cy.allOtherArrowsShouldBeDimmed("upstream-lib", "component-a");

      cy.moveMouseAwayFromArrowBetween("upstream-lib", "component-a");
    });
  });

  describe("VSM node link clickability", () => {
    it("clicking a pipeline name link navigates to the pipeline list", () => {
      cy.visitPage("/pipelines/value_stream_map/upstream-lib/3");
      cy.get(".vsm-node").contains("component-a").click({ force: true });
      cy.url().should("include", "/pipelines?search=component-a");
    });

    it("clicking a stage indicator navigates to stage details", () => {
      cy.visitPage("/pipelines/value_stream_map/upstream-lib/3");
      cy.insideVSMNode("upstream-lib", () => {
        cy.get("a[href*='/pipelines/']").first().click({ force: true });
      });
      cy.url().should("include", "/pipelines/");
    });

    it("VSM links remain clickable after zoom", () => {
      cy.viewport(1280, 800);
      cy.visitPage("/pipelines/value_stream_map/upstream-lib/3");
      cy.zoomInViaButton();
      cy.zoomInViaButton();
      cy.get(".vsm-node").contains("component-a").click({ force: true });
      cy.url().should("include", "component-a");
    });

    it("VSM links remain clickable after pan", () => {
      cy.viewport(1280, 800);
      cy.visitPage("/pipelines/value_stream_map/upstream-lib/3");
      cy.get("#vsm-container")
        .trigger("mousedown", { clientX: 400, clientY: 300 })
        .trigger("mousemove", { clientX: 350, clientY: 280 })
        .trigger("mouseup");
      cy.get(".vsm-node").contains("component-b").click({ force: true });
      cy.url().should("include", "component-b");
    });
  });

  describe("Desktop zoom and pan", () => {
    beforeEach(() => {
      cy.viewport(1280, 800);
      cy.visitPage("/pipelines/value_stream_map/upstream-lib/3");
    });

    it("shows zoom controls on desktop and hides them on mobile", () => {
      // Desktop: controls visible
      cy.theZoomControlsAreVisible();
      cy.theTransformGroupExists();

      // Mobile: controls hidden
      cy.viewport("iphone-6");
      cy.theZoomControlsAreHidden();
    });

    it("fits the graph to screen on initial load", () => {
      cy.theVSMZoomIsBelow(1.01);
    });

    it("zooms in and out and arrows still work", () => {
      cy.zoomInViaButton();
      cy.zoomInViaButton();
      cy.vsmArrowsStillWork();

      cy.zoomOutViaButton();
      cy.vsmArrowsStillWork();
    });

    it("resets zoom to fit via the Fit button", () => {
      cy.zoomInViaButton();
      cy.zoomInViaButton();
      cy.clickFitToScreen();
      cy.theVSMZoomIsBelow(1.01);
      cy.vsmArrowsStillWork();
    });

    it("zooms via mouse wheel on desktop", () => {
      cy.scrollWheelOnVSM(-100);
      cy.scrollWheelOnVSM(100);
      cy.vsmArrowsStillWork();
    });

    it("shows grab cursor on desktop", () => {
      cy.theVSMCursorIsGrab();
    });

    it("keeps arrows drawn after zoom", () => {
      cy.vsmArrowsStillWork();
      cy.zoomInViaButton();
      cy.vsmArrowsStillWork();
      cy.clickFitToScreen();
      cy.vsmArrowsStillWork();
    });

    it("hover highlight still works after zoom", () => {
      cy.zoomInViaButton();
      cy.hoverStillHighlightsNodes();
      cy.clickFitToScreen();
      cy.hoverStillHighlightsNodes();
    });
  });
});
