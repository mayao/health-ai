import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { canUserSwitch, listAllUsers } from "../../../../server/services/auth-service";
import { getDatabase } from "../../../../server/db/sqlite";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const currentUserId = getAuthenticatedUserId(request);
    const db = getDatabase();
    const canSwitchUser = canUserSwitch(currentUserId, db);
    const users = canSwitchUser ? listAllUsers(db) : [];
    return jsonOk({ users, currentUserId, canSwitchUser });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/auth/users", method: "GET" } });
    }
    return jsonSafeError({ message: "获取用户列表失败", status: 500, error, context: { route: "/api/auth/users", method: "GET" } });
  }
}
