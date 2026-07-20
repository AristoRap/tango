import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import * as vscode from "vscode";
import { LanguageClient } from "vscode-languageclient/node";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let client;

function resolveServerPath() {
  const configured = vscode.workspace
    .getConfiguration("tango")
    .get("server.path");

  if (configured && configured.length > 0) {
    return configured;
  }

  const roots = [__dirname];
  try {
    roots.push(fs.realpathSync(__dirname));
  } catch {}

  for (const root of roots) {
    const dev = path.resolve(root, "..", "..", "bin", "tango");
    if (fs.existsSync(dev)) {
      return dev;
    }
  }

  return "tango";
}

export function activate(context) {
  const command = resolveServerPath();
  const traceOutputChannel = vscode.window.createOutputChannel(
    "Tango LSP Trace",
    { log: true },
  );
  context.subscriptions.push(traceOutputChannel);

  const serverOptions = {
    command,
    args: ["lsp"],
  };

  const clientOptions = {
    documentSelector: [{ scheme: "file", language: "tango" }],
    outputChannelName: "Tango",
    traceOutputChannel,
  };

  client = new LanguageClient(
    "tango",
    "Tango Language Server",
    serverOptions,
    clientOptions,
  );

  client.start();
  context.subscriptions.push({ dispose: () => client && client.stop() });
}

export function deactivate() {
  return client ? client.stop() : undefined;
}
