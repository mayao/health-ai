import { getDatabase } from "../db/sqlite";
import { getServerId } from "../services/sync/server-identity";

/**
 * Validate that a sync request comes from a known peer server.
 * Checks the X-Sync-Server-Id header against the sync_peer table.
 * Returns the peer server_id if valid, null otherwise.
 */
export function validateSyncPeer(request: Request): string | null {
  const serverId = request.headers.get("X-Sync-Server-Id");
  if (!serverId) return null;

  try {
    const database = getDatabase();
    const localServerId = getServerId(database);
    if (serverId === localServerId) {
      return null;
    }

    const peer = database
      .prepare("SELECT server_id FROM sync_peer WHERE server_id = ?")
      .get(serverId) as { server_id: string } | undefined;

    if (peer?.server_id) {
      return peer.server_id;
    }

    const peerUrl = request.headers.get("X-Sync-Server-Url");
    if (!peerUrl) {
      return null;
    }

    const peerName = request.headers.get("X-Sync-Server-Name") ?? peerUrl;
    const now = new Date().toISOString();

    database
      .prepare(
        "INSERT INTO sync_peer (server_id, name, url, last_seen_at, created_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(server_id) DO UPDATE SET name = excluded.name, url = excluded.url, last_seen_at = excluded.last_seen_at"
      )
      .run(serverId, peerName, peerUrl, now, now);

    return serverId;
  } catch {
    return null;
  }
}

/**
 * Validate sync request and return 401 response if invalid.
 * For use in sync API route handlers.
 */
export function requireSyncPeer(request: Request): { serverId: string } | Response {
  const serverId = validateSyncPeer(request);
  if (!serverId) {
    return new Response(
      JSON.stringify({ error: "Unknown sync peer. X-Sync-Server-Id header required from a registered peer." }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }
  return { serverId };
}
