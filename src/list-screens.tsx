import { Action, ActionPanel, Color, environment, Icon, List, showToast, Toast } from "@raycast/api";
import { execFile } from "child_process";
import { join } from "path";
import { useEffect, useState } from "react";
import { promisify } from "util";

const run = promisify(execFile);
const BIN = join(environment.assetsPath, "cursor-screen");

type Screen = {
  index: number;
  id: number;
  name: string;
  main: boolean;
  builtin: boolean;
  virtual: boolean;
  vendor: number;
  model: number;
  serial: number;
  x: number;
  y: number;
  width: number;
  height: number;
};

export default function ListScreens() {
  const [screens, setScreens] = useState<Screen[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const { stdout } = await run(BIN, ["screens"]);
        setScreens(JSON.parse(stdout) as Screen[]);
      } catch (error) {
        await showToast({
          style: Toast.Style.Failure,
          title: "Couldn't list screens",
          message: error instanceof Error ? error.message : String(error),
        });
      } finally {
        setIsLoading(false);
      }
    })();
  }, []);

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Search screens…">
      {screens.map((s) => (
        <List.Item
          key={s.id}
          icon={s.virtual ? Icon.Monitor : Icon.Desktop}
          title={s.name}
          subtitle={`${s.width}×${s.height} @ (${s.x}, ${s.y})`}
          keywords={[s.virtual ? "virtual" : "physical", s.builtin ? "builtin" : "external"]}
          accessories={[
            s.main ? { tag: { value: "Main", color: Color.Blue } } : {},
            s.builtin ? { tag: "Built-in" } : { tag: "External" },
            s.virtual
              ? { tag: { value: "Virtual", color: Color.Purple } }
              : { tag: { value: "Physical", color: Color.Green } },
          ]}
          actions={
            <ActionPanel>
              <Action.CopyToClipboard title="Copy Screen JSON" content={JSON.stringify(s, null, 2)} />
              <Action.CopyToClipboard title="Copy Display Name" content={s.name} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
