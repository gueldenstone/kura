// Flicking through cards: drag the card sideways and let go. A long enough drag to the left pushes
// "swipe_next" and to the right "swipe_prev"; a shorter one springs back. The card to move is the
// child marked `data-swipe-card`, which the server replaces for every item.
const THRESHOLD = 70

export const Swipe = {
  mounted() {
    this.start = null

    this.el.addEventListener("pointerdown", event => {
      if (event.target.closest("button, a, input, select, textarea")) return
      this.card = this.el.querySelector("[data-swipe-card]")
      if (!this.card) return
      this.start = {x: event.clientX, y: event.clientY, dragging: false}
    })

    this.el.addEventListener("pointermove", event => {
      if (!this.start || !this.card) return
      const dx = event.clientX - this.start.x
      const dy = event.clientY - this.start.y

      if (!this.start.dragging) {
        if (Math.abs(dx) < 8 || Math.abs(dx) < Math.abs(dy)) return
        this.start.dragging = true
        try {
          this.el.setPointerCapture(event.pointerId)
        } catch (_error) {
          // The pointer is already gone; the drag still works without capture.
        }
        this.card.style.transition = "none"
      }

      this.card.style.transform = `translateX(${dx}px) rotate(${dx / 40}deg)`
      this.card.style.opacity = String(1 - Math.min(Math.abs(dx) / 400, 0.5))
    })

    const finish = event => {
      if (!this.start) return
      const {dragging, x} = this.start
      const dx = event.clientX - x
      this.start = null
      if (!dragging || !this.card) return

      const card = this.card
      const springBack = () => {
        card.style.transition = "transform 200ms ease-out, opacity 200ms ease-out"
        card.style.transform = ""
        card.style.opacity = ""
      }

      if (Math.abs(dx) < THRESHOLD) return springBack()

      // The server replaces the card when there is another one to show; otherwise it stays put.
      this.pushEvent(dx < 0 ? "swipe_next" : "swipe_prev", {}, reply => {
        if (reply.moved) {
          card.style.transition = "transform 150ms ease-in, opacity 150ms ease-in"
          card.style.transform = `translateX(${dx < 0 ? "-" : ""}110%)`
          card.style.opacity = "0"
        } else {
          springBack()
        }
      })
    }

    this.el.addEventListener("pointerup", finish)
    this.el.addEventListener("pointercancel", () => {
      if (!this.card) return
      this.start = null
      this.card.style.transition = "transform 200ms ease-out, opacity 200ms ease-out"
      this.card.style.transform = ""
      this.card.style.opacity = ""
    })
  },
}
