import { Action, ActionPanel, Icon, List, closeMainWindow, showHUD } from "@raycast/api";
import { useEffect, useState } from "react";
import { getState, run, State, Workspace } from "./lib/spacialctl";

// Every display's workspaces, focused display first. Switching goes by workspace id (#131), so row
// 11+ and rows on another display are reachable. A shell older than #131 has no `focus-workspace`
// verb: it gets the old `focus-workspace-N`, which only reaches the focused display's first ten.
export default function Switch() {
  const [state, setState] = useState<State>();
  const [error, setError] = useState<string>();
  useEffect(() => {
    getState().then(setState, (e: Error) => setError(e.message));
  }, []);
  const byId = state?.capabilities.includes("focus-workspace") ?? false;
  const screens = [...(state?.screens ?? [])]
    .filter((s) => byId || s.isFocused)
    .sort((a, b) => Number(b.isFocused) - Number(a.isFocused));
  const item = (ws: Workspace, i: number) => (
    <List.Item
      key={ws.id}
      icon={ws.isActive ? Icon.CheckCircle : Icon.Circle}
      title={ws.name}
      subtitle={ws.layout}
      accessories={[
        ...(ws.pinned ? [{ icon: Icon.Pin }] : []),
        { text: `${ws.windowCount} ${ws.windowCount === 1 ? "window" : "windows"}` },
      ]}
      actions={
        <ActionPanel>
          <Action
            title="Focus Workspace"
            icon={Icon.ArrowRight}
            onAction={async () => {
              await closeMainWindow();
              try {
                await run(byId ? ["focus-workspace", ws.id] : ["run", `focus-workspace-${i + 1}`]);
                await showHUD(ws.name);
              } catch (e) {
                await showHUD(e instanceof Error ? e.message : "SpacialShell error");
              }
            }}
          />
        </ActionPanel>
      }
    />
  );
  return (
    <List isLoading={!state && !error} searchBarPlaceholder="Focus workspace…">
      {error && <List.EmptyView icon={Icon.Warning} title="SpacialShell unavailable" description={error} />}
      {screens.length === 1
        ? screens[0].workspaces.map((ws, i) => item(ws, i))
        : screens.map((screen, n) => (
            <List.Section key={screen.display} title={screen.isFocused ? "Focused display" : `Display ${n + 1}`}>
              {screen.workspaces.map((ws, i) => item(ws, i))}
            </List.Section>
          ))}
    </List>
  );
}
