CREATE TABLE IF NOT EXISTS document_insight_cache (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  document_type TEXT NOT NULL,
  source_fingerprint TEXT NOT NULL,
  result_json TEXT NOT NULL,
  summary_text TEXT,
  generated_at TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_document_insight_cache_user_type
  ON document_insight_cache (user_id, document_type);
