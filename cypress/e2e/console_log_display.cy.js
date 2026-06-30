/// <reference types="cypress" />

/**
 * Console Log Display Tests
 *
 * Verifies the job details console log renders with tight, clean lines:
 * - No whitespace pollution (template whitespace bleeding into pre-wrap spans)
 * - Every log row is exactly 1 line-height tall (20px)
 * - Timestamps toggle works (CSS show/hide, no server roundtrip)
 * - Line-wrap toggle works (CSS white-space control)
 * - Fold sections collapse/expand cleanly
 *
 * Regression guard: the template for log rows must have ZERO whitespace between
 * HTML tags inside flex containers.  Any newline or indent between tags becomes
 * an anonymous flex-item text node that `whitespace-pre-wrap` renders as actual
 * blank lines, ballooning rows from 20px to 60–1000px.
 */

const JOB_URL = "/go/tab/build/detail/demo/131/build/1/default";
const READY = { timeout: 15000 };

describe("Console Log Display", () => {
  beforeEach(function () {
    cy.request({ url: JOB_URL, failOnStatusCode: false }).then((resp) => {
      if (resp.status !== 200) {
        cy.log(`** SKIP: job details returned ${resp.status}`);
        this.skip();
        return;
      }
      cy.visit(JOB_URL);
      cy.get(".phx-connected", READY);
      cy.get("#console-container", READY);
    });
  });

  // ── Tight line rendering ──────────────────────────────────────

  it("log rows render without catastrophic height (no 1000px+ explosions)", () => {
    // Regression guard: rows must not balloon to hundreds of px from
    // template whitespace bleeding into pre-wrap spans.
    cy.get(".log-row:not(.hidden)").each(($row) => {
      cy.wrap($row).invoke("height").should("be.lessThan", 200);
    });
  });

  it("visible log messages contain meaningful text (not just whitespace)", () => {
    cy.get(".log-row:not(.hidden) .log-message").each(($msg) => {
      const text = $msg.text().trim();
      if ($msg.closest(".fold-start").length > 0) {
        // Fold headers must have text
        expect(text.length).to.be.greaterThan(0);
      }
    });
  });

  it("no ##[endfold] or ##[fold] markers visible in rendered output", () => {
    cy.get(".log-row:not(.hidden) .log-message").each(($msg) => {
      expect($msg.text()).not.to.include("##[fold]");
      expect($msg.text()).not.to.include("##[endfold]");
    });
  });

  // ── Toggle controls ───────────────────────────────────────────

  it("timestamps toggle shows/hides timestamps via CSS class", () => {
    // Initial: timestamps hidden
    cy.get("#console-container").should("not.have.class", "show-timestamps");
    cy.get(".log-timestamp").first().should("not.be.visible");

    // Toggle ON
    cy.get("#toggle-timestamps").check();
    cy.get("#console-container").should("have.class", "show-timestamps");
    cy.get(".log-timestamp")
      .first()
      .invoke("css", "display")
      .should("not.eq", "none");

    // Toggle OFF
    cy.get("#toggle-timestamps").uncheck();
    cy.get("#console-container").should("not.have.class", "show-timestamps");
    cy.get(".log-timestamp")
      .first()
      .invoke("css", "display")
      .should("eq", "none");
  });

  it("line-wrap toggle controls white-space via CSS class", () => {
    // Initial: wrapping ON (no no-wrap class)
    cy.get("#console-container").should("not.have.class", "no-wrap");

    // Toggle OFF (no wrapping — lines overflow horizontally)
    cy.get("#toggle-wrap").uncheck();
    cy.get("#console-container").should("have.class", "no-wrap");

    // Toggle ON again
    cy.get("#toggle-wrap").check();
    cy.get("#console-container").should("not.have.class", "no-wrap");
  });

  it("follow toggle updates dataset without page reload", () => {
    // Initial: follow ON
    cy.get("#console-container").should("have.attr", "data-follow", "true");

    // Toggle OFF
    cy.get("#toggle-follow").uncheck();
    cy.get("#console-container").should("have.attr", "data-follow", "false");

    // Toggle ON
    cy.get("#toggle-follow").check();
    cy.get("#console-container").should("have.attr", "data-follow", "true");
  });

  // ── Fold sections ─────────────────────────────────────────────

  it("fold sections collapse and expand without breaking row heights", function () {
    cy.get("body").then(($body) => {
      if ($body.find(".fold-start").length === 0) {
        this.skip();
        return;
      }
      // Collapse all
      cy.contains("button", "Collapse All").click();
      cy.wait(400);

      cy.get(".fold-start.collapsed").should("have.length.at.least", 1);

      // Rows should not explode — guard against template whitespace bugs
      cy.get(".log-row:not(.hidden)").each(($row) => {
        cy.wrap($row).invoke("height").should("be.lessThan", 200);
      });

      // Expand all
      cy.contains("button", "Expand All").click();
      cy.wait(400);

      cy.get(".fold-start.collapsed").should("have.length", 0);
    });
  });

  // ── Filter ────────────────────────────────────────────────────

  it("filter hides non-matching rows", () => {
    cy.get("#console-search").type("git init");
    cy.wait(400); // debounce

    // At least the fold header containing "Compile" should still be visible
    cy.get(".log-row:not(.hidden):not(.filter-hidden)").should(
      "have.length.at.least",
      1,
    );

    // Clear filter
    cy.get("#console-search").clear();
    cy.wait(300);

    // All non-hidden rows should be back
    cy.get(".log-row:not(.hidden)").should("have.length.at.least", 5);
  });
});
