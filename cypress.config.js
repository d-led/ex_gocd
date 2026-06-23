const { defineConfig } = require("cypress");
const fs = require("fs");
const path = require("path");

module.exports = defineConfig({
  reporter: "junit",
  reporterOptions: {
    mochaFile: "cypress/results/results-[hash].xml",
    toConsole: false,
  },
  e2e: {
    baseUrl: "http://localhost:4000",
    supportFile: "cypress/support/e2e.js",
    specPattern: "cypress/e2e/**/*.cy.{js,jsx,ts,tsx}",
    excludeSpecPattern: ["**/screenshot*.cy.js"],
    video: false,
    screenshotOnRunFailure: false,
    screenshotsFolder: "cypress/screenshots",
    viewportWidth: 1280,
    viewportHeight: 720,
    setupNodeEvents(on, config) {
      on("task", {
        copyScreenshot({ src, dest }) {
          const srcPath = path.resolve(src);
          const destPath = path.resolve(dest);
          try {
            fs.mkdirSync(path.dirname(destPath), { recursive: true });
            fs.copyFileSync(srcPath, destPath);
            return { success: true, dest };
          } catch (err) {
            return { error: err.message };
          }
        },
      });
      return config;
    },
  },
});
