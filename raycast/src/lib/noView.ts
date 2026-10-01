import { closeMainWindow, showHUD } from "@raycast/api";
import { run } from "./spacialctl";

/** Command file body for every keystroke-like verb: run it, flash a HUD. A string is a bound
 *  command (`spacialctl run <name>`); an array is a spacialctl subcommand as written (`["reload"]`). */
export const noView = (command: string | string[], hud: string) => async () => {
  await closeMainWindow();
  try {
    await run(typeof command === "string" ? ["run", command] : command);
    await showHUD(hud);
  } catch (e) {
    await showHUD(e instanceof Error ? e.message : "SpacialShell error");
  }
};
