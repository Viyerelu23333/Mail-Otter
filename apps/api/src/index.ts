import { EmailEventsDispatcherWorker } from '@mail-otter/background';
import { MailOtterWorker } from '@/workers';
export { CronTasksWorker, EmailProcessingWorkflow, OAuth2TokenRefreshWorker } from '@mail-otter/background';

const mailOtterWorker: MailOtterWorker = new MailOtterWorker();
const emailEventsDispatcherWorker: EmailEventsDispatcherWorker = new EmailEventsDispatcherWorker();

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return mailOtterWorker.fetch(request, env, ctx);
  },
  scheduled(controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    return mailOtterWorker.scheduled(controller, env, ctx);
  },
  queue(batch: MessageBatch<unknown>, env: Env, ctx: ExecutionContext): Promise<void> {
    return emailEventsDispatcherWorker.queue(batch, env, ctx);
  },
};
