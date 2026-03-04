/**
 * InstagramTokenRefreshScheduler
 * Scheduled Apex that proactively refreshes Instagram long-lived tokens
 * before they expire (60-day validity).
 *
 * Schedule this to run daily:
 *   System.schedule(
 *     'Instagram Token Daily Refresh',
 *     '0 0 2 * * ?',          // 2 AM every day
 *     new InstagramTokenRefreshScheduler()
 *   );
 *
 * Or via the setup-sample-data.apex script.
 */
global class InstagramTokenRefreshScheduler implements Schedulable {

    global void execute(SchedulableContext ctx) {
        List<Social_Channel_Config__c> configs = [
            SELECT Id, Name, Platform__c, Access_Token__c,
                   Token_Expiry_Date__c, App_Secret__c
            FROM Social_Channel_Config__c
            WHERE Platform__c  = 'Instagram'
              AND Is_Active__c = true
              AND Access_Token__c != null
        ];

        for (Social_Channel_Config__c cfg : configs) {
            if (InstagramOAuthService.needsRefresh(cfg)) {
                try {
                    InstagramOAuthService.TokenExchangeResult result =
                        InstagramOAuthService.refreshLongLivedToken(cfg.Access_Token__c);

                    if (result.success) {
                        InstagramOAuthService.persistToken(
                            cfg.Id,
                            result.accessToken,
                            result.expiresIn != null ? result.expiresIn : 5183944
                        );
                        System.debug('Refreshed Instagram token for config: ' + cfg.Name);
                    } else {
                        System.debug(LoggingLevel.ERROR,
                            'Failed to refresh Instagram token for config: ' + cfg.Name
                            + ' — ' + result.rawResponse);
                    }
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR,
                        'Exception refreshing Instagram token for ' + cfg.Name
                        + ': ' + e.getMessage());
                }
            }
        }
    }
}
