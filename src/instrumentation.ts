export async function register() {
  // Only run on the server (not edge runtime)
  if (process.env.NEXT_RUNTIME === "nodejs") {
    if (process.env.HEALTH_SYNC_ENABLED === "0") {
      console.log("[Sync] Disabled by HEALTH_SYNC_ENABLED=0");
      return;
    }

    const { startUDPBroadcast } = await import(
      "./server/services/udp-broadcast"
    );
    const { getServerId } = await import(
      "./server/services/sync/server-identity"
    );
    const { getDatabase } = await import("./server/db/sqlite");
    const { startSyncScheduler } = await import(
      "./server/services/sync/sync-scheduler"
    );

    const port = Number(
      process.env.HEALTH_SERVER_PORT ?? process.env.PORT ?? 3000
    );

    // Ensure DB is initialized (runs migrations including 010_sync_system)
    getDatabase();

    const isUnroutableHost = (host: string | null | undefined): boolean => {
      if (!host) return true;
      const normalized = host.trim().toLowerCase();
      return (
        normalized === "0.0.0.0" ||
        normalized === "::" ||
        normalized === "::1" ||
        normalized === "127.0.0.1" ||
        normalized === "localhost"
      );
    };

    startUDPBroadcast({
      httpPort: port,
      getServerId: () => getServerId(),
      onPeerDiscovered: (serverId, name, ip, peerPort) => {
        try {
          if (isUnroutableHost(ip)) {
            return;
          }
          const db = getDatabase();
          const url = `http://${ip}:${peerPort}/`;
          const now = new Date().toISOString();

          const existing = db
            .prepare("SELECT server_id FROM sync_peer WHERE server_id = ?")
            .get(serverId);

          if (existing) {
            db.prepare(
              "UPDATE sync_peer SET name = ?, url = ?, last_seen_at = ? WHERE server_id = ?"
            ).run(name, url, now, serverId);
          } else {
            db.prepare(
              "INSERT INTO sync_peer (server_id, name, url, last_seen_at, created_at) VALUES (?, ?, ?, ?, ?)"
            ).run(serverId, name, url, now, now);
            console.log(`[UDP Discovery] New peer discovered: ${name} (${url})`);
          }
        } catch {
          // DB not ready — ignore
        }
      },
    });

    startSyncScheduler();
  }
}
