import { AiDailyUsageDAO, UserDAO } from '@mail-otter/backend-data/dao';
import { ConfigurationManager } from '@mail-otter/backend-runtime/config';

interface UserServiceEnv {
  DB: D1Database;
  MAX_APPLICATIONS_PER_USER?: string | undefined;
  MAX_CONTEXT_DOCUMENTS_PER_APPLICATION?: string | undefined;
  AI_DAILY_NEURON_FREE_TIER_LIMIT?: string | undefined;
  AI_DAILY_NEURON_FALLBACK_THRESHOLD?: string | undefined;
}

interface CurrentUserSummary {
  limits: {
    maxApplicationsPerUser: number;
    maxContextDocumentsPerApplication: number;
  };
  aiUsage: {
    estimatedNeurons: number;
    dailyNeuronLimit: number;
    fallbackThreshold: number;
  };
}

class UserService {
  constructor(private readonly env: UserServiceEnv) {}

  async upsertUser(email: string): Promise<void> {
    await new UserDAO(this.env.DB).upsertByEmail(email);
  }

  async getCurrentUserSummary(): Promise<CurrentUserSummary> {
    const today = new Date().toISOString().slice(0, 10);
    const usage = await new AiDailyUsageDAO(this.env.DB).getByDate(today);
    return {
      limits: {
        maxApplicationsPerUser: ConfigurationManager.getMaxApplicationsPerUser(this.env),
        maxContextDocumentsPerApplication: ConfigurationManager.getMaxContextDocumentsPerApplication(this.env),
      },
      aiUsage: {
        estimatedNeurons: usage?.estimatedNeurons ?? 0,
        dailyNeuronLimit: ConfigurationManager.getAiDailyNeuronFreeTierLimit(this.env),
        fallbackThreshold: ConfigurationManager.getAiDailyNeuronFallbackThreshold(this.env),
      },
    };
  }
}

class UserServiceFactory {
  static create(env: UserServiceEnv): UserService {
    return new UserService(env);
  }
}

export { UserService, UserServiceFactory };
export type { CurrentUserSummary, UserServiceEnv };
