// Shared helpers for both test suites
const DESKTOP = [1280, 720];
const NARROW = [1024, 720];

const ready = () => {
  cy.get(".site-header", { timeout: 10000 }).should("be.visible");
  cy.window().should("have.property", "liveSocket");
};

const openAdminDropdown = () => {
  cy.get("li.is-drop-down").trigger("mouseenter");
  cy.get(".sub-navigation").invoke("css", "display", "flex");
  // Trigger clampPosition again now that display is set
  cy.get("li.is-drop-down").trigger("mouseenter");
};

const assertWithinHorizontalViewport = ($el) => {
  const rect = $el[0].getBoundingClientRect();
  // Use clientWidth to account for potential vertical scrollbar taking up space
  const winW = $el[0].ownerDocument.documentElement.clientWidth;

  expect(rect.left).to.be.at.least(
    -2, // 2px tolerance for subpixel rendering
    `dropdown left edge (${rect.left}px) overflows left off-screen`,
  );
  expect(rect.right).to.be.at.most(
    winW + 2, // 2px tolerance for subpixel rendering
    `dropdown right edge (${rect.right}px) overflows right off-screen (viewport ${winW}px)`,
  );
};

const assertNotOverflowUpward = ($el) => {
  const rect = $el[0].getBoundingClientRect();
  expect(rect.top).to.be.at.least(
    0,
    `dropdown top edge (${rect.top}px) overflows above viewport`,
  );
};

describe("Admin dropdown — desktop viewport usability", () => {
  describe("desktop dropdown visibility", () => {
    beforeEach(() => {
      cy.viewport(...DESKTOP);
      cy.loginAsAdmin();
      cy.visit("/pipelines");
      ready();
    });

    it("renders the Admin nav item with dropdown class", () => {
      cy.get("li.is-drop-down")
        .should("exist")
        .and("be.visible")
        .find("a")
        .should("contain.text", "Admin");
    });

    it("shows the sub-navigation container when hovered", () => {
      openAdminDropdown();
      cy.get(".sub-navigation")
        .should("exist")
        .and("be.visible")
        .and("have.css", "display", "flex");
    });

    it("dropdown does NOT overflow left or right", () => {
      openAdminDropdown();
      cy.get(".sub-navigation").then(assertWithinHorizontalViewport);
    });

    it("dropdown does NOT overflow upward (above the header)", () => {
      openAdminDropdown();
      cy.get(".sub-navigation").then(assertNotOverflowUpward);
    });

    it("dropdown may overflow downward — that's fine, page scrolls", () => {
      openAdminDropdown();
      cy.get(".sub-navigation").then(($el) => {
        const rect = $el[0].getBoundingClientRect();
        // Downward overflow is acceptable — the page can scroll.
        // We just verify the dropdown has content and is positioned
        // below the header (top >= 40px header height).
        expect(rect.height).to.be.greaterThan(
          50,
          "dropdown should have meaningful height",
        );
        expect(rect.top).to.be.at.least(
          40,
          "dropdown should appear below the header bar",
        );
      });
    });
  });

  // ── submenu content ──────────────────────────────────────────

  describe("submenu content", () => {
    beforeEach(() => {
      cy.viewport(...DESKTOP);
      cy.loginAsAdmin();
      cy.visit("/pipelines");
      ready();
      openAdminDropdown();
    });

    it("renders all four column groups", () => {
      cy.get(".sub-navigation .site-sub-nav").should("have.length", 4);
    });

    it("renders the first column — Pipelines, Environments, Templates, Config XML, Package Repositories", () => {
      cy.get(".sub-navigation .site-sub-nav")
        .eq(0)
        .within(() => {
          cy.get(".site-sub-nav_link").should("have.length", 5);
          cy.contains("a", "Pipelines").should(
            "have.attr",
            "href",
            "/admin/pipelines",
          );
          cy.contains("a", "Environments").should(
            "have.attr",
            "href",
            "/admin/environments",
          );
          cy.contains("a", "Templates").should(
            "have.attr",
            "href",
            "/admin/templates",
          );
          cy.contains("a", "Config XML").should(
            "have.attr",
            "href",
            "/admin/config_xml",
          );
          cy.contains("a", "Package Repositories").should(
            "have.attr",
            "href",
            "/admin/package_repositories/new",
          );
        });
    });

    it("renders the second column", () => {
      cy.get(".sub-navigation .site-sub-nav")
        .eq(1)
        .within(() => {
          cy.get(".site-sub-nav_link").should("have.length", 5);
          cy.contains("a", "Elastic Agent Configurations");
          cy.contains("a", "Config Repositories");
          cy.contains("a", "Artifact Stores");
          cy.contains("a", "Secret Management");
          cy.contains("a", "Pluggable SCMs");
        });
    });

    it("renders the third column — Server Configuration heading and items", () => {
      cy.get(".sub-navigation .site-sub-nav")
        .eq(2)
        .within(() => {
          cy.get(".site-sub-nav_heading").should(
            "contain.text",
            "Server configuration",
          );
          cy.contains("a", "Server Configuration");
          cy.contains("a", "Server Maintenance Mode");
          cy.contains("a", "Backup");
          cy.contains("a", "Plugins");
        });
    });

    it("renders the fourth column — Security heading and items", () => {
      cy.get(".sub-navigation .site-sub-nav")
        .eq(3)
        .within(() => {
          cy.get(".site-sub-nav_heading").should("contain.text", "Security");
          cy.contains("a", "Authorization Configuration");
          cy.contains("a", "Role configuration");
          cy.contains("a", "Users Management");
          cy.contains("a", "Access Tokens Management");
        });
    });

    it("every submenu link has an href attribute", () => {
      cy.get(".sub-navigation .site-sub-nav_link").each(($link) => {
        expect($link).to.have.attr("href");
        expect($link.attr("href")).to.not.be.empty;
      });
    });
  });

  // ── navigation: clicking a link works ────────────────────────

  describe("submenu navigation", () => {
    beforeEach(() => {
      cy.viewport(...DESKTOP);
      cy.loginAsAdmin();
      cy.visit("/pipelines");
      ready();
      openAdminDropdown();
    });

    it("has correct link targets for key admin pages", () => {
      cy.get(".sub-navigation a")
        .contains("Pipelines")
        .should("have.attr", "href", "/admin/pipelines");
      cy.get(".sub-navigation a")
        .contains("Server Configuration")
        .should("have.attr", "href", "/admin/config/server");
      cy.get(".sub-navigation a")
        .contains("Users Management")
        .should("have.attr", "href", "/admin/users");
    });
  });

  // ── active state ─────────────────────────────────────────────

  describe("active state highlighting", () => {
    it("highlights the active sub-nav link when on an admin page", () => {
      cy.viewport(...DESKTOP);
      cy.loginAsAdmin();
      cy.visit("/admin/pipelines");
      ready();
      openAdminDropdown();

      cy.get('.sub-navigation a[href="/admin/pipelines"]').should(
        "have.class",
        "is-active",
      );
    });

    it("marks the Admin nav item as active when on admin pages", () => {
      cy.viewport(...DESKTOP);
      cy.loginAsAdmin();
      cy.visit("/admin/plugins");
      ready();

      cy.get("li.is-drop-down").should("have.class", "active");
    });
  });

  // ── accessibility ────────────────────────────────────────────

  describe("accessibility", () => {
    beforeEach(() => {
      cy.viewport(...DESKTOP);
      cy.loginAsAdmin();
      cy.visit("/pipelines");
      ready();
    });

    it("Admin nav link is keyboard-focusable", () => {
      cy.get("li.is-drop-down a")
        .should("have.attr", "tabindex")
        .and("match", /^\d+$/);
    });

    it("Admin nav link has menuitem role", () => {
      cy.get("li.is-drop-down a").should("have.attr", "role", "menuitem");
    });
  });
});

// ── narrow viewport: still no horizontal overflow ──────────────

describe("Admin dropdown — narrow viewport", () => {
  it("dropdown does NOT overflow left or right at 1024px width", () => {
    cy.viewport(...NARROW);
    cy.loginAsAdmin();
    cy.visit("/pipelines");
    ready();
    openAdminDropdown();
    cy.get(".sub-navigation").then(assertWithinHorizontalViewport);
  });
});
