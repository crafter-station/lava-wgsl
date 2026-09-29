import {
  DEFAULTS,
  preset,
  PRESETS,
  samePreset,
  SECTIONS,
  toQuery,
  type Control,
  type Settings,
} from "../state/settings";
import type { Store } from "../state/store";
import "./drawer.css";

const COPIED = 1400;

export interface DrawerOptions {
  readonly settings: Store<Settings>;
  readonly capture: () => Promise<Blob>;
}

function node<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attributes: Record<string, string> = {},
  ...children: (Node | string)[]
): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag);
  Object.entries(attributes).forEach(([name, value]) => element.setAttribute(name, value));
  element.append(...children);
  return element;
}

const button = (label: string, action: () => void, className = "") => {
  const element = node("button", { type: "button", class: className }, label);
  element.addEventListener("click", action);
  return element;
};

const title = (value: string) => value[0].toUpperCase() + value.slice(1);

interface Bound {
  readonly element: HTMLElement;
  sync(settings: Settings): void;
}

function bind(control: Control, settings: Store<Settings>): Bound {
  if (control.kind === "choice") {
    const options = control.options.map((value) => ({
      value,
      element: button(title(value), () => settings.set({ [control.key]: value } as Partial<Settings>)),
    }));
    return {
      element: node(
        "div",
        { class: "choice" },
        node("span", {}, control.label),
        node(
          "div",
          { class: "segments", role: "group", "aria-label": control.label },
          ...options.map((o) => o.element),
        ),
      ),
      sync: (current) =>
        options.forEach(({ value, element }) =>
          element.setAttribute("aria-pressed", `${current[control.key] === value}`),
        ),
    };
  }
  const { key, label, min, max, step, unit = "" } = control;
  const input = node("input", {
    type: "range",
    min: `${min}`,
    max: `${max}`,
    step: `${step}`,
    "aria-label": label,
  });
  const readout = node("span", { class: "value" });
  const digits = Math.max(0, -Math.floor(Math.log10(step)));
  input.addEventListener("input", () => settings.set({ [key]: Number(input.value) }));
  input.addEventListener("dblclick", () => settings.set({ [key]: DEFAULTS[key] }));
  return {
    element: node("label", { class: "row" }, node("span", {}, label), readout, input),
    sync: (current) => {
      input.value = `${current[key]}`;
      readout.textContent = `${current[key].toFixed(digits)}${unit}`;
    },
  };
}

async function download(blob: Blob, name: string) {
  const file = new File([blob], name, { type: blob.type });
  if (matchMedia("(pointer: coarse)").matches && navigator.canShare?.({ files: [file] })) {
    await navigator.share({ files: [file] }).catch(() => {});
    return;
  }
  const url = URL.createObjectURL(blob);
  node("a", { href: url, download: name }).click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function createDrawer({ settings, capture }: DrawerOptions): void {
  const handle = node("button", { class: "handle", type: "button", "aria-label": "Open lava controls" });
  const close = button("Close", () => setOpen(false));
  const presets = PRESETS.map(([name, patch]) => ({
    patch,
    element: button(name, () => settings.set(preset(patch))),
  }));
  const bound = SECTIONS.map(({ title, controls }) => {
    const rows = controls.map((control) => bind(control, settings));
    return { rows, element: node("section", {}, node("h3", {}, title), ...rows.map((r) => r.element)) };
  });

  let copying = 0;
  const link = button("Copy link", async () => {
    await navigator.clipboard.writeText(location.href);
    link.textContent = "Copied";
    clearTimeout(copying);
    copying = window.setTimeout(() => (link.textContent = "Copy link"), COPIED);
  });
  const save = button("Save PNG", async () => download(await capture(), "lava.png"));
  const reset = button("Reset", () => settings.set(DEFAULTS), "quiet");

  const sheet = node(
    "aside",
    { class: "sheet", "aria-label": "Lava controls" },
    node("div", { class: "top" }, node("span", { class: "title" }, "Lava"), close),
    node(
      "div",
      { class: "finishes", role: "group", "aria-label": "Presets" },
      ...presets.map((p) => p.element),
    ),
    ...bound.map((section) => section.element),
    node("div", { class: "actions" }, save, link),
    node("div", { class: "actions" }, reset),
  );
  document.body.append(handle, sheet);

  const refresh = () => {
    const current = settings.get();
    presets.forEach(({ patch, element }) =>
      element.setAttribute("aria-pressed", `${samePreset(current, patch)}`),
    );
    bound.forEach(({ rows }) => rows.forEach(({ sync }) => sync(current)));
  };

  const setOpen = (open: boolean) => {
    sheet.toggleAttribute("data-open", open);
    handle.setAttribute("aria-expanded", `${open}`);
    sheet.inert = !open;
    if (open) refresh();
  };
  handle.addEventListener("click", () => setOpen(true));
  document.querySelector("#stage")?.addEventListener("click", () => setOpen(false));
  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape") setOpen(false);
    if (event.target instanceof HTMLInputElement) return;
    if (event.key === " ") {
      event.preventDefault();
      settings.set({ motion: settings.get().motion === "play" ? "pause" : "play" });
    }
  });
  settings.subscribe(refresh);
  settings.subscribe((current) => history.replaceState(null, "", location.pathname + toQuery(current)));
  setOpen(false);
}
