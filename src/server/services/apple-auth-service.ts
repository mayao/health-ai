import { createPublicKey, verify as verifySignature, type JsonWebKey } from "node:crypto";

import { getAppEnv } from "../config/env";

interface AppleTokenHeader {
  alg?: string;
  kid?: string;
}

interface AppleTokenPayload {
  iss?: string;
  aud?: string | string[];
  exp?: number;
  iat?: number;
  sub?: string;
  email?: string;
  email_verified?: boolean | string;
  nonce_supported?: boolean;
  is_private_email?: boolean | string;
}

interface AppleJWKSKey {
  kty: "RSA";
  kid: string;
  use?: string;
  alg?: string;
  n: string;
  e: string;
}

interface AppleJWKSResponse {
  keys: AppleJWKSKey[];
}

export interface VerifiedAppleIdentity {
  subject: string;
  email: string | null;
  emailVerified: boolean;
  rawClaims: AppleTokenPayload;
}

export interface AppleTokenVerificationOptions {
  acceptedAudiences?: string[];
  fetcher?: typeof fetch;
}

export type AppleIdentityErrorKind =
  | "invalid_token_format"
  | "invalid_algorithm"
  | "invalid_issuer"
  | "invalid_audience"
  | "missing_subject"
  | "expired_token"
  | "missing_key"
  | "invalid_signature"
  | "apple_keys_timeout"
  | "apple_keys_unavailable";

export interface AppleIdentityErrorMetadata {
  kid?: string;
  acceptedAudiences?: string[];
  tokenAudiences?: string[];
  cacheHit?: boolean;
  usedStaleCache?: boolean;
  upstreamStatus?: number;
}

export class AppleIdentityError extends Error {
  readonly kind: AppleIdentityErrorKind;
  readonly status: number;
  readonly retryable: boolean;
  readonly metadata: AppleIdentityErrorMetadata;

  constructor(
    kind: AppleIdentityErrorKind,
    message: string,
    options: {
      status: number;
      retryable: boolean;
      metadata?: AppleIdentityErrorMetadata;
    }
  ) {
    super(message);
    this.name = "AppleIdentityError";
    this.kind = kind;
    this.status = options.status;
    this.retryable = options.retryable;
    this.metadata = options.metadata ?? {};
  }

  withMetadata(extra: AppleIdentityErrorMetadata): AppleIdentityError {
    return new AppleIdentityError(this.kind, this.message, {
      status: this.status,
      retryable: this.retryable,
      metadata: {
        ...this.metadata,
        ...extra
      }
    });
  }
}

const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEY_CACHE_TTL_MS = 10 * 60 * 1000;
const APPLE_FETCH_TIMEOUT_MS = 5_000;

let cachedKeys:
  | {
      fetchedAt: number;
      keys: AppleJWKSKey[];
    }
  | undefined;

function decodeJWTPart<T>(part: string): T {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as T;
}

function resolveAcceptedAudiences(explicit?: string[]): string[] {
  if (explicit && explicit.length > 0) {
    return explicit;
  }

  const env = getAppEnv();
  return [env.HEALTH_APPLE_CLIENT_ID ?? "com.xihe.healthai"];
}

function isCachedKeysFresh(): boolean {
  return Boolean(cachedKeys && Date.now() - cachedKeys.fetchedAt < APPLE_KEY_CACHE_TTL_MS);
}

function findCachedKey(kid: string, allowStale: boolean): AppleJWKSKey | undefined {
  if (!cachedKeys) {
    return undefined;
  }

  if (!allowStale && !isCachedKeysFresh()) {
    return undefined;
  }

  return cachedKeys.keys.find((key) => key.kid === kid);
}

async function requestAppleKeys(fetcher: typeof fetch = fetch): Promise<AppleJWKSKey[]> {
  let response: Response | null = null;
  let lastError: unknown;
  const maxAttempts = 2;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      response = await fetcher(APPLE_KEYS_URL, {
        headers: {
          Accept: "application/json"
        },
        signal: AbortSignal.timeout(APPLE_FETCH_TIMEOUT_MS)
      });
      break;
    } catch (error) {
      lastError = error;
      if (attempt < maxAttempts) {
        await new Promise((resolve) => setTimeout(resolve, 250));
      }
    }
  }

  if (!response) {
    const errorName = lastError instanceof Error ? lastError.name : "";
    if (errorName === "TimeoutError" || errorName === "AbortError") {
      throw new AppleIdentityError(
        "apple_keys_timeout",
        "获取 Apple 公钥超时",
        {
          status: 503,
          retryable: true
        }
      );
    }

    throw new AppleIdentityError(
      "apple_keys_unavailable",
      "无法连接 Apple 公钥服务",
      {
        status: 503,
        retryable: true
      }
    );
  }

  if (!response.ok) {
    throw new AppleIdentityError(
      "apple_keys_unavailable",
      `无法获取 Apple 公钥（${response.status}）`,
      {
        status: 503,
        retryable: true,
        metadata: {
          upstreamStatus: response.status
        }
      }
    );
  }

  let payload: AppleJWKSResponse;
  try {
    payload = (await response.json()) as AppleJWKSResponse;
  } catch {
    throw new AppleIdentityError(
      "apple_keys_unavailable",
      "Apple 公钥响应解析失败",
      {
        status: 503,
        retryable: true
      }
    );
  }

  if (!payload.keys?.length) {
    throw new AppleIdentityError(
      "apple_keys_unavailable",
      "Apple 公钥列表为空",
      {
        status: 503,
        retryable: true
      }
    );
  }

  cachedKeys = {
    fetchedAt: Date.now(),
    keys: payload.keys
  };

  return payload.keys;
}

function buildInvalidTokenError(
  kind: AppleIdentityErrorKind,
  message: string,
  metadata: AppleIdentityErrorMetadata = {}
): AppleIdentityError {
  return new AppleIdentityError(kind, message, {
    status: 401,
    retryable: false,
    metadata
  });
}

function isTruthyClaim(value: boolean | string | undefined): boolean {
  return value === true || value === "true";
}

export function clearAppleKeyCacheForTests(): void {
  cachedKeys = undefined;
}

export async function verifyAppleIdentityToken(
  identityToken: string,
  options: AppleTokenVerificationOptions = {}
): Promise<VerifiedAppleIdentity> {
  const parts = identityToken.split(".");
  if (parts.length !== 3) {
    throw buildInvalidTokenError("invalid_token_format", "Apple 身份令牌格式无效");
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = decodeJWTPart<AppleTokenHeader>(encodedHeader);
  const payload = decodeJWTPart<AppleTokenPayload>(encodedPayload);
  const acceptedAudiences = resolveAcceptedAudiences(options.acceptedAudiences);
  const tokenAudiences = (Array.isArray(payload.aud) ? payload.aud : [payload.aud]).filter(
    (value): value is string => typeof value === "string" && value.length > 0
  );
  const baseMetadata: AppleIdentityErrorMetadata = {
    kid: header.kid,
    acceptedAudiences,
    tokenAudiences
  };

  if (header.alg !== "RS256" || !header.kid) {
    throw buildInvalidTokenError("invalid_algorithm", "Apple 身份令牌算法无效", baseMetadata);
  }

  if (payload.iss !== APPLE_ISSUER) {
    throw buildInvalidTokenError("invalid_issuer", "Apple 身份令牌签发方无效", baseMetadata);
  }

  if (!tokenAudiences.some((audience) => acceptedAudiences.includes(audience))) {
    throw buildInvalidTokenError("invalid_audience", "Apple 身份令牌 audience 不匹配", baseMetadata);
  }

  if (!payload.sub) {
    throw buildInvalidTokenError("missing_subject", "Apple 身份令牌缺少用户标识", baseMetadata);
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (!payload.exp || payload.exp <= nowSeconds) {
    throw buildInvalidTokenError("expired_token", "Apple 身份令牌已过期", baseMetadata);
  }

  let matchingKey = findCachedKey(header.kid, false);
  let cacheHit = Boolean(matchingKey);
  let usedStaleCache = false;

  if (!matchingKey) {
    try {
      const keys = await requestAppleKeys(options.fetcher);
      matchingKey = keys.find((key) => key.kid === header.kid);
    } catch (error) {
      const staleKey = findCachedKey(header.kid, true);
      if (staleKey) {
        matchingKey = staleKey;
        cacheHit = true;
        usedStaleCache = true;
      } else if (error instanceof AppleIdentityError) {
        throw error.withMetadata({
          ...baseMetadata,
          cacheHit: false,
          usedStaleCache: false
        });
      } else {
        throw error;
      }
    }
  }

  if (!matchingKey) {
    throw buildInvalidTokenError("missing_key", "未找到匹配的 Apple 公钥", {
      ...baseMetadata,
      cacheHit,
      usedStaleCache
    });
  }

  const publicKey = createPublicKey({
    key: {
      kty: matchingKey.kty,
      kid: matchingKey.kid,
      use: matchingKey.use,
      alg: matchingKey.alg ?? "RS256",
      n: matchingKey.n,
      e: matchingKey.e,
      ext: true
    } as JsonWebKey,
    format: "jwk"
  });

  const signatureValid = verifySignature(
    "RSA-SHA256",
    Buffer.from(`${encodedHeader}.${encodedPayload}`, "utf8"),
    publicKey,
    Buffer.from(encodedSignature, "base64url")
  );

  if (!signatureValid) {
    throw buildInvalidTokenError("invalid_signature", "Apple 身份令牌签名校验失败", {
      ...baseMetadata,
      cacheHit,
      usedStaleCache
    });
  }

  return {
    subject: payload.sub,
    email: payload.email ?? null,
    emailVerified: isTruthyClaim(payload.email_verified),
    rawClaims: payload
  };
}
