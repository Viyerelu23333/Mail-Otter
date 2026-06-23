-- Migration 0020: Add auto_execute trigger type to email_action_executions
-- D1 does not support ALTER TABLE ... MODIFY COLUMN, so the table is recreated.

ALTER TABLE email_action_executions RENAME TO bak_email_action_executions;

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
    CHECK (triggered_by IN ('email_callback', 'web_ui', 'system_expiry', 'auto_execute')),
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

CREATE INDEX idx_email_action_executions_action
    ON email_action_executions(action_id, created_at);
