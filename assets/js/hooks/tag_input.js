// Enter in the tag or location search box picks or creates one instead of submitting the item form.
export const TagInput = {
  mounted() {
    this.el.addEventListener("keydown", event => {
      if (event.key !== "Enter") return
      event.preventDefault()
      this.pushEventTo(this.el, "chip_enter", {kind: this.el.dataset.kind})
    })
  },
}
