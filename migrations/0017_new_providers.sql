-- Migration 0017: Add support for new email providers (Fastmail/JMAP, Yahoo Mail, Custom IMAP, Apple iCloud)
-- Updates provider_id CHECK constraints in all relevant tables, adds imap-password connection method,
-- and adds imap_cursor column to provider_subscriptions for polling-based providers.
--
-- SQLite does not support ALTER COLUMN or DROP CONSTRAINT. We must rebuild each table whose CHECK
-- constraints change. Strategy: backup child table data to temp tables, drop all FK-referencing
-- tables, rebuild connected_applications, then recreate child tables from backups.

-- ============================================================
-- Phase A: Rebuild connected_applications with updated CHECKs
-- ============================================================

CREATE TABLE connected_applications_new (
    application_id TEXT PRIMARY KEY,
    user_email TEXT NOT NULL,
    provider_email TEXT,
    display_name TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    connection_method TEXT NOT NULL,
    encrypted_credentials TEXT NOT NULL,
    credentials_iv TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    context_indexing_enabled INTEGER NOT NULL DEFAULT 1,
    max_context_documents INTEGER,
    last_error_acknowledged_at INTEGER,
    context_last_error_acknowledged_at INTEGER,
    FOREIGN KEY (user_email) REFERENCES users(email) ON DELETE CASCADE,
    CHECK (provider_id IN ('google-gmail', 'microsoft-outlook', 'fastmail-jmap', 'yahoo-mail', 'custom-imap', 'apple-icloud')),
    CHECK (connection_method IN ('oauth2', 'imap-password')),
    CHECK (status IN ('draft', 'connected', 'error'))
);
INSERT INTO connected_applications_new
    (application_id, user_email, provider_email, display_name, provider_id, connection_method,
     encrypted_credentials, credentials_iv, status, created_at, updated_at,
     context_indexing_enabled, max_context_documents, last_error_acknowledged_at,
     context_last_error_acknowledged_at)
SELECT
    application_id, user_email, provider_email, display_name, provider_id, connection_method,
    encrypted_credentials, credentials_iv, status, created_at, updated_at,
    context_indexing_enabled, max_context_documents, last_error_acknowledged_at,
    context_last_error_acknowledged_at
FROM connected_applications;

-- ============================================================
-- Phase B: Backup all child table data to constraint-free temp tables
--          (column order matches between backup and restore via explicit lists)
-- ============================================================

CREATE TABLE bak_oauth2_authorization_sessions AS
    SELECT session_id, application_id, state_hash, code_verifier, redirect_uri,
           created_at, expires_at, consumed_at
    FROM oauth2_authorization_sessions;

CREATE TABLE bak_application_context_documents AS
    SELECT context_document_id, application_id, user_email,
           source_type, source_provider_id, source_document_id, source_thread_id,
           vector_namespace, vector_id,
           status, indexed_at, deleted_at, last_error, created_at, updated_at,
           source_document_fingerprint, source_thread_fingerprint,
           title_fingerprint, sender_fingerprint, content_fingerprint,
           indexed_text_chars
    FROM application_context_documents;

CREATE TABLE bak_context_audit_logs AS
    SELECT id, context_document_id, application_id, user_email, source_document_id,
           event_type, event_label, event_data, severity, created_at
    FROM context_audit_logs;

CREATE TABLE bak_application_context_deletion_runs AS
    SELECT deletion_run_id, application_id, user_email, vector_namespace,
           requested_vector_count, deleted_vector_count, mutation_ids,
           status, error_message, created_at, updated_at
    FROM application_context_deletion_runs;

CREATE TABLE bak_oauth2_access_token_refresh_status AS
    SELECT application_id, access_token_expires_at, last_refresh_started_at,
           last_refresh_succeeded_at, last_refresh_failed_at, last_error,
           created_at, updated_at
    FROM oauth2_access_token_refresh_status;

CREATE TABLE bak_application_watched_folders AS
    SELECT application_id, folder_path, created_at, folder_name
    FROM application_watched_folders;

CREATE TABLE bak_provider_application_configs AS
    SELECT application_id, config_key, config_value, created_at, updated_at
    FROM provider_application_configs;

CREATE TABLE bak_application_integrations AS
    SELECT integration_id, application_id, integration_type, name,
           encrypted_webhook_url, webhook_url_iv, webhook_url_prefix,
           enabled, created_at, updated_at
    FROM application_integrations;

CREATE TABLE bak_email_action_executions AS
    SELECT execution_id, action_id, attempt, triggered_by, status,
           provider_operation_id, request_user_agent_hash, error_message,
           created_at, completed_at
    FROM email_action_executions;

CREATE TABLE bak_email_summary_actions AS
    SELECT action_id, processed_message_id, application_id, user_email, provider_id,
           provider_message_id, provider_thread_id, action_type, status, risk_level,
           token_hash, encrypted_payload, payload_iv, payload_salt,
           encrypted_result, result_iv, result_salt, error_message,
           expires_at, executed_at, created_at, updated_at
    FROM email_summary_actions;

CREATE TABLE bak_provider_subscriptions AS
    SELECT subscription_id, application_id, provider_id, external_subscription_id,
           webhook_secret_hash, client_state_hash, gmail_history_id, resource,
           status, expires_at, last_notification_at, last_renewed_at, last_error,
           renewal_retry_count, renewal_next_retry_at, created_at, updated_at
    FROM provider_subscriptions;

CREATE TABLE bak_processed_messages AS
    SELECT processed_message_id, application_id, provider_id, provider_message_id,
           provider_thread_id, status, summary_sent_at, error_message,
           created_at, updated_at, provider_stable_message_fingerprint
    FROM processed_messages;

-- ============================================================
-- Phase C: DROP old child tables in FK-safe order
--          (children before parents, innermost references first)
-- ============================================================

-- context_audit_logs references application_context_documents (dropped below)
DROP TABLE context_audit_logs;
-- email_action_executions references email_summary_actions (dropped below)
DROP TABLE email_action_executions;
-- email_summary_actions references connected_applications + processed_messages
DROP TABLE email_summary_actions;
-- application_context_documents references connected_applications
DROP TABLE application_context_documents;
-- Remaining leaf children of connected_applications (no reverse FK)
DROP TABLE application_context_deletion_runs;
DROP TABLE oauth2_authorization_sessions;
DROP TABLE oauth2_access_token_refresh_status;
DROP TABLE application_watched_folders;
DROP TABLE provider_application_configs;
DROP TABLE application_integrations;
DROP TABLE provider_subscriptions;
DROP TABLE processed_messages;

-- ============================================================
-- Phase D: DROP connected_applications
--          (no remaining table references it)
-- ============================================================

DROP TABLE connected_applications;

-- ============================================================
-- Phase E: Rename connected_applications_new to final name
-- ============================================================

ALTER TABLE connected_applications_new RENAME TO connected_applications;

-- ============================================================
-- Phase F: Recreate all child tables with final schemas
--          and restore data from backups
-- ============================================================

-- 1. oauth2_authorization_sessions (no schema change)
CREATE TABLE oauth2_authorization_sessions (
    session_id TEXT PRIMARY KEY,
    application_id TEXT NOT NULL,
    state_hash TEXT NOT NULL UNIQUE,
    code_verifier TEXT NOT NULL,
    redirect_uri TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    consumed_at INTEGER,
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE
);
INSERT INTO oauth2_authorization_sessions
    (session_id, application_id, state_hash, code_verifier, redirect_uri, created_at, expires_at, consumed_at)
SELECT
    session_id, application_id, state_hash, code_verifier, redirect_uri, created_at, expires_at, consumed_at
FROM bak_oauth2_authorization_sessions;
DROP TABLE bak_oauth2_authorization_sessions;

-- 2. application_context_documents (update source_provider_id CHECK)
CREATE TABLE application_context_documents (
    context_document_id TEXT PRIMARY KEY,
    application_id TEXT NOT NULL,
    user_email TEXT NOT NULL,
    source_type TEXT NOT NULL,
    source_provider_id TEXT NOT NULL,
    source_document_id TEXT NOT NULL,
    source_thread_id TEXT,
    vector_namespace TEXT NOT NULL,
    vector_id TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL,
    indexed_at INTEGER,
    deleted_at INTEGER,
    last_error TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    source_document_fingerprint TEXT,
    source_thread_fingerprint TEXT,
    title_fingerprint TEXT,
    sender_fingerprint TEXT,
    content_fingerprint TEXT,
    indexed_text_chars INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE,
    FOREIGN KEY (user_email) REFERENCES users(email) ON DELETE CASCADE,
    UNIQUE (application_id, source_type, source_document_id),
    CHECK (source_provider_id IN ('google-gmail', 'microsoft-outlook', 'fastmail-jmap', 'yahoo-mail', 'custom-imap', 'apple-icloud')),
    CHECK (status IN ('active', 'deleted', 'error'))
);
INSERT INTO application_context_documents
    (context_document_id, application_id, user_email, source_type, source_provider_id,
     source_document_id, source_thread_id, vector_namespace, vector_id,
     status, indexed_at, deleted_at, last_error, created_at, updated_at,
     source_document_fingerprint, source_thread_fingerprint, title_fingerprint,
     sender_fingerprint, content_fingerprint, indexed_text_chars)
SELECT
    context_document_id, application_id, user_email, source_type, source_provider_id,
    source_document_id, source_thread_id, vector_namespace, vector_id,
    status, indexed_at, deleted_at, last_error, created_at, updated_at,
    source_document_fingerprint, source_thread_fingerprint, title_fingerprint,
    sender_fingerprint, content_fingerprint, indexed_text_chars
FROM bak_application_context_documents;
DROP TABLE bak_application_context_documents;

-- 3. context_audit_logs (no schema change)
CREATE TABLE context_audit_logs (
    id TEXT PRIMARY KEY,
    context_document_id TEXT NOT NULL,
    application_id TEXT NOT NULL,
    user_email TEXT NOT NULL,
    source_document_id TEXT,
    event_type TEXT NOT NULL,
    event_label TEXT,
    event_data TEXT,
    severity TEXT NOT NULL DEFAULT 'info',
    created_at INTEGER NOT NULL,
    FOREIGN KEY (context_document_id) REFERENCES application_context_documents(context_document_id)
);
INSERT INTO context_audit_logs
    (id, context_document_id, application_id, user_email, source_document_id,
     event_type, event_label, event_data, severity, created_at)
SELECT
    id, context_document_id, application_id, user_email, source_document_id,
    event_type, event_label, event_data, severity, created_at
FROM bak_context_audit_logs;
DROP TABLE bak_context_audit_logs;

-- 4. application_context_deletion_runs (no schema change)
CREATE TABLE application_context_deletion_runs (
    deletion_run_id TEXT PRIMARY KEY,
    application_id TEXT NOT NULL,
    user_email TEXT NOT NULL,
    vector_namespace TEXT NOT NULL,
    requested_vector_count INTEGER NOT NULL,
    deleted_vector_count INTEGER NOT NULL,
    mutation_ids TEXT,
    status TEXT NOT NULL,
    error_message TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE,
    FOREIGN KEY (user_email) REFERENCES users(email) ON DELETE CASCADE,
    CHECK (status IN ('accepted', 'error'))
);
INSERT INTO application_context_deletion_runs
    (deletion_run_id, application_id, user_email, vector_namespace,
     requested_vector_count, deleted_vector_count, mutation_ids,
     status, error_message, created_at, updated_at)
SELECT
    deletion_run_id, application_id, user_email, vector_namespace,
    requested_vector_count, deleted_vector_count, mutation_ids,
    status, error_message, created_at, updated_at
FROM bak_application_context_deletion_runs;
DROP TABLE bak_application_context_deletion_runs;

-- 5. oauth2_access_token_refresh_status (no schema change)
CREATE TABLE oauth2_access_token_refresh_status (
    application_id TEXT PRIMARY KEY,
    access_token_expires_at INTEGER,
    last_refresh_started_at INTEGER,
    last_refresh_succeeded_at INTEGER,
    last_refresh_failed_at INTEGER,
    last_error TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE
);
INSERT INTO oauth2_access_token_refresh_status
    (application_id, access_token_expires_at, last_refresh_started_at,
     last_refresh_succeeded_at, last_refresh_failed_at, last_error,
     created_at, updated_at)
SELECT
    application_id, access_token_expires_at, last_refresh_started_at,
    last_refresh_succeeded_at, last_refresh_failed_at, last_error,
    created_at, updated_at
FROM bak_oauth2_access_token_refresh_status;
DROP TABLE bak_oauth2_access_token_refresh_status;

-- 6. application_watched_folders (no schema change)
CREATE TABLE application_watched_folders (
    application_id TEXT NOT NULL,
    folder_path TEXT NOT NULL,
    folder_name TEXT,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (application_id, folder_path),
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE
);
INSERT INTO application_watched_folders
    (application_id, folder_path, folder_name, created_at)
SELECT
    application_id, folder_path, folder_name, created_at
FROM bak_application_watched_folders;
DROP TABLE bak_application_watched_folders;

-- 7. provider_application_configs (no schema change)
CREATE TABLE provider_application_configs (
    application_id TEXT NOT NULL,
    config_key TEXT NOT NULL,
    config_value TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (application_id, config_key),
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE
);
INSERT INTO provider_application_configs
    (application_id, config_key, config_value, created_at, updated_at)
SELECT
    application_id, config_key, config_value, created_at, updated_at
FROM bak_provider_application_configs;
DROP TABLE bak_provider_application_configs;

-- 8. application_integrations (no schema change)
CREATE TABLE application_integrations (
    integration_id        TEXT    NOT NULL PRIMARY KEY,
    application_id        TEXT    NOT NULL,
    integration_type      TEXT    NOT NULL,
    name                  TEXT    NOT NULL,
    encrypted_webhook_url TEXT    NOT NULL,
    webhook_url_iv        TEXT    NOT NULL,
    webhook_url_prefix    TEXT    NOT NULL DEFAULT '',
    enabled               INTEGER NOT NULL DEFAULT 1,
    created_at            INTEGER NOT NULL,
    updated_at            INTEGER NOT NULL,
    FOREIGN KEY (application_id)
        REFERENCES connected_applications(application_id) ON DELETE CASCADE
);
INSERT INTO application_integrations
    (integration_id, application_id, integration_type, name,
     encrypted_webhook_url, webhook_url_iv, webhook_url_prefix,
     enabled, created_at, updated_at)
SELECT
    integration_id, application_id, integration_type, name,
    encrypted_webhook_url, webhook_url_iv, webhook_url_prefix,
    enabled, created_at, updated_at
FROM bak_application_integrations;
DROP TABLE bak_application_integrations;

-- 9. processed_messages (update provider_id CHECK)
CREATE TABLE processed_messages (
    processed_message_id TEXT PRIMARY KEY,
    application_id TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    provider_message_id TEXT NOT NULL,
    provider_thread_id TEXT,
    status TEXT NOT NULL,
    summary_sent_at INTEGER,
    error_message TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    provider_stable_message_fingerprint TEXT,
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE,
    UNIQUE (application_id, provider_message_id),
    CHECK (provider_id IN ('google-gmail', 'microsoft-outlook', 'fastmail-jmap', 'yahoo-mail', 'custom-imap', 'apple-icloud')),
    CHECK (status IN ('processing', 'summarized', 'skipped', 'error'))
);
INSERT INTO processed_messages
    (processed_message_id, application_id, provider_id, provider_message_id,
     provider_thread_id, status, summary_sent_at, error_message,
     created_at, updated_at, provider_stable_message_fingerprint)
SELECT
    processed_message_id, application_id, provider_id, provider_message_id,
    provider_thread_id, status, summary_sent_at, error_message,
    created_at, updated_at, provider_stable_message_fingerprint
FROM bak_processed_messages;
DROP TABLE bak_processed_messages;

-- 10. email_summary_actions (update provider_id CHECK)
CREATE TABLE email_summary_actions (
    action_id TEXT PRIMARY KEY,
    processed_message_id TEXT NOT NULL,
    application_id TEXT NOT NULL,
    user_email TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    provider_message_id TEXT NOT NULL,
    provider_thread_id TEXT,
    action_type TEXT NOT NULL,
    status TEXT NOT NULL,
    risk_level TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    encrypted_payload TEXT NOT NULL,
    payload_iv TEXT NOT NULL,
    payload_salt TEXT NOT NULL,
    encrypted_result TEXT,
    result_iv TEXT,
    result_salt TEXT,
    error_message TEXT,
    expires_at INTEGER NOT NULL,
    executed_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (processed_message_id) REFERENCES processed_messages(processed_message_id) ON DELETE CASCADE,
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE,
    CHECK (provider_id IN ('google-gmail', 'microsoft-outlook', 'fastmail-jmap', 'yahoo-mail', 'custom-imap', 'apple-icloud')),
    CHECK (action_type IN ('calendar.add_event', 'email.draft_reply', 'external.open_link', 'manual.todo')),
    CHECK (status IN ('pending', 'executing', 'succeeded', 'failed', 'expired', 'cancelled')),
    CHECK (risk_level IN ('low', 'medium', 'high'))
);
INSERT INTO email_summary_actions
    (action_id, processed_message_id, application_id, user_email, provider_id,
     provider_message_id, provider_thread_id, action_type, status, risk_level,
     token_hash, encrypted_payload, payload_iv, payload_salt,
     encrypted_result, result_iv, result_salt, error_message,
     expires_at, executed_at, created_at, updated_at)
SELECT
    action_id, processed_message_id, application_id, user_email, provider_id,
    provider_message_id, provider_thread_id, action_type, status, risk_level,
    token_hash, encrypted_payload, payload_iv, payload_salt,
    encrypted_result, result_iv, result_salt, error_message,
    expires_at, executed_at, created_at, updated_at
FROM bak_email_summary_actions;
DROP TABLE bak_email_summary_actions;

-- 11. email_action_executions (no schema change)
CREATE TABLE email_action_executions (
    execution_id TEXT PRIMARY KEY,
    action_id TEXT NOT NULL,
    attempt INTEGER NOT NULL,
    triggered_by TEXT NOT NULL,
    status TEXT NOT NULL,
    provider_operation_id TEXT,
    request_user_agent_hash TEXT,
    error_message TEXT,
    created_at INTEGER NOT NULL,
    completed_at INTEGER,
    FOREIGN KEY (action_id) REFERENCES email_summary_actions(action_id) ON DELETE CASCADE,
    CHECK (triggered_by IN ('email_callback', 'web_ui', 'system_expiry')),
    CHECK (status IN ('pending', 'executing', 'succeeded', 'failed', 'expired', 'cancelled'))
);
INSERT INTO email_action_executions
    (execution_id, action_id, attempt, triggered_by, status,
     provider_operation_id, request_user_agent_hash, error_message,
     created_at, completed_at)
SELECT
    execution_id, action_id, attempt, triggered_by, status,
    provider_operation_id, request_user_agent_hash, error_message,
    created_at, completed_at
FROM bak_email_action_executions;
DROP TABLE bak_email_action_executions;

-- 12. provider_subscriptions (update provider_id CHECK + add imap_cursor column)
CREATE TABLE provider_subscriptions (
    subscription_id TEXT PRIMARY KEY,
    application_id TEXT NOT NULL UNIQUE,
    provider_id TEXT,
    external_subscription_id TEXT UNIQUE,
    webhook_secret_hash TEXT,
    client_state_hash TEXT,
    gmail_history_id TEXT,
    resource TEXT,
    status TEXT NOT NULL,
    expires_at INTEGER,
    last_notification_at INTEGER,
    last_renewed_at INTEGER,
    last_error TEXT,
    renewal_retry_count INTEGER NOT NULL DEFAULT 0,
    renewal_next_retry_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    imap_cursor TEXT,
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE,
    CHECK (provider_id IS NULL OR provider_id IN ('google-gmail', 'microsoft-outlook', 'fastmail-jmap', 'yahoo-mail', 'custom-imap', 'apple-icloud')),
    CHECK (status IN ('active', 'stopped', 'error'))
);
INSERT INTO provider_subscriptions
    (subscription_id, application_id, provider_id, external_subscription_id,
     webhook_secret_hash, client_state_hash, gmail_history_id, resource,
     status, expires_at, last_notification_at, last_renewed_at, last_error,
     renewal_retry_count, renewal_next_retry_at, created_at, updated_at)
SELECT
    subscription_id, application_id, provider_id, external_subscription_id,
    webhook_secret_hash, client_state_hash, gmail_history_id, resource,
    status, expires_at, last_notification_at, last_renewed_at, last_error,
    renewal_retry_count, renewal_next_retry_at, created_at, updated_at
FROM bak_provider_subscriptions;
-- imap_cursor defaults to NULL for existing rows
DROP TABLE bak_provider_subscriptions;

-- ============================================================
-- Phase G: Recreate all indexes
-- ============================================================

-- connected_applications
CREATE INDEX idx_connected_applications_user_email ON connected_applications(user_email);

-- oauth2_authorization_sessions
CREATE INDEX idx_oauth2_authorization_sessions_application_id ON oauth2_authorization_sessions(application_id);
CREATE INDEX idx_oauth2_authorization_sessions_expires_at ON oauth2_authorization_sessions(expires_at);
CREATE INDEX idx_oauth2_sessions_app_state
    ON oauth2_authorization_sessions(application_id, state_hash);

-- application_context_documents
CREATE INDEX idx_application_context_documents_application_id ON application_context_documents(application_id);
CREATE INDEX idx_application_context_documents_user_email ON application_context_documents(user_email);
CREATE INDEX idx_application_context_documents_status ON application_context_documents(status);
CREATE INDEX idx_application_context_documents_vector_id ON application_context_documents(vector_id);
CREATE INDEX idx_application_context_documents_application_created
    ON application_context_documents(application_id, created_at)
    WHERE status = 'active';
CREATE INDEX idx_application_context_documents_user_sort
    ON application_context_documents(user_email, updated_at, created_at);

-- context_audit_logs
CREATE INDEX idx_cal_ctx_doc ON context_audit_logs(context_document_id, created_at);

-- application_context_deletion_runs
CREATE INDEX idx_application_context_deletion_runs_application_id ON application_context_deletion_runs(application_id);
CREATE INDEX idx_application_context_deletion_runs_user_email ON application_context_deletion_runs(user_email);

-- oauth2_access_token_refresh_status
CREATE INDEX idx_oauth2_access_token_refresh_status_expires_at ON oauth2_access_token_refresh_status(access_token_expires_at);
CREATE INDEX idx_oauth2_access_token_refresh_status_updated_at ON oauth2_access_token_refresh_status(updated_at);

-- application_watched_folders
CREATE INDEX idx_application_watched_folders_application ON application_watched_folders(application_id);

-- provider_application_configs
CREATE INDEX idx_provider_application_configs_app ON provider_application_configs(application_id);

-- application_integrations
CREATE INDEX idx_application_integrations_app_id ON application_integrations(application_id);

-- email_action_executions
CREATE INDEX idx_email_action_executions_action ON email_action_executions(action_id, created_at);

-- email_summary_actions
CREATE INDEX idx_email_summary_actions_user_sort
    ON email_summary_actions(user_email, updated_at, created_at);
CREATE INDEX idx_email_summary_actions_application_status
    ON email_summary_actions(application_id, status, updated_at);
CREATE INDEX idx_email_summary_actions_status_expires
    ON email_summary_actions(status, expires_at);
CREATE INDEX idx_email_summary_actions_processed_message
    ON email_summary_actions(processed_message_id);

-- provider_subscriptions
CREATE INDEX idx_provider_subscriptions_application_id ON provider_subscriptions(application_id);
CREATE INDEX idx_provider_subscriptions_external_id ON provider_subscriptions(external_subscription_id);
CREATE INDEX idx_provider_subscriptions_expires_at ON provider_subscriptions(expires_at);
CREATE INDEX idx_provider_subscriptions_renewal
    ON provider_subscriptions(status, expires_at, renewal_next_retry_at);

-- processed_messages
CREATE INDEX idx_processed_messages_application_id ON processed_messages(application_id);
CREATE INDEX idx_processed_messages_status ON processed_messages(status);
CREATE UNIQUE INDEX idx_processed_messages_stable_fingerprint
    ON processed_messages(application_id, provider_id, provider_stable_message_fingerprint)
    WHERE provider_stable_message_fingerprint IS NOT NULL;
CREATE INDEX idx_processed_messages_app_status_updated
    ON processed_messages(application_id, status, updated_at);
