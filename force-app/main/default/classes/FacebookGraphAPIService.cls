/**
 * FacebookGraphAPIService
 * Handles all outbound calls to the Facebook Graph API.
 * Supports sending messages via Messenger and fetching conversation threads.
 *
 * Prerequisites:
 *  - Named Credential "Facebook_Graph_API" configured with the Page Access Token
 *  - Connected App with facebook_messenger scope approved in Salesforce
 */
public with sharing class FacebookGraphAPIService {

    private static final String GRAPH_API_VERSION = 'v19.0';
    private static final String NAMED_CREDENTIAL   = 'callout:Facebook_Graph_API';

    // ─── Send a text message to a recipient ───────────────────────────────────

    public static FacebookSendMessageResult sendTextMessage(String recipientId, String messageText) {
        Map<String, Object> payload = new Map<String, Object>{
            'recipient' => new Map<String, Object>{ 'id' => recipientId },
            'message'   => new Map<String, Object>{ 'text' => messageText },
            'messaging_type' => 'RESPONSE'
        };
        return sendMessage(payload);
    }

    // ─── Send a quick reply message ───────────────────────────────────────────

    public static FacebookSendMessageResult sendQuickReply(
        String recipientId,
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
        Map<String, Object> payload = new Map<String, Object>{
            'recipient' => new Map<String, Object>{ 'id' => recipientId },
            'message'   => new Map<String, Object>{
                'text'          => messageText,
                'quick_replies' => qrList
            },
            'messaging_type' => 'RESPONSE'
        };
        return sendMessage(payload);
    }

    // ─── Mark message as seen / typing indicator ─────────────────────────────

    public static void markAsSeen(String recipientId) {
        sendSenderAction(recipientId, 'mark_seen');
    }

    public static void sendTypingOn(String recipientId) {
        sendSenderAction(recipientId, 'typing_on');
    }

    public static void sendTypingOff(String recipientId) {
        sendSenderAction(recipientId, 'typing_off');
    }

    // ─── Get user profile from Facebook ──────────────────────────────────────

    public static FacebookUserProfile getUserProfile(String userId) {
        String endpoint = NAMED_CREDENTIAL + '/' + GRAPH_API_VERSION + '/'
            + userId + '?fields=name,first_name,last_name,profile_pic';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(10000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 200) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            FacebookUserProfile profile = new FacebookUserProfile();
            profile.id         = (String) data.get('id');
            profile.name       = (String) data.get('name');
            profile.firstName  = (String) data.get('first_name');
            profile.lastName   = (String) data.get('last_name');
            profile.profilePic = (String) data.get('profile_pic');
            return profile;
        }
        System.debug(LoggingLevel.ERROR,
            'FacebookGraphAPIService.getUserProfile failed: ' + res.getBody());
        return null;
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static FacebookSendMessageResult sendMessage(Map<String, Object> payload) {
        String endpoint = NAMED_CREDENTIAL + '/' + GRAPH_API_VERSION + '/me/messages';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        FacebookSendMessageResult result = new FacebookSendMessageResult();
        result.statusCode = res.getStatusCode();
        result.rawResponse = res.getBody();

        if (res.getStatusCode() == 200) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            result.messageId  = (String) data.get('message_id');
            result.recipientId = (String) data.get('recipient_id');
            result.success    = true;
        } else {
            result.success = false;
            System.debug(LoggingLevel.ERROR,
                'FacebookGraphAPIService.sendMessage failed: ' + res.getBody());
        }
        return result;
    }

    private static void sendSenderAction(String recipientId, String action) {
        Map<String, Object> payload = new Map<String, Object>{
            'recipient'     => new Map<String, Object>{ 'id' => recipientId },
            'sender_action' => action
        };
        String endpoint = NAMED_CREDENTIAL + '/' + GRAPH_API_VERSION + '/me/messages';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(10000);

        new Http().send(req);
    }

    // ─── Inner result / DTO classes ───────────────────────────────────────────

    public class FacebookSendMessageResult {
        public Boolean success;
        public Integer statusCode;
        public String  messageId;
        public String  recipientId;
        public String  rawResponse;
    }

    public class FacebookUserProfile {
        public String id;
        public String name;
        public String firstName;
        public String lastName;
        public String profilePic;
    }
}
