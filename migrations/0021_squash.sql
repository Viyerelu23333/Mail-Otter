-- Migration 0021: Squash of migrations 0001–0020
-- Complete schema for a fresh database installation.

-- ============================================================
-- Tables (creation order respects foreign-key dependencies)
-- ============================================================

CREATE TABLE IF NOT EXISTS users (
    email TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS connected_applications (
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

CREATE TABLE IF NOT EXISTS provider_subscriptions (
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

CREATE TABLE IF NOT EXISTS processed_messages (
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

CREATE TABLE IF NOT EXISTS oauth2_authorization_sessions (
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

CREATE TABLE IF NOT EXISTS oauth2_access_token_refresh_status (
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

CREATE TABLE IF NOT EXISTS ai_daily_usage (
    usage_date TEXT PRIMARY KEY,
    estimated_neurons INTEGER NOT NULL DEFAULT 0,
    prompt_tokens INTEGER NOT NULL DEFAULT 0,
    completion_tokens INTEGER NOT NULL DEFAULT 0,
    embedding_tokens INTEGER NOT NULL DEFAULT 0,
    request_count INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS application_watched_folders (
    application_id TEXT NOT NULL,
    folder_path TEXT NOT NULL,
    folder_name TEXT,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (application_id, folder_path),
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS provider_application_configs (
    application_id TEXT NOT NULL,
    config_key TEXT NOT NULL,
    config_value TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (application_id, config_key),
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS application_context_documents (
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

CREATE TABLE IF NOT EXISTS context_audit_logs (
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

CREATE TABLE IF NOT EXISTS application_context_deletion_runs (
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

CREATE TABLE IF NOT EXISTS application_integrations (
    integration_id TEXT NOT NULL PRIMARY KEY,
    application_id TEXT NOT NULL,
    integration_type TEXT NOT NULL,
    name TEXT NOT NULL,
    encrypted_webhook_url TEXT NOT NULL,
    webhook_url_iv TEXT NOT NULL,
    webhook_url_prefix TEXT NOT NULL DEFAULT '',
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    last_delivery_at INTEGER,
    last_delivery_status TEXT,
    consecutive_failures INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (application_id) REFERENCES connected_applications(application_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS integration_delivery_logs (
    log_id TEXT NOT NULL PRIMARY KEY,
    integration_id TEXT NOT NULL,
    application_id TEXT NOT NULL,
    status TEXT NOT NULL,
    http_status INTEGER,
    error_message TEXT,
    email_subject TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (integration_id) REFERENCES application_integrations(integration_id) ON DELETE CASCADE,
    CHECK (status IN ('success', 'failure'))
);

CREATE TABLE IF NOT EXISTS email_summary_actions (
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
    CHECK (action_type IN (
        'calendar.add_event',
        'email.draft_reply',
        'external.open_link',
        'manual.todo',
        'delivery.track_package',
        'travel.track_flight',
        'finance.pay_bill',
        'appointment.confirm'
    )),
    CHECK (status IN ('pending', 'executing', 'succeeded', 'failed', 'expired', 'cancelled')),
    CHECK (risk_level IN ('low', 'medium', 'high'))
);

CREATE TABLE IF NOT EXISTS email_action_executions (
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
    CHECK (triggered_by IN ('email_callback', 'web_ui', 'system_expiry', 'auto_execute')),
    CHECK (status IN ('pending', 'executing', 'succeeded', 'failed', 'expired', 'cancelled'))
);

-- ============================================================
-- Indexes
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_connected_applications_user_email
    ON connected_applications(user_email);

CREATE INDEX IF NOT EXISTS idx_provider_subscriptions_application_id
    ON provider_subscriptions(application_id);
CREATE INDEX IF NOT EXISTS idx_provider_subscriptions_external_id
    ON provider_subscriptions(external_subscription_id);
CREATE INDEX IF NOT EXISTS idx_provider_subscriptions_expires_at
    ON provider_subscriptions(expires_at);
CREATE INDEX IF NOT EXISTS idx_provider_subscriptions_renewal
    ON provider_subscriptions(status, expires_at, renewal_next_retry_at);

CREATE INDEX IF NOT EXISTS idx_processed_messages_application_id
    ON processed_messages(application_id);
CREATE INDEX IF NOT EXISTS idx_processed_messages_status
    ON processed_messages(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_processed_messages_stable_fingerprint
    ON processed_messages(application_id, provider_id, provider_stable_message_fingerprint)
    WHERE provider_stable_message_fingerprint IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_processed_messages_app_status_updated
    ON processed_messages(application_id, status, updated_at);

CREATE INDEX IF NOT EXISTS idx_oauth2_authorization_sessions_application_id
    ON oauth2_authorization_sessions(application_id);
CREATE INDEX IF NOT EXISTS idx_oauth2_authorization_sessions_expires_at
    ON oauth2_authorization_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_oauth2_sessions_app_state
    ON oauth2_authorization_sessions(application_id, state_hash);

CREATE INDEX IF NOT EXISTS idx_oauth2_access_token_refresh_status_expires_at
    ON oauth2_access_token_refresh_status(access_token_expires_at);
CREATE INDEX IF NOT EXISTS idx_oauth2_access_token_refresh_status_updated_at
    ON oauth2_access_token_refresh_status(updated_at);

CREATE INDEX IF NOT EXISTS idx_application_watched_folders_application
    ON application_watched_folders(application_id);

CREATE INDEX IF NOT EXISTS idx_provider_application_configs_app
    ON provider_application_configs(application_id);

CREATE INDEX IF NOT EXISTS idx_application_context_documents_application_id
    ON application_context_documents(application_id);
CREATE INDEX IF NOT EXISTS idx_application_context_documents_user_email
    ON application_context_documents(user_email);
CREATE INDEX IF NOT EXISTS idx_application_context_documents_status
    ON application_context_documents(status);
CREATE INDEX IF NOT EXISTS idx_application_context_documents_vector_id
    ON application_context_documents(vector_id);
CREATE INDEX IF NOT EXISTS idx_application_context_documents_application_created
    ON application_context_documents(application_id, created_at)
    WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_application_context_documents_user_sort
    ON application_context_documents(user_email, updated_at, created_at);

CREATE INDEX IF NOT EXISTS idx_cal_ctx_doc
    ON context_audit_logs(context_document_id, created_at);

CREATE INDEX IF NOT EXISTS idx_application_context_deletion_runs_application_id
    ON application_context_deletion_runs(application_id);
CREATE INDEX IF NOT EXISTS idx_application_context_deletion_runs_user_email
    ON application_context_deletion_runs(user_email);

CREATE INDEX IF NOT EXISTS idx_application_integrations_app_id
    ON application_integrations(application_id);

CREATE INDEX IF NOT EXISTS idx_idl_integration_created
    ON integration_delivery_logs(integration_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_idl_created_at
    ON integration_delivery_logs(created_at);

CREATE INDEX IF NOT EXISTS idx_email_summary_actions_user_sort
    ON email_summary_actions(user_email, updated_at, created_at);
CREATE INDEX IF NOT EXISTS idx_email_summary_actions_application_status
    ON email_summary_actions(application_id, status, updated_at);
CREATE INDEX IF NOT EXISTS idx_email_summary_actions_status_expires
    ON email_summary_actions(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_email_summary_actions_processed_message
    ON email_summary_actions(processed_message_id);

CREATE INDEX IF NOT EXISTS idx_email_action_executions_action
    ON email_action_executions(action_id, created_at);
