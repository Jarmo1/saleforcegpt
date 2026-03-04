/**
 * SocialWebhookController
 * REST endpoint receiving webhook events from Facebook Messenger and Instagram.
 *
 * Endpoints (exposed via Salesforce Sites / Experience Cloud):
 *   GET  /services/apexrest/social/webhook  → hub.challenge verification
 *   POST /services/apexrest/social/webhook  → inbound message events
 *
 * Meta App Dashboard → Webhooks → Subscribe to:
 *   Facebook : messages, messaging_postbacks, message_reads
 *   Instagram: messages, messaging_reactions (Instagram API with Instagram Login)
 *
 * Security: X-Hub-Signature-256 is validated on POST requests when
 * App_Secret__c is populated on the Social_Channel_Config__c record.
 */
@RestResource(urlMapping='/social/webhook/*')
global with sharing class SocialWebhookController {

    // ─── GET: hub.challenge verification ─────────────────────────────────────

    @HttpGet
    global static void verifyWebhook() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        String mode      = req.params.get('hub.mode');
        String token     = req.params.get('hub.verify_token');
        String challenge = req.params.get('hub.challenge');

        if (mode == 'subscribe' && token == getVerifyToken()) {
            res.statusCode   = 200;
            res.responseBody = Blob.valueOf(challenge);
        } else {
            res.statusCode   = 403;
            res.responseBody = Blob.valueOf('Forbidden');
        }
    }

    // ─── POST: Incoming events ────────────────────────────────────────────────

    @HttpPost
    global static void receiveWebhookEvent() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String body = req.requestBody.toString();

            // Validate X-Hub-Signature-256 when app secret is configured
            String sigHeader = req.headers.get('X-Hub-Signature-256');
            if (!validateSignature(body, sigHeader)) {
                res.statusCode   = 403;
                res.responseBody = Blob.valueOf('Invalid signature');
                return;
            }

            Map<String, Object> event      = (Map<String, Object>) JSON.deserializeUntyped(body);
            String              objectType = (String) event.get('object');

            if (objectType == 'page') {
                processFacebookEvents(event);
            } else if (objectType == 'instagram') {
                processInstagramEvents(event);
            }

            res.statusCode   = 200;
            res.responseBody = Blob.valueOf('EVENT_RECEIVED');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SocialWebhookController.receiveWebhookEvent error: ' + e.getMessage()
                + '\n' + e.getStackTraceString());
            res.statusCode   = 500;
            res.responseBody = Blob.valueOf('Internal error');
        }
    }

    // ─── Facebook Messenger event processing ─────────────────────────────────

    @TestVisible
    private static void processFacebookEvents(Map<String, Object> event) {
        List<Object> entries = (List<Object>) event.get('entry');
        if (entries == null) return;

        for (Object entryObj : entries) {
            Map<String, Object> entry        = (Map<String, Object>) entryObj;
            List<Object>        messagingList = (List<Object>) entry.get('messaging');
            if (messagingList == null) continue;

            for (Object msgObj : messagingList) {
                Map<String, Object> m      = (Map<String, Object>) msgObj;
                Map<String, Object> sender = (Map<String, Object>) m.get('sender');
                String senderId = (String) sender.get('id');

                if (m.containsKey('message')) {
                    Map<String, Object> msg = (Map<String, Object>) m.get('message');
                    // Skip echo events (messages sent by the page itself)
                    if (Boolean.valueOf(String.valueOf(msg.get('is_echo') ?? 'false'))) continue;

                    String text  = (String) msg.get('text');
                    String msgId = (String) msg.get('mid');
                    if (String.isNotBlank(text)) {
                        OmniChannelRoutingService.routeInboundMessage(
                            senderId, text, 'Facebook', msgId
                        );
                    }
                } else if (m.containsKey('postback')) {
                    Map<String, Object> postback = (Map<String, Object>) m.get('postback');
                    String payload = (String) postback.get('payload');
                    String title   = (String) postback.get('title');
                    OmniChannelRoutingService.routeInboundMessage(
                        senderId, title + ' [' + payload + ']', 'Facebook', null
                    );
                }
            }
        }
    }

    // ─── Instagram event processing (Instagram API with Instagram Login) ──────
    //
    // Webhook object = "instagram"
    // Subscribed fields: messages, messaging_reactions
    //
    // Entry structure:
    //   entry[].id          → Instagram Business Account ID
    //   entry[].messaging[] → messaging events (same shape as Messenger)
    //     .sender.id        → IGSID of the person who sent the message
    //     .recipient.id     → Your Instagram Business Account ID
    //     .message.mid      → Message ID
    //     .message.text     → Text content (may be absent for attachments/stickers)
    //     .message.attachments[] → Array of attachments (images, audio, etc.)
    //     .message.reply_to  → Present when replying to a story/message

    @TestVisible
    private static void processInstagramEvents(Map<String, Object> event) {
        List<Object> entries = (List<Object>) event.get('entry');
        if (entries == null) return;

        for (Object entryObj : entries) {
            Map<String, Object> entry        = (Map<String, Object>) entryObj;
            List<Object>        messagingList = (List<Object>) entry.get('messaging');
            if (messagingList == null) continue;

            for (Object msgObj : messagingList) {
                Map<String, Object> m      = (Map<String, Object>) msgObj;
                Map<String, Object> sender = (Map<String, Object>) m.get('sender');
                String senderId = (String) sender.get('id');

                if (m.containsKey('message')) {
                    Map<String, Object> msg = (Map<String, Object>) m.get('message');
                    // Skip echo events
                    if (Boolean.valueOf(String.valueOf(msg.get('is_echo') ?? 'false'))) continue;

                    String text  = (String) msg.get('text');
                    String msgId = (String) msg.get('mid');

                    // Build display text: use message text, or describe attachment type
                    String displayText = text;
                    if (String.isBlank(displayText)) {
                        displayText = extractAttachmentDescription(msg);
                    }

                    // Handle story reply context
                    if (m.containsKey('reply_to')) {
                        Map<String, Object> replyTo = (Map<String, Object>) m.get('reply_to');
                        String storyId = (String) replyTo.get('story');
                        if (String.isNotBlank(storyId)) {
                            displayText = '[Story Reply] ' + (displayText ?? '');
                        }
                    }

                    if (String.isNotBlank(displayText)) {
                        OmniChannelRoutingService.routeInboundMessage(
                            senderId, displayText, 'Instagram', msgId
                        );
                    }

                } else if (m.containsKey('reaction')) {
                    // messaging_reactions webhook field — log but don't create new cases
                    Map<String, Object> reaction = (Map<String, Object>) m.get('reaction');
                    String emoji   = (String) reaction.get('emoji');
                    String reactionMid = (String) reaction.get('mid');
                    System.debug('Instagram reaction ' + emoji + ' on message ' + reactionMid
                        + ' from IGSID ' + senderId);
                }
            }
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    /**
     * Validates X-Hub-Signature-256: sha256=<hmac-hex>
     * If no app secret is configured, the check is skipped (returns true).
     * In production, always configure App_Secret__c.
     */
    @TestVisible
    private static Boolean validateSignature(String body, String sigHeader) {
        String appSecret = getAppSecret();
        if (String.isBlank(appSecret)) return true;       // secret not configured — skip
        if (String.isBlank(sigHeader)) return false;      // secret configured but no header

        String expectedHex = EncodingUtil.convertToHex(
            Crypto.generateMac('hmacSHA256',
                Blob.valueOf(body),
                Blob.valueOf(appSecret)
            )
        );
        String receivedHex = sigHeader.replace('sha256=', '');
        return expectedHex.equalsIgnoreCase(receivedHex);
    }

    private static String extractAttachmentDescription(Map<String, Object> msg) {
        List<Object> attachments = (List<Object>) msg.get('attachments');
        if (attachments == null || attachments.isEmpty()) return null;

        Map<String, Object> first = (Map<String, Object>) attachments[0];
        String type = (String) first.get('type');
        switch on type {
            when 'image'  { return '[Image attachment]'; }
            when 'video'  { return '[Video attachment]'; }
            when 'audio'  { return '[Audio attachment]'; }
            when 'file'   { return '[File attachment]';  }
            when 'share'  { return '[Shared post]';      }
            when 'sticker'{ return '[Sticker]';          }
            when else     { return '[Attachment: ' + type + ']'; }
        }
    }

    private static String getVerifyToken() {
        List<Social_Channel_Config__c> configs = [
            SELECT Webhook_Verify_Token__c
            FROM Social_Channel_Config__c
            WHERE Is_Active__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return configs.isEmpty() ? '' : configs[0].Webhook_Verify_Token__c;
    }

    private static String getAppSecret() {
        List<Social_Channel_Config__c> configs = [
            SELECT App_Secret__c
            FROM Social_Channel_Config__c
            WHERE Is_Active__c  = true
              AND App_Secret__c != null
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0].App_Secret__c;
    }
}
