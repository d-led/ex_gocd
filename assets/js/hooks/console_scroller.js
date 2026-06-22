// Auto-scrolls console log container to bottom.
// Respects data-follow="true" attribute — only scrolls when following is enabled.
export const ConsoleScroller = {
  mounted() {
    this.scrollIfFollowing()
  },
  updated() {
    this.scrollIfFollowing()
  },
  scrollIfFollowing() {
    if (this.el.dataset.follow === "true") {
      this.el.scrollTop = this.el.scrollHeight
    }
  }
}
