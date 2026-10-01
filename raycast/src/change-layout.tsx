import { Action, ActionPanel, Icon, List, closeMainWindow, showHUD } from "@raycast/api";
import { useEffect, useState } from "react";
import { getState, run, State } from "./lib/spacialctl";

// #198: change the focused workspace's layout by name — the picker the workspace list used to look
// like. The current layout is marked; picking one runs `spacialctl change-layout <id>`.
export default function ChangeLayout() {
  const [state, setState] = useState<State>();
  const [error, setError] = useState<string>();
  useEffect(() => {
    getState().then(setState, (e: Error) => setError(e.message));
  }, []);
  const active = state?.screens.find((s) => s.isFocused)?.workspaces.find((w) => w.isActive);
  return (
    <List
      isLoading={!state && !error}
      searchBarPlaceholder={active ? `Change layout of ${active.title ?? active.name}…` : "Change layout…"}
    >
      {error && <List.EmptyView icon={Icon.Warning} title="SpacialShell unavailable" description={error} />}
      {(state?.layouts ?? []).map((layout) => (
        <List.Item
          key={layout.id}
          icon={layout.id === active?.layout ? Icon.CheckCircle : Icon.Circle}
          title={layout.name}
          subtitle={layout.builtin ? undefined : "custom"}
          accessories={layout.id === active?.layout ? [{ text: "current" }] : []}
          actions={
            <ActionPanel>
              <Action
                title="Change Layout"
                icon={Icon.AppWindowGrid3x3}
                onAction={async () => {
                  await closeMainWindow();
                  try {
                    await run(["change-layout", layout.id]);
                    await showHUD(`Layout: ${layout.name}`);
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
