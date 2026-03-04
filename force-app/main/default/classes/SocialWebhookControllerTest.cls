/**
 * SocialWebhookControllerTest
 * Unit tests for SocialWebhookController REST endpoint.
 */
@IsTest
private class SocialWebhookControllerTest {

    @TestSetup
    static void setup() {
        Social_Channel_Config__c config = new Social_Channel_Config__c(
            Name                   = 'Test Facebook Page',
            Platform__c            = 'Facebook',
            Is_Active__c           = true,
            Webhook_Verify_Token__c = 'test_verify_token_123',
            Page_Name__c           = 'Test Page'
        );
        insert config;
    }

    // ─── GET verification tests ───────────────────────────────────────────────

    @IsTest
    static void testVerifyWebhook_ValidToken() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/social/webhook';
        req.httpMethod = 'GET';
        req.params.put('hub.mode',         'subscribe');
        req.params.put('hub.verify_token', 'test_verify_token_123');
        req.params.put('hub.challenge',    'ABC123CHALLENGE');

        RestResponse res = new RestResponse();
        RestContext.request  = req;
        RestContext.response = res;

        Test.startTest();
        SocialWebhookController.verifyWebhook();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Should return 200 for valid token');
        System.assertEquals('ABC123CHALLENGE', res.responseBody.toString(),
            'Should echo challenge back');
    }

    @IsTest
    static void testVerifyWebhook_InvalidToken() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/social/webhook';
        req.httpMethod = 'GET';
        req.params.put('hub.mode',         'subscribe');
        req.params.put('hub.verify_token', 'wrong_token');
        req.params.put('hub.challenge',    'ABC123CHALLENGE');

        RestResponse res = new RestResponse();
        RestContext.request  = req;
        RestContext.response = res;

        Test.startTest();
        SocialWebhookController.verifyWebhook();
        Test.stopTest();

        System.assertEquals(403, res.statusCode, 'Should return 403 for invalid token');
    }

    // ─── POST event tests ─────────────────────────────────────────────────────

    @IsTest
    static void testReceiveFacebookMessage() {
        String facebookPayload = '{'
            + '"object": "page",'
            + '"entry": [{'
            + '  "messaging": [{'
            + '    "sender":  { "id": "FB_USER_001" },'
            + '    "message": { "mid": "MSG_001", "text": "Hello from Facebook" }'
            + '  }]'
            + '}]'
            + '}';

        RestRequest req = new RestRequest();
        req.requestURI   = '/services/apexrest/social/webhook';
        req.httpMethod   = 'POST';
        req.requestBody  = Blob.valueOf(facebookPayload);

        RestResponse res = new RestResponse();
        RestContext.request  = req;
        RestContext.response = res;

        Test.startTest();
        SocialWebhookController.receiveWebhookEvent();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Should return 200 for valid event');

        List<Case> cases = [SELECT Id, Platform__c FROM Case WHERE Platform__c = 'Facebook'];
        System.assertEquals(1, cases.size(), 'A Case should have been created');
    }

    @IsTest
    static void testReceiveInstagramMessage() {
        String igPayload = '{'
            + '"object": "instagram",'
            + '"entry": [{'
            + '  "messaging": [{'
            + '    "sender":  { "id": "IG_USER_001" },'
            + '    "message": { "mid": "IG_MSG_001", "text": "DM from Instagram" }'
            + '  }]'
            + '}]'
            + '}';

        RestRequest req = new RestRequest();
        req.requestURI  = '/services/apexrest/social/webhook';
        req.httpMethod  = 'POST';
        req.requestBody = Blob.valueOf(igPayload);

        RestResponse res = new RestResponse();
        RestContext.request  = req;
        RestContext.response = res;

        Test.startTest();
        SocialWebhookController.receiveWebhookEvent();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Case> cases = [SELECT Id, Platform__c FROM Case WHERE Platform__c = 'Instagram'];
        System.assertEquals(1, cases.size(), 'A Case should have been created');
    }

    @IsTest
    static void testDeduplication() {
        String payload = '{'
            + '"object": "page",'
            + '"entry": [{'
            + '  "messaging": [{'
            + '    "sender":  { "id": "FB_USER_DUP" },'
            + '    "message": { "mid": "DUP_MSG_001", "text": "Duplicate test" }'
            + '  }]'
            + '}]'
            + '}';

        RestRequest req = new RestRequest();
        req.requestURI  = '/services/apexrest/social/webhook';
        req.httpMethod  = 'POST';
        req.requestBody = Blob.valueOf(payload);
        RestContext.request  = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        SocialWebhookController.receiveWebhookEvent();

        // Send same event again
        RestContext.request  = req;
        RestContext.response = new RestResponse();
        SocialWebhookController.receiveWebhookEvent();
        Test.stopTest();

        List<Case> cases = [SELECT Id FROM Case WHERE Platform_User_Id__c = 'FB_USER_DUP'];
        System.assertEquals(1, cases.size(), 'Duplicate messages should not create extra cases');
    }
}
