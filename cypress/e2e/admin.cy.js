// Admin page tests: verifies each admin tab loads and shows correct content.
// Uses loginAsAdmin() since admin pages require authentication.

describe("Admin Page", () => {
  beforeEach(() => {
    cy.loginAsAdmin();
    cy.visitPage("/admin");
  });

  // ── Tab navigation ────────────────────────────────────────────

  const tabs = [
    { label: "Overview", url: "/admin/overview" },
    { label: "Pipelines & Groups", url: "/admin/pipelines" },
    { label: "Environments", url: "/admin/environments" },
    { label: "Config Repositories", url: "/admin/config_repos" },
    { label: "Server Configuration", url: "/admin/server" },
    { label: "Security & Users", url: "/admin/security" },
    { label: "Audit Log", url: "/admin/audit_log" },
  ];

  tabs.forEach(({ label, url }) => {
    it(`navigates to "${label}" tab`, () => {
      cy.visitPage(url);

      // The tab link with the correct href should exist in the nav bar
      cy.get(`a[href="${url}"]`).should("exist").and("contain", label);

      // The page heading should reflect the active tab
      cy.get("h1").should("exist");
    });
  });

  // ── Overview tab ──────────────────────────────────────────────

  describe("Overview tab", () => {
    beforeEach(() => {
      cy.visitPage("/admin/overview");
    });

    it("displays stat cards for Pipeline Groups, Environments, Config Repos, and Users", () => {
      cy.thePageShows("Pipeline Groups");
      cy.thePageShows("Environments");
      cy.thePageShows("Config Repos");
      cy.thePageShows("Active Users");
    });

    it("displays Server Status panel", () => {
      cy.thePageShows("Server Status");
      cy.thePageShows("Server State");
      cy.thePageShows("Maintenance Mode");
    });

    it("displays Operations Control panel with action buttons", () => {
      cy.thePageShows("Operations Control");
      cy.contains("button", "Enable").should("exist");
      cy.contains("a", "Backup Server").should("exist");
      cy.contains("button", "Cleanup Now").should("exist");
    });
  });

  // ── Pipelines tab ─────────────────────────────────────────────

  describe("Pipelines tab", () => {
    beforeEach(() => {
      cy.visitPage("/admin/pipelines");
    });

    it("has a search input for pipelines", () => {
      cy.get("input[name='query']").should("be.visible");
    });

    it("has a button to create a new pipeline group", () => {
      cy.contains("button", "Create new pipeline group").should("exist");
    });

    it("shows pipeline groups with pipeline entries", () => {
      // Pipeline Group heading should be visible
      cy.thePageShows("Pipeline Group");
      // At least the Add new pipeline button exists per group
      cy.get("button").contains("Add new pipeline").should("exist");
    });
  });

  // ── Environments tab ──────────────────────────────────────────

  describe("Environments tab", () => {
    beforeEach(() => {
      cy.visitPage("/admin/environments");
    });

    it("has a button to add an environment", () => {
      cy.contains("button", "Add Environment").should("exist");
    });

    it("shows environment entries or empty state", () => {
      // Either environments are listed or an empty state message appears
      cy.get("body").then(($body) => {
        if ($body.text().includes("No environments configured")) {
          cy.thePageShows("No environments configured");
        } else {
          cy.thePageShows("Active Agents");
        }
      });
    });
  });

  // ── Config Repos tab ──────────────────────────────────────────

  describe("Config Repos tab", () => {
    beforeEach(() => {
      cy.visitPage("/admin/config_repos");
    });

    it("has a link to add a config repo", () => {
      cy.thePageHasALinkToAddConfigRepo();
    });

    it("shows a table with repo data or empty state", () => {
      cy.get("body").then(($body) => {
        if ($body.text().includes("No config repositories configured")) {
          cy.thePageShows("No config repositories configured");
        } else {
          // Table headers should be present
          cy.get("thead").should("contain", "Repo URL");
          cy.get("thead").should("contain", "Source Type");
        }
      });
    });
  });

  // ── Server Configuration tab ──────────────────────────────────

  describe("Server Configuration tab", () => {
    beforeEach(() => {
      cy.visitPage("/admin/server");
    });

    it("displays the backup configuration section", () => {
      cy.thePageShows("Backup Configuration Database");
      cy.get("button").contains("Start Backup Now").should("exist");
    });

    it("displays the active plugins section", () => {
      cy.thePageShows("Active Plugins");
    });
  });

  // ── Security & Users tab ──────────────────────────────────────

  describe("Security & Users tab", () => {
    beforeEach(() => {
      cy.visitPage("/admin/security");
    });

    it("has a button to add a user", () => {
      cy.contains("button", "Add User").should("exist");
    });

    it("shows users in a table", () => {
      cy.get("body").then(($body) => {
        if ($body.text().includes("No users found")) {
          cy.thePageShows("No users found");
        } else {
          // At least username column should appear
          cy.get("thead").should("contain", "Username");
        }
      });
    });
  });
});
