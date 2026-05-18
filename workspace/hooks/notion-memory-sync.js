import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const TOTAL_ATTEMPTS = 2;
const SYNC_SCRIPT = "agents/einstein/scripts/sync-notion-memory.sh";
const MEMORY_FILE = "agents/einstein/MEMORY.md";

function assertGatewayStartup(event) {
  return event?.type === "gateway" && event?.action === "startup";
}

function syncNotionMemory(workspaceDir) {
  const scriptPath = path.join(workspaceDir, SYNC_SCRIPT);
  const memoryPath = path.join(workspaceDir, MEMORY_FILE);

  execFileSync("/bin/bash", [scriptPath], {
    cwd: workspaceDir,
    encoding: "utf8",
    stdio: "pipe"
  });

  const stats = fs.statSync(memoryPath);
  if (!stats.isFile() || stats.size <= 0) {
    throw new Error(`invalid MEMORY.md after sync: ${memoryPath}`);
  }
}

export default async function notionMemorySyncHook(event) {
  if (!assertGatewayStartup(event)) return;

  const workspaceDir = event?.context?.workspaceDir;
  if (typeof workspaceDir !== "string" || workspaceDir.trim() === "") {
    throw new Error("gateway:startup hook missing context.workspaceDir");
  }

  let lastError = null;

  for (let attempt = 1; attempt <= TOTAL_ATTEMPTS; attempt += 1) {
    try {
      syncNotionMemory(workspaceDir);
      return;
    } catch (error) {
      lastError = error;
    }
  }

  if (lastError instanceof Error) throw lastError;
  throw new Error(String(lastError));
}
