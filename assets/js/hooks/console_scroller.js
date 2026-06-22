// Auto-scrolls console log container to bottom.
// Respects data-follow="true" — only scrolls when following.
// Timestamps toggle: when .show-timestamps is present, shows line timestamps.
export const ConsoleScroller = {
  mounted() {
    this.scrollIfFollowing()
    this.setupTimestamps()
  },
  updated() {
    this.scrollIfFollowing()
    this.setupTimestamps()
  },
  scrollIfFollowing() {
    if (this.el.dataset.follow === "true") {
      this.el.scrollTop = this.el.scrollHeight
    }
  },
  setupTimestamps() {
    const pre = this.el.querySelector('pre')
    if (!pre) return
    const show = this.el.classList.contains('show-timestamps')
    const lines = pre.innerHTML.split('\n')
    const now = new Date().toISOString().substr(11, 8)
    if (show) {
      pre.innerHTML = lines.map((l, i) =>
        `<span class="text-gray-500 select-none mr-2">[${now}]</span>${l}`
      ).join('\n')
    }
  }
}
