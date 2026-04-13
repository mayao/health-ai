import os from "node:os";
import { NextResponse } from "next/server";
import { headers } from "next/headers";
import { getServerId } from "../../../server/services/sync/server-identity";

export const dynamic = "force-dynamic";

function getLocalIPv4(): string {
  const interfaces = os.networkInterfaces();
  const preferredPrefixes = ["en", "eth"];

  for (const prefix of preferredPrefixes) {
    for (const name of Object.keys(interfaces)) {
      if (!name.startsWith(prefix)) continue;
      for (const iface of interfaces[name] ?? []) {
        if (iface.family === "IPv4" && !iface.internal) {
          return iface.address;
        }
      }
    }
  }

  for (const name of Object.keys(interfaces)) {
    if (name.startsWith("utun") || name.startsWith("lo") || name.startsWith("bridge")) continue;
    for (const iface of interfaces[name] ?? []) {
      if (iface.family === "IPv4" && !iface.internal) {
        return iface.address;
      }
    }
  }
  return "0.0.0.0";
}

export async function GET() {
  const headerStore = await headers();
  const protocol = headerStore.get("x-forwarded-proto") ?? "http";
  const host = headerStore.get("x-forwarded-host") ?? headerStore.get("host") ?? `${getLocalIPv4()}:${Number(process.env.PORT ?? 3000)}`;
  const baseURL = `${protocol}://${host}/`;
  const serverId = getServerId();

  return NextResponse.json({
    service: "vital-command",
    name: os.hostname(),
    ip: getLocalIPv4(),
    port: Number(process.env.PORT ?? 3000),
    scheme: protocol,
    baseURL,
    serverId,
    server_id: serverId,
    version: "1.0.0",
  });
}
