import { Action, ActionPanel, Color, environment, Icon, List, showToast, Toast } from "@raycast/api";
import { execFile } from "child_process";
import { join } from "path";
import { useEffect, useState } from "react";
import { promisify } from "util";

const run = promisify(execFile);
const BIN = join(environment.assetsPath, "cursor-screen");

type Space = {
  index: number;
  managedSpaceID: number;
  type: number;
  typeLabel: string;
  uuid: string;
  current: boolean;
};

type DisplaySpaces = {
  display: string;
  displayIdentifier: string;
  spaces: Space[];
};

export default function ListSpaces() {
  const [displays, setDisplays] = useState<DisplaySpaces[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const { stdout } = await run(BIN, ["spaces"]);
        setDisplays(JSON.parse(stdout) as DisplaySpaces[]);
      } catch (error) {
        await showToast({
          style: Toast.Style.Failure,
          title: "Couldn't list Spaces",
          message: error instanceof Error ? error.message : String(error),
        });
      } finally {
        setIsLoading(false);
      }
    })();
  }, []);

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Search Spaces…">
      {displays.map((d) => (
        <List.Section key={d.displayIdentifier} title={d.display} subtitle={`${d.spaces.length} spaces`}>
          {d.spaces.map((s) => {
            const title = s.type === 0 ? `Desktop ${s.index}` : `${s.typeLabel} ${s.index}`;
            return (
              <List.Item
                key={s.uuid || `${d.displayIdentifier}-${s.index}`}
                icon={s.current ? { source: Icon.CheckCircle, tintColor: Color.Green } : Icon.Circle}
                title={title}
                subtitle={s.type === 0 ? undefined : s.typeLabel}
                keywords={[s.typeLabel, s.current ? "current" : ""]}
                accessories={[
                  s.current ? { tag: { value: "Current", color: Color.Green } } : {},
                  { text: `#${s.managedSpaceID}` },
                ]}
                actions={
                  <ActionPanel>
                    <Action.CopyToClipboard title="Copy Space UUID" content={s.uuid} />
                    <Action.CopyToClipboard title="Copy Space JSON" content={JSON.stringify(s, null, 2)} />
                    <Action.CopyToClipboard title="Copy All Spaces JSON" content={JSON.stringify(displays, null, 2)} />
                  </ActionPanel>
                }
              />
            );
          })}
        </List.Section>
      ))}
    </List>
  );
}
