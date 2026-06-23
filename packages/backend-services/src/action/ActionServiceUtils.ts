import { EmailActionDAO } from '@mail-otter/backend-data/dao';
import type { D1Queryable } from '@mail-otter/backend-data/utils';
import { CryptoUtil } from '@mail-otter/shared/utils';

interface ActionDAOEnv {
  DB: D1Queryable;
  ACTION_ENCRYPTION_KEY_SECRET: SecretsStoreSecret;
}

async function createActionDAO(env: ActionDAOEnv): Promise<EmailActionDAO> {
  return new EmailActionDAO(env.DB, await env.ACTION_ENCRYPTION_KEY_SECRET.get());
}

async function hashToken(actionId: string, token: string, signingSecret: string): Promise<string> {
  return CryptoUtil.hmacSha256Hex(`email-action-token\n${actionId}\n${token}`, signingSecret);
}

export type { ActionDAOEnv };
export { createActionDAO, hashToken };
