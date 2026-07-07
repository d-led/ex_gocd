/// <reference types="cypress" />

/**
 * Auto-screenshot spec for ex_gocd documentation.
 * Run via: bash scripts/update-screenshots-cypress.sh
 * (NOT included in default `npm run cypress:run`)
 *
 * Every test discovers what's available dynamically — no hardcoded names.
 * If preconditions aren't met, the test skips gracefully.
 *
 * Uses ONLY reusable custom commands: no raw cy.get, no magic selectors.
 */

describe("Auto screenshot", () => {
  // Sign in once via Quick Login for admin-protected pages.
  // NOTE: demo login page — will be removed in production
  // once custom admin accounts are configured.
  before(() => {
    cy.loginAsAdmin();
  });

  beforeEach(() => {
    cy.loginAsAdmin();
  });

  // ═══════════════════════════════════════════════════════════════
  // DASHBOARD
  // ═══════════════════════════════════════════════════════════════

  it("dashboard", function () {
    cy.navigateAndVerify("/pipelines", ".dashboard");
    cy.captureScreenshot("dashboard");
  });

  // ═══════════════════════════════════════════════════════════════
  // AGENTS
  // ═══════════════════════════════════════════════════════════════

  it("agents (static tab)", function () {
    cy.navigateAndVerify("/agents", ".agents-page");
    cy.captureScreenshot("agents");
  });

  it("agents (elastic tab)", function () {
    cy.navigateAndVerify("/agents", ".agents-page");
    cy.get("body").then(($body) => {
      const tab = $body
        .find("button")
        .filter((_, el) => el.textContent.trim() === "ELASTIC");
      if (!tab.length) {
        this.skip();
        return;
      }
    });
    cy.clickTab("ELASTIC");
    cy.captureScreenshot("agents-elastic");
  });

  it("agents (k8s pods tab)", function () {
    cy.navigateAndVerify("/agents", ".agents-page");
    cy.get("body").then(($body) => {
      const tab = $body
        .find("button")
        .filter((_, el) => el.textContent.trim() === "K8S PODS");
      if (!tab.length) {
        this.skip();
        return;
      }
    });
    cy.clickTab("K8S PODS");
    cy.captureScreenshot("agents-k8s-pods");
  });

  it("agent job history", function () {
    cy.navigateAndVerify("/agents", ".agents-page");
    cy.discoverFirstAgent();
    cy.get("@agent").then(function (agent) {
      cy.navigateAndVerify(`/agents/${agent.uuid}/job_run_history`);
      cy.captureScreenshot("agent-job-history");
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // MATERIALS
  // ═══════════════════════════════════════════════════════════════

  it("materials", function () {
    cy.navigateAndVerify("/materials", ".materials-page");
    cy.captureScreenshot("materials");
  });

  // ═══════════════════════════════════════════════════════════════
  // ANALYTICS
  // ═══════════════════════════════════════════════════════════════

  it("analytics (global)", function () {
    cy.navigateAndVerify("/analytics");
    cy.captureScreenshot("analytics-global");
  });

  it("analytics (pipelines)", function () {
    cy.navigateAndVerify("/analytics");
    cy.clickTab("Pipelines");
    cy.captureScreenshot("analytics-pipelines");
  });

  it("analytics (agents)", function () {
    cy.navigateAndVerify("/analytics");
    cy.clickTab("Agents");
    cy.captureScreenshot("analytics-agents");
  });

  it("analytics (vsm trends)", function () {
    cy.navigateAndVerify("/analytics");
    cy.get("body").then(($body) => {
      const tab = $body
        .find("button")
        .filter((_, el) => el.textContent.trim() === "VSM Trends");
      if (!tab.length) {
        this.skip();
        return;
      }
    });
    cy.clickTab("VSM Trends");
    cy.captureScreenshot("analytics-vsm-trends");
  });

  // ═══════════════════════════════════════════════════════════════
  // ADMIN — Overview & Sub-Pages
  // ═══════════════════════════════════════════════════════════════

  it("admin (overview)", function () {
    cy.navigateAndVerify("/admin");
    cy.captureScreenshot("admin-overview");
  });

  it("admin (pipelines)", function () {
    cy.navigateAndVerify("/admin/pipelines");
    cy.captureScreenshot("admin-pipelines");
  });

  it("admin (environments)", function () {
    cy.navigateAndVerify("/admin/environments");
    cy.captureScreenshot("admin-environments");
  });

  it("admin (templates)", function () {
    cy.navigateAndVerify("/admin/templates");
    cy.captureScreenshot("admin-templates");
  });

  it("admin (config repos)", function () {
    cy.navigateAndVerify("/admin/config_repos");
    cy.captureScreenshot("admin-config-repos");
  });

  it("admin (server config)", function () {
    cy.navigateAndVerify("/admin/config/server");
    cy.captureScreenshot("admin-server-config");
  });

  it("admin (security)", function () {
    cy.navigateAndVerify("/admin/security/auth_configs");
    cy.captureScreenshot("admin-security");
  });

  it("admin (audit log)", function () {
    cy.navigateAndVerify("/admin/audit_log");
    cy.captureScreenshot("admin-audit-log");
  });

  it("admin (elastic agents)", function () {
    cy.navigateAndVerify("/admin/elastic_agents");
    cy.captureScreenshot("admin-elastic-agents");
  });

  it("admin (clustering)", function () {
    cy.navigateAndVerify("/admin/clustering");
    cy.captureScreenshot("admin-clustering");
  });

  it("admin (plugins)", function () {
    cy.navigateAndVerify("/admin/plugins");
    cy.captureScreenshot("admin-plugins");
  });

  it("admin (config xml)", function () {
    cy.navigateAndVerify("/admin/config_xml");
    cy.captureScreenshot("admin-config-xml");
  });

  it("admin (package repos)", function () {
    cy.navigateAndVerify("/admin/package_repositories/new");
    cy.captureScreenshot("admin-package-repos");
  });

  // ═══════════════════════════════════════════════════════════════
  // PIPELINE WIZARD (new pipeline)
  // ═══════════════════════════════════════════════════════════════

  it("pipeline wizard (new)", function () {
    cy.navigateAndVerify("/admin/pipelines/new");
    cy.captureScreenshot("pipeline-wizard-new");
  });

  // ═══════════════════════════════════════════════════════════════
  // EXTERNAL CI REPO WIZARD
  // ═══════════════════════════════════════════════════════════════

  it("external ci repo wizard", function () {
    cy.navigateAndVerify("/admin/config_repos/new");
    cy.captureScreenshot("config-repo-wizard");
  });

  // ═══════════════════════════════════════════════════════════════
  // PIPELINE ACTIVITY
  // ═══════════════════════════════════════════════════════════════

  it("pipeline activity", function () {
    cy.navigateAndVerify("/pipelines", ".dashboard");
    cy.discoverFirstPipeline();
    cy.get("@pipeline").then(function (p) {
      cy.navigateAndVerify(`/pipeline/activity/${p.name}`);
      cy.captureScreenshot("pipeline-activity");
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // PIPELINE CONFIG WIZARD
  // ═══════════════════════════════════════════════════════════════

  it("pipeline config", function () {
    cy.navigateAndVerify("/pipelines", ".dashboard");
    cy.discoverFirstPipeline();
    cy.get("@pipeline").then(function (p) {
      cy.navigateAndVerify(`/go/admin/pipelines/${p.name}/edit/materials`);
      cy.captureScreenshot("pipeline-config");
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // STAGE DETAILS — all tabs
  // ═══════════════════════════════════════════════════════════════

  function visitStageDetails(callback) {
    cy.navigateAndVerify("/pipelines", ".dashboard");
    cy.discoverFirstPipeline();
    cy.get("@pipeline").then(function (p) {
      if (!p.counter) {
        cy.log("** SKIP: no completed runs");
        this.skip();
        return;
      }
      const url = `/go/pipelines/${p.name}/${p.counter}/build/1`;
      cy.request({ url, failOnStatusCode: false }).then((resp) => {
        if (resp.status !== 200) {
          cy.log(`** SKIP: stage returned ${resp.status}`);
          this.skip();
          return;
        }
        cy.navigateAndVerify(url);
        callback(p);
      });
    });
  }

  it("stage details (jobs tab)", function () {
    visitStageDetails.call(this, () => {
      cy.captureScreenshot("stage-details");
    });
  });

  it("stage details (configuration tab)", function () {
    visitStageDetails.call(this, () => {
      cy.get("body").then(($body) => {
        const tab = $body
          .find("button")
          .filter((_, el) => el.textContent.trim() === "Configuration");
        if (!tab.length) {
          this.skip();
          return;
        }
      });
      cy.clickTab("Configuration");
      cy.captureScreenshot("stage-configuration");
    });
  });

  it("stage details (trends tab)", function () {
    visitStageDetails.call(this, () => {
      cy.get("body").then(($body) => {
        const tab = $body
          .find("button")
          .filter((_, el) => el.textContent.trim() === "Trends");
        if (!tab.length) {
          this.skip();
          return;
        }
      });
      cy.clickTab("Trends");
      cy.captureScreenshot("stage-trends");
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // JOB DETAILS — all tabs
  // ═══════════════════════════════════════════════════════════════

  function visitJobDetails(callback) {
    visitStageDetails.call(this, (p) => {
      cy.discoverFirstJobName();
      cy.get("@jobName").then(function (jobName) {
        const url = `/go/tab/build/detail/${p.name}/${p.counter}/build/1/${jobName}`;
        cy.navigateAndVerify(url);
        callback(p, jobName);
      });
    });
  }

  it("job details (console log)", function () {
    visitJobDetails.call(this, () => {
      cy.captureScreenshot("job-details-console");
    });
  });

  it("job details (tests tab)", function () {
    visitJobDetails.call(this, () => {
      cy.clickTab("Tests");
      cy.captureScreenshot("job-details-tests");
    });
  });

  it("job details (artifacts tab)", function () {
    visitJobDetails.call(this, () => {
      cy.get("body").then(($body) => {
        const tab = $body
          .find("button")
          .filter((_, el) => el.textContent.trim() === "Artifacts");
        if (!tab.length) {
          this.skip();
          return;
        }
      });
      cy.clickTab("Artifacts");
      cy.captureScreenshot("job-details-artifacts");
    });
  });

  it("job details (materials tab)", function () {
    visitJobDetails.call(this, () => {
      cy.clickTab("Materials");
      cy.captureScreenshot("job-details-materials");
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // CONFIG DIFF
  // ═══════════════════════════════════════════════════════════════

  it("config diff", function () {
    cy.navigateAndVerify("/pipelines", ".dashboard");
    cy.discoverFirstPipeline();
    cy.get("@pipeline").then(function (p) {
      if (!p.counter) {
        this.skip();
        return;
      }
      const url = `/go/pipelines/${p.name}/${p.counter}/config_diff`;
      cy.request({ url, failOnStatusCode: false }).then((resp) => {
        if (resp.status !== 200) {
          cy.log(`** SKIP: config diff returned ${resp.status}`);
          this.skip();
          return;
        }
        cy.navigateAndVerify(url);
        cy.captureScreenshot("config-diff");
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // VALUE STREAM MAP
  // ═══════════════════════════════════════════════════════════════

  it("value stream map", function () {
    cy.navigateAndVerify("/pipelines", ".dashboard");
    cy.discoverFirstPipeline();
    cy.get("@pipeline").then(function (p) {
      if (!p.counter) {
        this.skip();
        return;
      }
      const url = `/go/pipelines/value_stream_map/${p.name}/${p.counter}`;
      cy.request({ url, failOnStatusCode: false }).then((resp) => {
        if (resp.status !== 200) {
          cy.log(`** SKIP: VSM returned ${resp.status}`);
          this.skip();
          return;
        }
        cy.navigateAndVerify(url);
        cy.captureScreenshot("vsm");
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // COMPARE
  // ═══════════════════════════════════════════════════════════════

  it("compare", function () {
    cy.navigateAndVerify("/pipelines", ".dashboard");
    cy.discoverFirstPipeline();
    cy.get("@pipeline").then(function (p) {
      if (!p.counter) {
        this.skip();
        return;
      }
      const from = Math.max(1, Number(p.counter) - 1);
      const url = `/go/compare/${p.name}/${from}/with/${p.counter}`;
      cy.request({ url, failOnStatusCode: false }).then((resp) => {
        if (resp.status !== 200) {
          cy.log(`** SKIP: compare returned ${resp.status}`);
          this.skip();
          return;
        }
        cy.navigateAndVerify(url);
        cy.captureScreenshot("compare");
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // SWAGGER UI
  // ═══════════════════════════════════════════════════════════════

  it("swagger ui", function () {
    cy.request({ url: "/swaggerui", failOnStatusCode: false }).then((resp) => {
      if (resp.status !== 200) {
        cy.log(`** SKIP: swagger returned ${resp.status}`);
        this.skip();
        return;
      }
      cy.navigateAndVerify("/swaggerui");
      cy.captureScreenshot("swagger-ui");
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GANTT CHART
  // ═══════════════════════════════════════════════════════════════

  /**
   * Navigate to the Gantt page and verify it has pipeline data
   * worth screenshotting (at least one pipeline with stage bars).
   * Skips when no data or only single-stage pipelines.
   */
  function verifyGanttHasData() {
    cy.navigateAndVerify("/gantt", '[data-test-id="gantt-page"]');

    cy.get("body").then(($body) => {
      // No runs at all
      if ($body.text().includes("No pipeline runs yet")) {
        cy.log("** SKIP: no pipeline runs for Gantt chart");
        cy.state("runnable").skip();
        return;
      }

      // Look for at least one pipeline label with a counter
      // Pipeline labels look like "two-stage-demo #7" in the SVG
      const svgText = $body.find("svg text").text();
      const hasPipelineLabel = /[a-z].*#\d+/.test(svgText);
      if (!hasPipelineLabel) {
        cy.log("** SKIP: no pipeline labels found in Gantt SVG");
        cy.state("runnable").skip();
        return;
      }

      // Verify at least one pipeline has stage bars (colored rects)
      const stageRects = $body.find(
        "svg rect[fill='#22c55e'], svg rect[fill='#ef4444'], svg rect[fill='#3b82f6']",
      );
      if (!stageRects.length) {
        cy.log("** SKIP: no stage bars (colored rects) in Gantt SVG");
        cy.state("runnable").skip();
        return;
      }

      const pipelineLabels = svgText.match(/[a-z].*#\d+/g) || [];
      cy.log(
        `Gantt: ${pipelineLabels.length} pipelines, ${stageRects.length} stage bars`,
      );
    });
  }

  it("gantt chart", function () {
    verifyGanttHasData();
    cy.captureScreenshot("gantt-chart");
  });

  // ═══════════════════════════════════════════════════════════════
  // MOBILE VIEWPORTS
  // ═══════════════════════════════════════════════════════════════

  it("dashboard mobile", function () {
    cy.viewport(375, 812);
    cy.navigateAndVerify("/pipelines", ".dashboard");
    cy.captureScreenshot("dashboard-mobile");
  });

  it("agents mobile", function () {
    cy.viewport(375, 812);
    cy.navigateAndVerify("/agents", ".agents-page");
    cy.captureScreenshot("agents-mobile");
  });

  it("materials mobile", function () {
    cy.viewport(375, 812);
    cy.navigateAndVerify("/materials", ".materials-page");
    cy.captureScreenshot("materials-mobile");
  });

  it("stage details mobile", function () {
    cy.viewport(375, 812);
    visitStageDetails.call(this, () => {
      cy.captureScreenshot("stage-details-mobile");
    });
  });

  it("job details mobile", function () {
    cy.viewport(375, 812);
    visitJobDetails.call(this, () => {
      cy.captureScreenshot("job-details-mobile");
    });
  });

  it("admin mobile", function () {
    cy.viewport(375, 812);
    cy.navigateAndVerify("/admin");
    cy.captureScreenshot("admin-mobile");
  });

  it("gantt chart mobile", function () {
    cy.viewport(375, 812);
    verifyGanttHasData();
    cy.captureScreenshot("gantt-chart-mobile");
  });
});
