/**
 * setup-sample-data.apex
 * Run with: sf apex run --file scripts/apex/setup-sample-data.apex
 *
 * Creates sample Social_Channel_Config__c records so the dashboard
 * shows connected channels immediately after deployment.
 */

// Facebook Page
Social_Channel_Config__c fb = new Social_Channel_Config__c(
    Name                    = 'My Facebook Page',
    Platform__c             = 'Facebook',
    Is_Active__c            = true,
    Page_Name__c            = 'Acme Corp Support',
    Webhook_Verify_Token__c = 'CHANGE_ME_TO_A_SECURE_RANDOM_STRING',
    Last_Verified_Date__c   = DateTime.now()
);

// Instagram Business Account (Instagram API with Instagram Login)
// After inserting this record:
//   1. Set Instagram_App_Id__c and App_Secret__c from the Meta App Dashboard
//   2. Set OAuth_Redirect_Uri__c to your Salesforce Site callback URL
//   3. Call SocialMessagingController.getInstagramAuthUrl(record.Id) to start OAuth
//   4. After OAuth completes, Access_Token__c and Token_Expiry_Date__c are set automatically
Social_Channel_Config__c ig = new Social_Channel_Config__c(
    Name                    = 'My Instagram Account',
    Platform__c             = 'Instagram',
    Is_Active__c            = false,    // set to true after OAuth completes
    Page_Name__c            = '@acmecorpsupport',
    Webhook_Verify_Token__c = 'CHANGE_ME_TO_A_SECURE_RANDOM_STRING',
    Instagram_App_Id__c     = 'YOUR_META_APP_ID',
    OAuth_Redirect_Uri__c   = 'https://YOUR_SITE.force.com/services/apexrest/social/oauth/callback'
);

// WhatsApp Business (placeholder - inactive until configured)
Social_Channel_Config__c wa = new Social_Channel_Config__c(
    Name         = 'WhatsApp Business',
    Platform__c  = 'WhatsApp',
    Is_Active__c = false,
    Page_Name__c = '+1 555 000 0000'
);

insert new List<Social_Channel_Config__c>{ fb, ig, wa };

// ─── Schedule automatic Instagram token refresh ──────────────────────────────
// Runs at 2 AM every day to refresh tokens 7+ days before expiry
try {
    System.schedule(
        'Instagram Token Daily Refresh',
        '0 0 2 * * ?',
        new InstagramTokenRefreshScheduler()
    );
    System.debug('Instagram token refresh scheduler registered.');
} catch (Exception e) {
    System.debug('Scheduler already exists or failed: ' + e.getMessage());
}

System.debug('Sample channel configs created: ' + [
    SELECT Id, Name, Platform__c, Is_Active__c
    FROM Social_Channel_Config__c
]);
