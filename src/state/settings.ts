export const LAYOUTS = ["field", "random"] as const;
export const MOTIONS = ["play", "pause"] as const;
export const DRONES = ["fly", "hold"] as const;
export const FITS = ["cover", "contain"] as const;
export const QUALITIES = ["draft", "hd", "ultra"] as const;

export interface Settings {
  readonly layout: (typeof LAYOUTS)[number];
  readonly seed: number;
  readonly width: number;
  readonly land: number;
  readonly islands: number;
  readonly meander: number;
  readonly motion: (typeof MOTIONS)[number];
  readonly speed: number;
  readonly spin: number;
  readonly life: number;
  readonly plate: number;
  readonly detail: number;
  readonly heat: number;
  readonly sheen: number;
  readonly drone: (typeof DRONES)[number];
  readonly position: number;
  readonly zoom: number;
  readonly turn: number;
  readonly panX: number;
  readonly panY: number;
  readonly fit: (typeof FITS)[number];
  readonly exposure: number;
  readonly glow: number;
  readonly haze: number;
  readonly grain: number;
  readonly quality: (typeof QUALITIES)[number];
}

type KeysOf<T> = { [K in keyof Settings]: Settings[K] extends T ? K : never }[keyof Settings];
export type NumberKey = KeysOf<number>;
export type ChoiceKey = KeysOf<string>;

export type Control =
  | {
      readonly kind: "range";
      readonly key: NumberKey;
      readonly label: string;
      readonly min: number;
      readonly max: number;
      readonly step: number;
      readonly unit?: string;
    }
  | {
      readonly kind: "choice";
      readonly key: ChoiceKey;
      readonly label: string;
      readonly options: readonly string[];
    };

export interface Section {
  readonly title: string;
  readonly controls: readonly Control[];
}

const range = (
  key: NumberKey,
  label: string,
  min: number,
  max: number,
  step: number,
  unit?: string,
): Control => ({
  kind: "range",
  key,
  label,
  min,
  max,
  step,
  unit,
});

const choice = (key: ChoiceKey, label: string, options: readonly string[]): Control => ({
  kind: "choice",
  key,
  label,
  options,
});

export const SECTIONS: readonly Section[] = [
  {
    title: "World",
    controls: [
      choice("layout", "Layout", LAYOUTS),
      range("seed", "Seed", 1, 999, 1),
      range("width", "Channel width", 120, 520, 5, "px"),
      range("land", "Land between", 60, 1200, 10, "px"),
      range("islands", "Islands", 0, 1, 0.01),
      range("meander", "Meander", 0, 2, 0.01),
    ],
  },
  {
    title: "Flow",
    controls: [
      choice("motion", "Motion", MOTIONS),
      range("speed", "Velocity", 0.1, 4, 0.05, "×"),
      range("spin", "Swirl", 0, 3, 0.05),
      range("life", "Renewal", 2, 20, 0.5, "s"),
    ],
  },
  {
    title: "Crust",
    controls: [
      range("plate", "Plate size", 14, 70, 2, "px"),
      range("detail", "Texture", 0, 2.5, 0.05, "×"),
      range("heat", "Heat", -0.4, 0.4, 0.01),
      range("sheen", "Sky sheen", 0, 3, 0.05, "×"),
    ],
  },
  {
    title: "Camera",
    controls: [
      choice("drone", "Drone", DRONES),
      range("position", "Position", 0, 1, 0.01),
      range("zoom", "Zoom", 1, 5, 0.01, "×"),
      range("turn", "Turn", -180, 180, 1, "°"),
      range("panX", "Pan x", -1, 1, 0.01),
      range("panY", "Pan y", -1, 1, 0.01),
      choice("fit", "Frame", FITS),
    ],
  },
  {
    title: "Light",
    controls: [
      range("exposure", "Exposure", 0.2, 3, 0.01),
      range("glow", "Glow", 0, 6, 0.05, "×"),
      range("haze", "Heat haze", 0, 6, 0.05, "×"),
      range("grain", "Grain", 0, 4, 0.05, "×"),
    ],
  },
  {
    title: "Render",
    controls: [choice("quality", "Quality", QUALITIES)],
  },
];

export const CONTROLS: readonly Control[] = SECTIONS.flatMap((section) => section.controls);

export const DEFAULTS: Settings = {
  layout: "field",
  seed: 7,
  width: 200,
  land: 320,
  islands: 0.55,
  meander: 1,
  motion: "play",
  speed: 1,
  spin: 0.6,
  life: 6,
  plate: 28,
  detail: 1,
  heat: 0,
  sheen: 1,
  drone: "fly",
  position: 0.5,
  zoom: 1,
  turn: 0,
  panX: 0,
  panY: 0,
  fit: "cover",
  exposure: 1,
  glow: 1,
  haze: 1,
  grain: 1,
  quality: "hd",
};

export const PRESETS: readonly (readonly [name: string, patch: Partial<Settings>])[] = [
  ["Field", {}],
  ["Molten", { heat: 0.18, glow: 2.4, haze: 2.5, sheen: 0.6, speed: 1.4 }],
  ["Crusted", { heat: -0.16, detail: 1.6, speed: 0.55, glow: 0.6, sheen: 1.6 }],
  ["Surge", { speed: 2.6, spin: 1.4, life: 4, haze: 2 }],
  ["Close", { zoom: 2.6, drone: "hold", position: 0.35, detail: 1.2 }],
  ["Braided", { layout: "random", islands: 0.9, width: 210, land: 140, meander: 1.4, seed: 21 }],
];

export const preset = (patch: Partial<Settings>): Settings => ({ ...DEFAULTS, ...patch });

export const samePreset = (settings: Settings, patch: Partial<Settings>): boolean =>
  CONTROLS.every(({ key }) => settings[key] === preset(patch)[key]);

function read(control: Control, raw: string | null, fallback: Settings[keyof Settings]) {
  if (raw === null) return fallback;
  if (control.kind === "choice") return control.options.includes(raw) ? raw : fallback;
  const value = Number(raw);
  return Number.isFinite(value) ? Math.min(control.max, Math.max(control.min, value)) : fallback;
}

export function fromQuery(query: string): Settings {
  const params = new URLSearchParams(query);
  return Object.fromEntries(
    CONTROLS.map((control) => [control.key, read(control, params.get(control.key), DEFAULTS[control.key])]),
  ) as unknown as Settings;
}

export function toQuery(settings: Settings): string {
  const changed = CONTROLS.filter(({ key }) => settings[key] !== DEFAULTS[key]);
  const params = new URLSearchParams(changed.map(({ key }) => [key, `${settings[key]}`]));
  return params.size ? `?${params}` : "";
}
