import { closeMainWindow, showHUD } from "@raycast/api";
import { run } from "./spacialctl";

/** Command file body for every keystroke-like verb: run it, flash a HUD. */
export const noView = (command: string, hud: string) => async () => {
  await closeMainWindow();
  try {
    await run(["run", command]);
    await showHUD(hud);
  } catch (e) {
    await showHUD(e instanceof Error ? e.message : "SpacialShell error");
  }
};
