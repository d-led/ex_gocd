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

const JOB_URL = "/go/tab/build/detail/demo/4/build/1/default";
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

  it("every visible log row is at most 1 line-height tall (no whitespace pollution)", () => {
    // Each log-row must be 20px ± a small tolerance for sub-pixel rounding
    cy.get(".log-row:not(.hidden)").each(($row) => {
      cy.wrap($row)
        .invoke("height")
        .should("be.at.most", 22); // 20px + 2px tolerance
    });
  });

  it("log-message text does not start with whitespace", () => {
    cy.get(".log-message").each(($msg) => {
      const text = $msg.text();
      // Must not start with newline or space — that's template pollution
      expect(text[0]).not.to.match(/[\n\s]/);
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
    cy.get(".log-timestamp").first().should("be.visible");

    // Toggle OFF
    cy.get("#toggle-timestamps").uncheck();
    cy.get("#console-container").should("not.have.class", "show-timestamps");
    cy.get(".log-timestamp").first().should("not.be.visible");
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

  it("fold sections collapse and expand without breaking row heights", () => {
    // Collapse all
    cy.contains("button", "Collapse All").click();
    cy.wait(300);

    // Only fold headers + the trailing "Build completed" line should be visible
    cy.get(".fold-start.collapsed").should("have.length.at.least", 1);
    cy.get(".log-row:not(.hidden)").each(($row) => {
      cy.wrap($row)
        .invoke("height")
        .should("be.at.most", 22);
    });

    // Expand all
    cy.contains("button", "Expand All").click();
    cy.wait(300);

    cy.get(".fold-start.collapsed").should("have.length", 0);
    cy.get(".log-row:not(.hidden)").each(($row) => {
      cy.wrap($row)
        .invoke("height")
        .should("be.at.most", 22);
    });
  });

  // ── Filter ────────────────────────────────────────────────────

  it("filter hides non-matching rows", () => {
    cy.get("#console-search").type("mix compile");
    cy.wait(300); // debounce

    // At least the fold header containing "Compile" should still be visible
    cy.get(".log-row:not(.hidden):not(.filter-hidden)")
      .should("have.length.at.least", 1);

    // Clear filter
    cy.get("#console-search").clear();
    cy.wait(300);

    // All non-hidden rows should be back
    cy.get(".log-row:not(.hidden)").should("have.length.at.least", 5);
  });
});
