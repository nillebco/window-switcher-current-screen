import { closeMainWindow, environment, PopToRootType, showHUD } from "@raycast/api";
import { execFile } from "child_process";
import { join } from "path";
import { promisify } from "util";

const run = promisify(execFile);
const BIN = join(environment.assetsPath, "cursor-screen");

export default async function ClickAtCursor() {
  // Close Raycast first so the click lands on the window underneath the cursor.
  await closeMainWindow({ clearRootSearch: true, popToRootType: PopToRootType.Immediate });
  try {
    await run(BIN, ["click", "left"]);
  } catch (error) {
    await showHUD("Couldn't click at cursor");
  }
}
