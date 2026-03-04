/**
 * InstagramGraphAPIService
 * Handles outbound calls to the Instagram Platform API using Instagram Login.
 *
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  IMPORTANT — API changed July 2024                              │
 * │  This uses the Instagram API with Instagram Login approach.     │
 * │  Base URL: https://graph.instagram.com  (NOT graph.facebook.com)│
 * │  No Facebook Page link required.                               │
 * └─────────────────────────────────────────────────────────────────┘
 *
 * Required Named Credential:
 *   Name:     "Instagram_Graph_API"
 *   URL:      https://graph.instagram.com
 *   Protocol: Custom (No Authentication)
 *   Header:   Authorization → Bearer {long-lived Instagram User Access Token}
 *
 * Required scopes (set in Meta App → App Review):
 *   instagram_business_basic
 *   instagram_manage_messages
 *
 * @see InstagramOAuthService for token acquisition and refresh.
 */
public with sharing class InstagramGraphAPIService {

    private static final String API_VERSION    = 'v21.0';
    private static final String NAMED_CRED     = 'callout:Instagram_Graph_API';

    // ─── Send a plain text DM ─────────────────────────────────────────────────

    /**
     * @param recipientIgsid  Instagram-scoped User ID (IGSID) of the recipient.
     *                        This is the `sender.id` value from the inbound webhook.
     */
    public static InstagramSendResult sendTextMessage(String recipientIgsid, String messageText) {
        return callMessagesEndpoint(buildPayload(recipientIgsid,
            new Map<String, Object>{ 'text' => messageText }
        ));
    }

    // ─── Send an image attachment ─────────────────────────────────────────────

    public static InstagramSendResult sendImageMessage(String recipientIgsid, String imageUrl) {
        return callMessagesEndpoint(buildPayload(recipientIgsid,
            new Map<String, Object>{
                'attachment' => new Map<String, Object>{
                    'type'    => 'image',
                    'payload' => new Map<String, Object>{
                        'url'         => imageUrl,
                        'is_reusable' => true
                    }
                }
            }
        ));
    }

    // ─── Send quick replies ───────────────────────────────────────────────────

    public static InstagramSendResult sendQuickReplies(
        String recipientIgsid,
        String messageText,
        List<Map<String, String>> quickReplies
    ) {
        List<Object> qrList = new List<Object>();
        for (Map<String, String> qr : quickReplies) {
            qrList.add(new Map<String, Object>{
                'content_type' => 'text',
                'title'        => qr.get('title'),
                'payload'      => qr.get('payload')
            });
        }
        return callMessagesEndpoint(buildPayload(recipientIgsid,
            new Map<String, Object>{ 'text' => messageText, 'quick_replies' => qrList }
        ));
    }

    // ─── Sender actions ───────────────────────────────────────────────────────

    public static void sendTypingOn(String recipientIgsid) {
        callSenderAction(recipientIgsid, 'typing_on');
    }

    public static void sendTypingOff(String recipientIgsid) {
        callSenderAction(recipientIgsid, 'typing_off');
    }

    public static void markAsSeen(String recipientIgsid) {
        callSenderAction(recipientIgsid, 'mark_seen');
    }

    // ─── Get the authenticated business account info ──────────────────────────

    /**
     * Returns info for the account whose token is stored in the Named Credential.
     * GET https://graph.instagram.com/v21.0/me?fields=id,name,username,...
     */
    public static InstagramAccountInfo getMyAccountInfo() {
        HttpRequest req = buildGetRequest(
            NAMED_CRED + '/' + API_VERSION + '/me'
            + '?fields=id,name,username,profile_picture_url,followers_count'
        );
        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> d = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            InstagramAccountInfo info = new InstagramAccountInfo();
            info.id                = (String) d.get('id');
            info.name              = (String) d.get('name');
            info.username          = (String) d.get('username');
            info.profilePictureUrl = (String) d.get('profile_picture_url');
            info.followersCount    = d.get('followers_count') != null
                ? Integer.valueOf(String.valueOf(d.get('followers_count'))) : 0;
            return info;
        }
        System.debug(LoggingLevel.ERROR,
            'InstagramGraphAPIService.getMyAccountInfo ' + res.getStatusCode()
            + ': ' + res.getBody());
        return null;
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static Map<String, Object> buildPayload(String igsid, Map<String, Object> message) {
        return new Map<String, Object>{
            'recipient' => new Map<String, Object>{ 'id' => igsid },
            'message'   => message
        };
    }

    private static InstagramSendResult callMessagesEndpoint(Map<String, Object> payload) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CRED + '/' + API_VERSION + '/me/messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        InstagramSendResult result = new InstagramSendResult();
        result.statusCode  = res.getStatusCode();
        result.rawResponse = res.getBody();

        if (res.getStatusCode() == 200) {
            Map<String, Object> d = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            result.success     = true;
            result.messageId   = (String) d.get('message_id');
            result.recipientId = (String) d.get('recipient_id');
        } else {
            result.success = false;
            System.debug(LoggingLevel.ERROR,
                'InstagramGraphAPIService.callMessagesEndpoint '
                + result.statusCode + ': ' + result.rawResponse);
        }
        return result;
    }

    private static void callSenderAction(String igsid, String action) {
        Map<String, Object> payload = new Map<String, Object>{
            'recipient'     => new Map<String, Object>{ 'id' => igsid },
            'sender_action' => action
        };
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CRED + '/' + API_VERSION + '/me/messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(10000);
        new Http().send(req);
    }

    private static HttpRequest buildGetRequest(String endpoint) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(10000);
        return req;
    }

    // ─── DTOs ─────────────────────────────────────────────────────────────────

    public class InstagramSendResult {
        public Boolean success;
        public Integer statusCode;
        public String  messageId;
        public String  recipientId;
        public String  rawResponse;
    }

    public class InstagramAccountInfo {
        public String  id;
        public String  name;
        public String  username;
        public String  profilePictureUrl;
        public Integer followersCount;
    }
}
