// Enter in the tag search box picks or creates a tag instead of submitting the item form.
export const TagInput = {
  mounted() {
    this.el.addEventListener("keydown", event => {
      if (event.key !== "Enter") return
      event.preventDefault()
      this.pushEventTo(this.el, "tag_enter", {})
    })
  },
}
