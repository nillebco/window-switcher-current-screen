import { closeMainWindow, environment, showHUD } from "@raycast/api";
import { execFile } from "child_process";
import { join } from "path";
import { promisify } from "util";

const run = promisify(execFile);
const BIN = join(environment.assetsPath, "cursor-screen");

export default async function FocusNextScreen() {
  await closeMainWindow();
  try {
    await run(BIN, ["next"]);
  } catch (error) {
    await showHUD("Couldn't move cursor to next screen");
  }
}
