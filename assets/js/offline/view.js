// The offline screens: the shopping list and the inventory, drawn from the saved copy.
// Tailwind finds the class names below because it scans assets/js for them.

import {stockLabel, tileText, matches} from "./state.js"

const escapeHtml = text =>
  String(text).replace(/[&<>"']/g, char => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"}[char]))

const BANNERS = {
  offline: {icon: "hero-signal-slash", text: "Offline · changes sync when you're back", tone: "bg-neutral text-neutral-content"},
  syncing: {icon: "hero-arrow-path", text: "Back online · syncing…", tone: "bg-secondary text-secondary-content"},
  "signed-out": {icon: "hero-lock-closed", text: "You are signed out · sign in to sync", tone: "bg-error text-error-content"}
}

export function banner(status, queued) {
  const {icon, text, tone} = BANNERS[status] ?? BANNERS.offline
  const pending = queued > 0 ? `<span class="ml-auto shrink-0 rounded-full bg-white/20 px-2.5 py-0.5 text-xs font-extrabold">${queued} to sync</span>` : ""
  const link = status === "signed-out" ? `<a href="/sign-in" class="ml-auto shrink-0 font-extrabold underline">Sign in</a>` : ""

  return `<div role="status" class="${tone} flex items-center gap-2.5 px-4 py-2.5 text-sm font-semibold">
    <span class="${icon} size-5 shrink-0"></span><span class="min-w-0">${text}</span>${pending}${link}</div>`
}

function entryIcon(entry, dimmed) {
  const dim = dimmed ? "opacity-70 grayscale" : ""
  if (entry.emoji) return `<span class="text-2xl ${dim}">${escapeHtml(entry.emoji)}</span>`
  return `<span class="grid size-7 shrink-0 place-items-center rounded-full bg-base-300/60 text-sm font-bold text-base-content/70 ${dim}">${escapeHtml(tileText(entry))}</span>`
}

export function shoppingList({open, checked}) {
  const toBuy = open.length === 0 ? "Nothing to buy" : `${open.length} to buy`

  const openRows = open.map(entry => `
    <li class="flex items-center gap-3 rounded-box bg-base-100 py-2.5 pr-4 pl-2.5 shadow-card">
      <button type="button" data-action="check" data-id="${entry.id}" aria-label="Check off ${escapeHtml(entry.name)}"
        class="size-11 shrink-0 rounded-full border-[2.5px] border-primary/55 transition active:scale-90"></button>
      <span class="flex min-w-0 flex-1 items-center gap-2 text-[17px] font-bold">${entryIcon(entry)}<span class="truncate">${escapeHtml(entry.name)}</span></span>
      <span class="text-lg font-extrabold tabular-nums">× ${entry.quantity}</span>
    </li>`).join("")

  const cart = checked.length === 0 ? "" : `
    <section class="mt-6">
      <h2 class="mb-2.5 px-1 font-display text-xl font-bold">In the cart <small class="ml-1 font-sans text-sm font-semibold text-base-content/55">${checked.length}</small></h2>
      <ul class="grid gap-2.5">${checked.map(entry => `
        <li class="flex items-center gap-3 rounded-box border-[1.5px] border-dashed border-base-300 py-2.5 pr-4 pl-2.5">
          <button type="button" data-action="uncheck" data-id="${entry.id}" aria-label="Put ${escapeHtml(entry.name)} back on the list"
            class="grid size-11 shrink-0 place-items-center rounded-full bg-secondary text-secondary-content transition active:scale-90"><span class="hero-check size-6"></span></button>
          <span class="flex min-w-0 flex-1 items-center gap-2 text-[17px] font-bold text-base-content/55">${entryIcon(entry, true)}<span class="truncate line-through decoration-[1.5px]">${escapeHtml(entry.name)}</span></span>
          <span class="font-bold text-base-content/55 tabular-nums">× ${entry.quantity}</span>
        </li>`).join("")}</ul>
    </section>`

  const empty = open.length === 0 && checked.length === 0 ? `
    <p class="mt-14 text-center text-base-content/55"><span class="block text-5xl">🧺</span>
    <span class="mt-3 block font-display text-xl text-base-content">Your list is empty</span></p>` : ""

  return `<h1 class="font-display text-4xl leading-none font-bold tracking-tight">Shopping list</h1>
    <p class="mt-1 text-sm text-base-content/60">${toBuy}</p>
    ${empty}<ul class="mt-5 grid gap-2.5">${openRows}</ul>${cart}`
}

export function inventoryRows(items, query) {
  const shown = items.filter(item => matches(item, query))

  if (shown.length === 0) {
    return `<p class="mt-10 text-center text-base-content/55">${items.length === 0 ? "No items saved yet." : "Nothing matches."}</p>`
  }

  return shown.map(item => `
    <li class="flex items-center gap-3 rounded-box bg-base-100 p-3.5 shadow-card">
      <span class="relative grid size-12 shrink-0 place-items-center rounded-2xl bg-base-300/60 text-2xl font-bold text-base-content/70">
        <span class="${item.empty ? "opacity-60 grayscale" : ""}">${escapeHtml(tileText(item))}</span>
        ${item.on_list ? `<span title="On the shopping list" class="absolute -top-1.5 -right-1.5 grid size-[22px] place-items-center rounded-full border-[2.5px] border-base-100 bg-primary text-primary-content"><span class="hero-shopping-cart-solid size-2.5"></span></span>` : ""}
      </span>
      <div class="min-w-0 flex-1">
        <div class="truncate text-[17px] font-bold">${escapeHtml(item.name)}</div>
        <div class="text-sm ${item.empty ? "font-bold text-error" : "text-base-content/60"}">${stockLabel(item)}</div>
      </div>
    </li>`).join("")
}

export function inventory({items}, query) {
  return `<h1 class="font-display text-4xl leading-none font-bold tracking-tight">Inventory</h1>
    <div class="relative mt-5">
      <span class="hero-magnifying-glass pointer-events-none absolute top-1/2 left-4 size-5 -translate-y-1/2 text-base-content/45"></span>
      <input id="offline-search" type="search" value="${escapeHtml(query)}" placeholder="Search" autocomplete="off"
        class="h-12 w-full rounded-full border-0 bg-base-100 pr-4 pl-12 text-base shadow-card outline-none placeholder:text-base-content/45 focus:ring-2 focus:ring-primary/40" />
    </div>
    <ul id="offline-inventory" class="mt-5 grid gap-3">${inventoryRows(items, query)}</ul>`
}

export function page({status, queued, tab, openCount, content}) {
  const tabClass = active =>
    `flex flex-col items-center gap-0.5 rounded-2xl py-2 text-xs font-bold transition active:scale-95 ${active ? "bg-primary/10 text-primary" : "text-base-content/55"}`

  return `<div class="flex min-h-dvh flex-col bg-base-200 text-base-content">
    <div class="pt-[env(safe-area-inset-top)]">${banner(status, queued)}</div>
    <header class="mx-auto flex h-14 w-full max-w-2xl items-center px-4">
      <span class="font-display text-2xl font-bold tracking-tight text-primary">Kura</span>
    </header>
    <main class="mx-auto w-full max-w-2xl flex-1 px-4 pt-1 pb-32">${content}</main>
    <nav class="fixed inset-x-0 bottom-0 z-10 border-t border-base-300 bg-base-200/90 px-4 pt-2 pb-[max(0.75rem,env(safe-area-inset-bottom))] backdrop-blur-md" aria-label="Main">
      <div class="mx-auto grid max-w-2xl grid-cols-2 gap-2">
        <button type="button" data-action="tab" data-tab="list" class="${tabClass(tab === "list")}">
          <span class="relative"><span class="hero-shopping-cart size-6"></span>
            ${openCount > 0 ? `<span class="absolute -top-1.5 -right-3.5 grid h-[18px] min-w-[18px] place-items-center rounded-full bg-primary px-1 text-[11px] font-extrabold text-primary-content">${openCount}</span>` : ""}
          </span>Shopping list</button>
        <button type="button" data-action="tab" data-tab="inventory" class="${tabClass(tab === "inventory")}">
          <span class="hero-archive-box size-6"></span>Inventory</button>
      </div>
    </nav>
  </div>`
}

export function noData() {
  return `<p class="mt-14 text-center text-base-content/55"><span class="block text-5xl">🧺</span>
    <span class="mt-3 block font-display text-xl text-base-content">Nothing saved on this phone yet</span>
    Open Kura once while you have a connection, and your lists will be here next time.</p>`
}
