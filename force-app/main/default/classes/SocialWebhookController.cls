/**
 * SocialWebhookController
 * Exposes a REST endpoint that receives webhook events from Facebook and Instagram.
 *
 * URL pattern (configured in the Remote Site Settings / Salesforce Sites):
 *   GET  /services/apexrest/social/webhook  → webhook verification (hub.challenge)
 *   POST /services/apexrest/social/webhook  → incoming message events
 *
 * Facebook App Dashboard → Webhook → Subscribed Fields:
 *   messages, messaging_postbacks, message_reads (Messenger)
 *   messages (Instagram DMs)
 */
@RestResource(urlMapping='/social/webhook/*')
global with sharing class SocialWebhookController {

    // Webhook verify token - store this value as a Custom Setting / Custom Metadata
    private static final String VERIFY_TOKEN_SETTING = 'Social_Webhook_Verify_Token';

    // ─── GET: Facebook/Instagram hub.challenge verification ──────────────────

    @HttpGet
    global static void verifyWebhook() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        String mode        = req.params.get('hub.mode');
        String token       = req.params.get('hub.verify_token');
        String challenge   = req.params.get('hub.challenge');
        String verifyToken = getVerifyToken();

        if (mode == 'subscribe' && token == verifyToken) {
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(challenge);
        } else {
            res.statusCode = 403;
            res.responseBody = Blob.valueOf('Forbidden');
        }
    }

    // ─── POST: Incoming message events ───────────────────────────────────────

    @HttpPost
    global static void receiveWebhookEvent() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String body = req.requestBody.toString();
            Map<String, Object> event = (Map<String, Object>) JSON.deserializeUntyped(body);

            String objectType = (String) event.get('object');

            if (objectType == 'page') {
                processFacebookEvents(event);
            } else if (objectType == 'instagram') {
                processInstagramEvents(event);
            }

            res.statusCode = 200;
            res.responseBody = Blob.valueOf('EVENT_RECEIVED');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SocialWebhookController.receiveWebhookEvent error: ' + e.getMessage());
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('Internal error');
        }
    }

    // ─── Facebook event processing ────────────────────────────────────────────

    @TestVisible
    private static void processFacebookEvents(Map<String, Object> event) {
        List<Object> entries = (List<Object>) event.get('entry');
        if (entries == null) return;

        for (Object entryObj : entries) {
            Map<String, Object> entry     = (Map<String, Object>) entryObj;
            List<Object> messagingList    = (List<Object>) entry.get('messaging');
            if (messagingList == null) continue;

            for (Object msgObj : messagingList) {
                Map<String, Object> messaging = (Map<String, Object>) msgObj;
                Map<String, Object> sender    = (Map<String, Object>) messaging.get('sender');
                String senderId = (String) sender.get('id');

                if (messaging.containsKey('message')) {
                    Map<String, Object> msg  = (Map<String, Object>) messaging.get('message');
                    String text = (String) msg.get('text');
                    String msgId = (String) msg.get('mid');

                    if (String.isNotBlank(text)) {
                        OmniChannelRoutingService.routeInboundMessage(
                            senderId, text, 'Facebook', msgId
                        );
                    }
                } else if (messaging.containsKey('postback')) {
                    Map<String, Object> postback = (Map<String, Object>) messaging.get('postback');
                    String payload = (String) postback.get('payload');
                    String title   = (String) postback.get('title');
                    OmniChannelRoutingService.routeInboundMessage(
                        senderId, title + ' [' + payload + ']', 'Facebook', null
                    );
                }
            }
        }
    }

    // ─── Instagram event processing ───────────────────────────────────────────

    @TestVisible
    private static void processInstagramEvents(Map<String, Object> event) {
        List<Object> entries = (List<Object>) event.get('entry');
        if (entries == null) return;

        for (Object entryObj : entries) {
            Map<String, Object> entry     = (Map<String, Object>) entryObj;
            List<Object> messagingList    = (List<Object>) entry.get('messaging');
            if (messagingList == null) continue;

            for (Object msgObj : messagingList) {
                Map<String, Object> messaging = (Map<String, Object>) msgObj;
                Map<String, Object> sender    = (Map<String, Object>) messaging.get('sender');
                String senderId = (String) sender.get('id');

                if (messaging.containsKey('message')) {
                    Map<String, Object> msg  = (Map<String, Object>) messaging.get('message');
                    String text  = (String) msg.get('text');
                    String msgId = (String) msg.get('mid');

                    if (String.isNotBlank(text)) {
                        OmniChannelRoutingService.routeInboundMessage(
                            senderId, text, 'Instagram', msgId
                        );
                    }
                }
            }
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static String getVerifyToken() {
        List<Social_Channel_Config__c> configs = [
            SELECT Webhook_Verify_Token__c
            FROM Social_Channel_Config__c
            WHERE Is_Active__c = true
            LIMIT 1
        ];
        return configs.isEmpty() ? '' : configs[0].Webhook_Verify_Token__c;
    }
}
