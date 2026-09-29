import { createLava } from "./lava/renderer";
import { fromQuery } from "./state/settings";
import { createStore } from "./state/store";
import { createDrawer } from "./ui/drawer";
import "./styles.css";

const canvas = document.querySelector<HTMLCanvasElement>("#stage")!;
const settings = createStore(fromQuery(location.search));
const frame = () => (document.body.dataset.fit = settings.get().fit);
settings.subscribe(frame);
frame();

const lava = createLava(canvas, settings);
createDrawer({ settings, capture: lava.capture });

lava.ready.catch((error: unknown) => {
  const notice = document.createElement("p");
  notice.className = "notice";
  notice.textContent = "Lava needs a browser with WebGPU";
  document.body.append(notice);
  console.error(error);
});
