-- ============================================================
-- Migration 0011: Database Optimization
-- ============================================================
-- 1. Composite indexes for query performance
-- 2. Normalize watched_folder_ids into own table
-- 3. Normalize provider-specific config into own table
-- ============================================================

-- 1a. Composite index for processed_messages getLatestForApplication/getLatestErrorForApplication
-- Query pattern: WHERE application_id = ? AND status = ? ORDER BY updated_at DESC LIMIT 1
CREATE INDEX IF NOT EXISTS idx_processed_messages_app_status_updated
  ON processed_messages(application_id, status, updated_at);

-- 1b. Composite index for provider_subscriptions listActiveRenewalCandidates
-- Query pattern: WHERE status = ? AND expires_at IS NOT NULL AND expires_at <= ?
--               AND (renewal_next_retry_at IS NULL OR renewal_next_retry_at <= ?)
--               ORDER BY expires_at ASC
CREATE INDEX IF NOT EXISTS idx_provider_subscriptions_renewal
  ON provider_subscriptions(status, expires_at, renewal_next_retry_at);

-- 1c. Composite index for application_context_documents user listing queries
-- Query pattern: WHERE user_email = ? [AND application_id = ?] [AND status = ?]
--               ORDER BY updated_at DESC, created_at DESC
CREATE INDEX IF NOT EXISTS idx_application_context_documents_user_sort
  ON application_context_documents(user_email, updated_at, created_at);

-- 1d. Composite index for oauth2_authorization_sessions getActive
-- Query pattern: WHERE application_id = ? AND state_hash = ? AND expires_at > ? AND consumed_at IS NULL
CREATE INDEX IF NOT EXISTS idx_oauth2_sessions_app_state
  ON oauth2_authorization_sessions(application_id, state_hash);

-- ============================================================
-- 2. Normalize watched_folder_ids into application_watched_folders
-- ============================================================

CREATE TABLE IF NOT EXISTS application_watched_folders (
    application_id TEXT NOT NULL,
    folder_path TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (application_id, folder_path),
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE
);

INSERT OR IGNORE INTO application_watched_folders (application_id, folder_path, created_at)
SELECT
    ca.application_id,
    JSON_EACH.value AS folder_path,
    ca.created_at
FROM connected_applications ca,
JSON_EACH(ca.watched_folder_ids)
WHERE ca.watched_folder_ids IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_application_watched_folders_application
  ON application_watched_folders(application_id);

ALTER TABLE connected_applications DROP COLUMN watched_folder_ids;

-- ============================================================
-- 3. Normalize provider-specific config into provider_application_configs
-- ============================================================

CREATE TABLE IF NOT EXISTS provider_application_configs (
    application_id TEXT NOT NULL,
    config_key TEXT NOT NULL,
    config_value TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (application_id, config_key),
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE
);

INSERT OR IGNORE INTO provider_application_configs (application_id, config_key, config_value, created_at, updated_at)
SELECT application_id, 'gmail_pubsub_topic_name', gmail_pubsub_topic_name, created_at, updated_at
FROM connected_applications
WHERE gmail_pubsub_topic_name IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_provider_application_configs_app
  ON provider_application_configs(application_id);

ALTER TABLE connected_applications DROP COLUMN gmail_pubsub_topic_name;
