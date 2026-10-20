# OpenRouter: models for chat, code and the agent fleet.
# Its capabilities are the closed set every openrouter plan must state, each with
# the page that states it (../accounts).
{
  accounts = {
    capabilities.openrouter = {
      managementKeys = "flag";
      keyCreditLimits = "flag";
    };

    # Prepaid credits, spent per token.
    plans.openrouter.pay-as-you-go = {
      checked = "2026-10-20";
      capabilities = {
        # A management key creates, limits and disables API keys; it cannot
        # call models itself.
        managementKeys = {
          value = true;
          source = "https://openrouter.ai/docs/guides/overview/auth/management-api-keys";
        };
        keyCreditLimits = {
          value = true;
          source = "https://openrouter.ai/docs/guides/overview/auth/management-api-keys";
        };
      };
    };

    # Models for chat and code, default deepseek/deepseek-v4-flash.
    held.openrouter = {
      provider = "openrouter";
      plan = "pay-as-you-go";
      owner = "kagamizo";
      status = "planned";
      signup = {
        url = "https://openrouter.ai/sign-up";
        handle = "kagamizo";
        email = "dev@kagamizo.com";
        credential = "password";
        findings = [
          {
            fact = "OpenRouter has no official CLI; its management API creates, limits and disables keys";
            source = "https://openrouter.ai/docs/guides/overview/auth/management-api-keys";
            checked = "2026-10-20";
          }
          {
            fact = "the first management key and the first credit top-up are made in the web dashboard";
            source = "https://openrouter.ai/docs/guides/overview/auth/management-api-keys";
            checked = "2026-10-20";
          }
        ];
      };
    };
  };
}
