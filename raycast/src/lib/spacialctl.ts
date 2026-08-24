import { getPreferenceValues } from "@raycast/api";
import { execFile } from "node:child_process";
import { accessSync, constants } from "node:fs";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const candidates = [
  "/Applications/SpacialShell.app/Contents/MacOS/spacialctl",
  `${process.env.HOME}/Applications/SpacialShell.app/Contents/MacOS/spacialctl`,
  "/opt/homebrew/bin/spacialctl",
  "/usr/local/bin/spacialctl",
];

function binary(): string {
  const pref = getPreferenceValues<{ spacialctl?: string }>().spacialctl?.trim();
  for (const path of pref ? [pref, ...candidates] : candidates) {
    try {
      accessSync(path, constants.X_OK);
      return path;
    } catch {
      // keep looking
    }
  }
  throw new Error("spacialctl not found — set its path in the extension preferences");
}

export async function run(args: string[]): Promise<string> {
  try {
    return (await execFileAsync(binary(), args)).stdout;
  } catch (e) {
    const err = e as { code?: number; stderr?: string; message: string };
    if (err.code === 3) throw new Error("SpacialShell is not running");
    throw new Error(err.stderr?.trim().replace(/^spacialctl: /, "") || err.message);
  }
}

export interface Workspace {
  id: string;
  name: string;
  symbol: string;
  layout: string;
  pinned: boolean;
  isActive: boolean;
  windowCount: number;
}
export interface Screen {
  display: string;
  isFocused: boolean;
  activeIndex: number;
  workspaces: Workspace[];
}
export interface State {
  v: number;
  capabilities: string[];
  screens: Screen[];
}

export const getState = async (): Promise<State> => JSON.parse(await run(["state"])) as State;
