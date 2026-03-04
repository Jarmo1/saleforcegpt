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

// Instagram Business Account
Social_Channel_Config__c ig = new Social_Channel_Config__c(
    Name                    = 'My Instagram Account',
    Platform__c             = 'Instagram',
    Is_Active__c            = true,
    Page_Name__c            = '@acmecorpsupport',
    Webhook_Verify_Token__c = 'CHANGE_ME_TO_A_SECURE_RANDOM_STRING',
    Last_Verified_Date__c   = DateTime.now()
);

// WhatsApp Business (placeholder - inactive until configured)
Social_Channel_Config__c wa = new Social_Channel_Config__c(
    Name         = 'WhatsApp Business',
    Platform__c  = 'WhatsApp',
    Is_Active__c = false,
    Page_Name__c = '+1 555 000 0000'
);

insert new List<Social_Channel_Config__c>{ fb, ig, wa };

System.debug('Sample channel configs created: ' + [
    SELECT Id, Name, Platform__c, Is_Active__c
    FROM Social_Channel_Config__c
]);
