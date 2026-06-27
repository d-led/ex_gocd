// Phoenix LiveView hook for Chart.js integration
// Attach with phx-hook="ChartHook" on a <canvas> element.
// Pass chart data via data-chart-* attributes.

const ChartHook = {
  mounted() {
    this.chart = null;
    this.initChart();
  },

  updated() {
    this.destroyChart();
    this.initChart();
  },

  destroyed() {
    this.destroyChart();
  },

  initChart() {
    const type = this.el.dataset.chartType || "bar";
    const raw = this.el.dataset.chartConfig;
    if (!raw) return;

    let config;
    try {
      config = JSON.parse(raw);
    } catch (_e) {
      return;
    }

    config.type = type;
    // Default responsive options matching GoCD aesthetic
    config.options = {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: true, position: "bottom" },
        ...(config.options?.plugins || {}),
      },
      scales: {
        y: { beginAtZero: true },
        ...(config.options?.scales || {}),
      },
      ...(config.options || {}),
    };

    // Allow overriding scales per chart type
    if (config.options?.scales) {
      config.options.scales = {
        y: { beginAtZero: true },
        ...config.options.scales,
      };
    }

    this.chart = new window.Chart(this.el, config);
  },

  destroyChart() {
    if (this.chart) {
      this.chart.destroy();
      this.chart = null;
    }
  },
};

export default ChartHook;
