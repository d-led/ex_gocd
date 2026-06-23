describe("Site Navigation — narrow view / burger menu", () => {
  const MOBILE = [375, 812];

  const ready = () => {
    cy.get(".site-header", { timeout: 10000 }).should("be.visible");
    cy.window().should("have.property", "liveSocket");
  };

  // ── visibility ────────────────────────────────────────────────

  it("burger hidden on desktop, visible on mobile", () => {
    cy.visit("/pipelines");
    ready();
    cy.get(".navbtn").should("not.be.visible");
    cy.viewport(...MOBILE);
    cy.get(".navbtn").should("be.visible");
  });

  // ── menu structure ───────────────────────────────────────────

  describe("menu structure on mobile", () => {
    beforeEach(() => {
      cy.viewport(...MOBILE);
      cy.visit("/pipelines");
      ready();
    });

    it("renders core nav links", () => {
      cy.get("#main-navigation").should("exist");
      cy.get(".site-header_left").should("exist");
      cy.get(".site-header_right").should("exist");
      cy.get(".site-navigation_left > li").should("have.length.at.least", 4);
      cy.get(".site-navigation_left a").contains("Dashboard").should("exist");
      cy.get(".site-navigation_left a").contains("Agents").should("exist");
      cy.get(".site-navigation_left a").contains("Materials").should("exist");
    });

    it("highlights active page link", () => {
      cy.get(".site-navigation_left > li.active a").should(
        "have.attr",
        "aria-current",
        "page",
      );
    });
  });

  // ── accessibility ────────────────────────────────────────────

  describe("accessibility", () => {
    beforeEach(() => {
      cy.viewport(...MOBILE);
      cy.visit("/pipelines");
      ready();
    });

    it("burger button has proper ARIA attributes", () => {
      cy.get(".navbtn")
        .should("have.attr", "aria-label", "Open navigation menu")
        .and("have.attr", "aria-controls", "main-navigation")
        .and("have.attr", "aria-expanded", "false");
    });

    it("main nav has role and label", () => {
      cy.get("#main-navigation")
        .should("have.attr", "role", "navigation")
        .and("have.attr", "aria-label", "Main navigation");
    });

    it("nav links are keyboard-focusable", () => {
      cy.get(".site-navigation_left a").first().should("have.attr", "tabindex");
    });
  });

  // ── desktop: nav is inline ───────────────────────────────────

  it("desktop nav is inline (not off-screen overlay)", () => {
    cy.viewport(1280, 720);
    cy.visit("/pipelines");
    ready();
    cy.get("#main-navigation")
      .should("be.visible")
      .and("not.have.css", "position", "fixed");
  });
});
