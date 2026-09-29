# Lava

Pahoehoe lava as pure maths on WebGPU, written in WGSL with [vgpu](https://vgpu.sh). There are no images, videos or baked textures. Everything you see is generated on the GPU every frame.

## Run

```bash
npm install
npm run dev        # http://localhost:5190
npm run build
```

It needs a browser with WebGPU: Chrome or Edge on desktop and Android, Safari on iOS 26 and macOS 26.

## How it is built

**Layout.** The field layout (`src/lava/field.ts`) is plain numbers:

- 13 rock outlines as vector polygons
- one stream value per rock body
- a slow drone path
- 48 soft heat blobs

The GPU rasterises the outlines into a signed distance field. The random layout generates meandering channels and islands from a seed instead.

**Any screen.** The world keeps a fixed height and grows sideways to match the screen, so it works from a phone in portrait to an ultrawide monitor. The field sits in the middle, and new land on both sides carries the lava wherever it crosses the field's edges: inflows come down from the top of the world and outflows leave through the bottom. A GPU pass gives each new rock region the stream value of the rock it touches, so the lava flows the right way across the seams.

**Flow.** A multigrid solve of `div(k grad psi) = 0` runs on the GPU. Rock bodies are held at their stream values, and a bank-drag term `k` adds shear and swirl. Velocity is the curl of `psi`, so lava can never leak through rock.

**Surface.** Heat comes from contact rims, shear, the heat blobs, and filaments that follow streamlines. It is shaded through an emission curve and a glossy sky reflection.

**Crust.** Rigid plates ride the flow in two phased layers. Each plate carries procedural crust:

- torn platelets whose cracks open wider where the lava is hotter
- plates that stretch along the flow in shear zones
- flow-aligned micro relief that catches the sky
- floating crust blocks

**Rock.** Warped toes with ropes near their margins, deep creases, and glassy basalt reflections. The rock is shaded once per world into a cache.

**Mobile.** 32-bit float fields are filtered by hand in WGSL (`shaders/sample.wgsl`), so the optional `float32-filterable` feature is not needed and it runs on phone GPUs. The pixel ratio is capped at 2.

```
src/
  main.ts              wiring
  state/settings.ts    playground schema, presets, URL sync
  ui/drawer.ts         the drawer
  lava/renderer.ts     frame loop
  lava/world.ts        terrain, flow solve, surface, rock cache
  lava/simulation.ts   plate advection and lookup
  lava/camera.ts       drone path and cover framing
  lava/field.ts        field layout data
  lava/shaders/*.wgsl
```

## Controls

The handle on the right edge opens the drawer. Tapping the lava or pressing Esc closes it, Space pauses, and double-clicking a slider resets it. Every change is kept in the URL.

| Section | Controls                                                              |
| ------- | --------------------------------------------------------------------- |
| World   | layout (field or random), seed, channel width, land, islands, meander |
| Flow    | motion, velocity, swirl, renewal                                      |
| Crust   | plate size, texture, heat, sky sheen                                  |
| Camera  | drone, position, zoom, turn, pan, frame                               |
| Light   | exposure, glow, heat haze, grain                                      |
| Render  | quality: draft, HD (native pixels), ultra (1.5x)                      |

## License

MIT
