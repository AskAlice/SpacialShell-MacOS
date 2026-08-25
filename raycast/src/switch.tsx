import { Action, ActionPanel, Icon, List, closeMainWindow, showHUD } from "@raycast/api";
import { useEffect, useState } from "react";
import { getState, run, State } from "./lib/spacialctl";

export default function Switch() {
  const [state, setState] = useState<State>();
  const [error, setError] = useState<string>();
  useEffect(() => {
    getState().then(setState, (e: Error) => setError(e.message));
  }, []);
  const focused = state?.screens.find((s) => s.isFocused);
  return (
    <List isLoading={!state && !error} searchBarPlaceholder="Focus workspace…">
      {error && <List.EmptyView icon={Icon.Warning} title="SpacialShell unavailable" description={error} />}
      {focused?.workspaces.map((ws, i) => (
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
                    await run(["run", `focus-workspace-${i + 1}`]);
                    await showHUD(ws.name);
                  } catch (e) {
                    await showHUD(e instanceof Error ? e.message : "SpacialShell error");
                  }
                }}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
