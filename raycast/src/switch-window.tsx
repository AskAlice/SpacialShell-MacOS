import { Action, ActionPanel, Icon, List, closeMainWindow, showHUD } from "@raycast/api";
import { useEffect, useState } from "react";
import { getState, run, State } from "./lib/spacialctl";

// #199: every window on every display, searchable by app and title (Raycast filters on the
// title, subtitle and keywords). The highlighted one's thumbnail shows beside the list: fetched
// once per window through `spacialctl window-preview`, which writes the shell's cached picture
// (taken now if missing) to a PNG.
interface Row {
  key: string;
  id: number;
  pid: number;
  title: string;
  app: string;
  workspace: string;
  focused: boolean;
}

export default function SwitchWindow() {
  const [state, setState] = useState<State>();
  const [error, setError] = useState<string>();
  const [previews, setPreviews] = useState<Record<string, string | null>>({});
  useEffect(() => {
    getState().then(setState, (e: Error) => setError(e.message));
  }, []);

  const rows: Row[] = [...(state?.screens ?? [])]
    .sort((a, b) => Number(b.isFocused) - Number(a.isFocused))
    .flatMap((screen) =>
      screen.workspaces.flatMap((ws, i) =>
        (ws.windows ?? []).map((w) => ({
          key: `${w.id}@${w.pid}`,
          id: w.id,
          pid: w.pid,
          title: w.title || w.appName || "Untitled",
          app: w.appName ?? w.bundleID ?? `pid ${w.pid}`,
          workspace: `${i + 1} ${ws.title ?? ws.name}`,
          focused: w.isFocused,
        })),
      ),
    );

  const loadPreview = async (key: string | null) => {
    const row = rows.find((r) => r.key === key);
    if (!row || row.key in previews) return;
    setPreviews((p) => ({ ...p, [row.key]: null }));
    try {
      const out = JSON.parse(await run(["window-preview", String(row.id), String(row.pid)])) as { path: string };
      setPreviews((p) => ({ ...p, [row.key]: out.path }));
    } catch {
      // No picture (not capturable, or no Screen Recording): the detail shows text only.
    }
  };

  return (
    <List
      isLoading={!state && !error}
      isShowingDetail
      searchBarPlaceholder="Switch to window… (app or title)"
      onSelectionChange={loadPreview}
    >
      {error && <List.EmptyView icon={Icon.Warning} title="SpacialShell unavailable" description={error} />}
      {rows.map((r) => (
        <List.Item
          key={r.key}
          id={r.key}
          icon={r.focused ? Icon.CheckCircle : Icon.AppWindow}
          title={r.title}
          subtitle={r.app}
          keywords={[r.app, r.workspace]}
          detail={
            <List.Item.Detail
              markdown={previews[r.key] ? `![${r.title}](${encodeURI("file://" + previews[r.key])})` : undefined}
              metadata={
                <List.Item.Detail.Metadata>
                  <List.Item.Detail.Metadata.Label title="App" text={r.app} />
                  <List.Item.Detail.Metadata.Label title="Title" text={r.title} />
                  <List.Item.Detail.Metadata.Label title="Workspace" text={r.workspace} />
                </List.Item.Detail.Metadata>
              }
            />
          }
          actions={
            <ActionPanel>
              <Action
                title="Switch to Window"
                icon={Icon.ArrowRight}
                onAction={async () => {
                  await closeMainWindow();
                  try {
                    await run(["call", "focus-window", JSON.stringify({ window: { id: r.id, pid: r.pid } })]);
                    await showHUD(r.title);
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
