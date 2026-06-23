import { IUserRoute } from '@/endpoints/IUserRoute';
import type { IUserEnv, IRequest, IResponse, RouteContext } from '@/endpoints/IUserRoute';
import { ApplicationService } from '@mail-otter/backend-services/application';
import type { ConnectedApplicationMetadata, EmailProcessingRule } from '@mail-otter/shared/model';

class UpdateApplicationRulesRoute extends IUserRoute<UpdateApplicationRulesRequest, UpdateApplicationRulesResponse, UpdateApplicationRulesEnv> {
  schema = {
    tags: ['Rules'],
    summary: 'Replace email processing rules for a mailbox',
    responses: {
      '200': {
        description: 'Rules updated',
      },
    },
  };

  protected async handleRequest(
    request: UpdateApplicationRulesRequest,
    env: UpdateApplicationRulesEnv,
    cxt: RouteContext<UpdateApplicationRulesEnv>,
  ): Promise<UpdateApplicationRulesResponse> {
    const application = await new ApplicationService(env).updateRules(this.getAuthenticatedUserEmailAddress(cxt), request.applicationId, request.rules);
    return { application };
  }
}

interface UpdateApplicationRulesRequest extends IRequest {
  applicationId: string;
  rules: EmailProcessingRule[];
}

interface UpdateApplicationRulesResponse extends IResponse {
  application: ConnectedApplicationMetadata;
}

type UpdateApplicationRulesEnv = IUserEnv;

export { UpdateApplicationRulesRoute };
