import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import test from "node:test";

import {
  AppleIdentityError,
  clearAppleKeyCacheForTests,
  verifyAppleIdentityToken
} from "./apple-auth-service";

function base64url(value: object | string): string {
  const raw = typeof value === "string" ? value : JSON.stringify(value);
  return Buffer.from(raw, "utf8").toString("base64url");
}

function buildFakeToken(overrides: {
  kid?: string;
  aud?: string;
  iss?: string;
  exp?: number;
  sub?: string;
} = {}): string {
  const header = {
    alg: "RS256",
    kid: overrides.kid ?? "apple-key-1"
  };
  const payload = {
    iss: overrides.iss ?? "https://appleid.apple.com",
    aud: overrides.aud ?? "com.xihe.healthai",
    exp: overrides.exp ?? Math.floor(Date.now() / 1000) + 3600,
    sub: overrides.sub ?? "apple-user-1"
  };

  return `${base64url(header)}.${base64url(payload)}.${base64url("invalid-signature")}`;
}

test.beforeEach(() => {
  clearAppleKeyCacheForTests();
});

test("verifyAppleIdentityToken rejects invalid audience before requesting Apple keys", async () => {
  let fetchCalled = false;
  const token = buildFakeToken({ aud: "com.example.other" });

  await assert.rejects(
    verifyAppleIdentityToken(token, {
      acceptedAudiences: ["com.xihe.healthai"],
      fetcher: async (_input: string | URL | Request, _init?: RequestInit) => {
        fetchCalled = true;
        return new Response(JSON.stringify({ keys: [] }), { status: 200 });
      }
    }),
    (error: unknown) => {
      assert.ok(error instanceof AppleIdentityError);
      assert.equal(error.kind, "invalid_audience");
      assert.equal(error.status, 401);
      assert.equal(fetchCalled, false);
      return true;
    }
  );
});

test("verifyAppleIdentityToken returns retryable 503 when Apple keys are unavailable", async () => {
  const token = buildFakeToken();

  await assert.rejects(
    verifyAppleIdentityToken(token, {
      acceptedAudiences: ["com.xihe.healthai"],
      fetcher: async (_input: string | URL | Request, _init?: RequestInit) => {
        throw new Error("network down");
      }
    }),
    (error: unknown) => {
      assert.ok(error instanceof AppleIdentityError);
      assert.equal(error.kind, "apple_keys_unavailable");
      assert.equal(error.status, 503);
      assert.equal(error.retryable, true);
      return true;
    }
  );
});

test("verifyAppleIdentityToken reuses stale cached keys when refresh fails", async () => {
  const { publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const jwk = publicKey.export({ format: "jwk" }) as { n?: string; e?: string };
  const token = buildFakeToken({ kid: "kid-stale" });

  const fetchAppleKeys: typeof fetch = async (_input, _init) =>
    new Response(
      JSON.stringify({
        keys: [
          {
            kty: "RSA",
            kid: "kid-stale",
            alg: "RS256",
            n: jwk.n,
            e: jwk.e
          }
        ]
      }),
      { status: 200 }
    );

  await assert.rejects(
    verifyAppleIdentityToken(token, {
      acceptedAudiences: ["com.xihe.healthai"],
      fetcher: fetchAppleKeys
    }),
    (error: unknown) => {
      assert.ok(error instanceof AppleIdentityError);
      assert.equal(error.kind, "invalid_signature");
      assert.equal(error.status, 401);
      return true;
    }
  );

  const realNow = Date.now;
  Date.now = () => realNow() + 11 * 60 * 1000;

  try {
    await assert.rejects(
      verifyAppleIdentityToken(token, {
        acceptedAudiences: ["com.xihe.healthai"],
        fetcher: async (_input: string | URL | Request, _init?: RequestInit) => {
          throw new Error("apple jwks offline");
        }
      }),
      (error: unknown) => {
        assert.ok(error instanceof AppleIdentityError);
        assert.equal(error.kind, "invalid_signature");
        assert.equal(error.status, 401);
        assert.equal(error.metadata.cacheHit, true);
        assert.equal(error.metadata.usedStaleCache, true);
        return true;
      }
    );
  } finally {
    Date.now = realNow;
  }
});
