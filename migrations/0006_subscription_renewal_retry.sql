ALTER TABLE provider_subscriptions ADD COLUMN renewal_retry_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE provider_subscriptions ADD COLUMN renewal_next_retry_at INTEGER;
