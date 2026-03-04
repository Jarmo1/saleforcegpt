/**
 * InstagramGraphAPIService
 * Handles outbound calls to the Instagram Graph API for Direct Messages (DMs).
 * Instagram messaging is handled via the same Graph API as Facebook Messenger
 * (Instagram Professional Account linked to a Facebook Page).
 *
 * Prerequisites:
 *  - Named Credential "Instagram_Graph_API" with the Instagram Page Access Token
 *  - instagram_manage_messages permission granted in the Connected App
 */
public with sharing class InstagramGraphAPIService {

    private static final String GRAPH_API_VERSION = 'v19.0';
    private static final String NAMED_CREDENTIAL   = 'callout:Instagram_Graph_API';

    // ─── Send text DM to an Instagram user ───────────────────────────────────

    public static InstagramSendResult sendTextMessage(String recipientId, String messageText) {
        Map<String, Object> payload = new Map<String, Object>{
            'recipient' => new Map<String, Object>{ 'id' => recipientId },
            'message'   => new Map<String, Object>{ 'text' => messageText }
        };
        return sendMessage(payload);
    }

    // ─── Reply with an image ──────────────────────────────────────────────────

    public static InstagramSendResult sendImageMessage(String recipientId, String imageUrl) {
        Map<String, Object> payload = new Map<String, Object>{
            'recipient' => new Map<String, Object>{ 'id' => recipientId },
            'message'   => new Map<String, Object>{
                'attachment' => new Map<String, Object>{
                    'type'    => 'image',
                    'payload' => new Map<String, Object>{ 'url' => imageUrl }
                }
            }
        };
        return sendMessage(payload);
    }

    // ─── Get Instagram user info ──────────────────────────────────────────────

    public static InstagramUserInfo getUserInfo(String userId) {
        String endpoint = NAMED_CREDENTIAL + '/' + GRAPH_API_VERSION + '/'
            + userId + '?fields=name,username,profile_pic';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(10000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 200) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            InstagramUserInfo info = new InstagramUserInfo();
            info.id         = (String) data.get('id');
            info.name       = (String) data.get('name');
            info.username   = (String) data.get('username');
            info.profilePic = (String) data.get('profile_pic');
            return info;
        }
        System.debug(LoggingLevel.ERROR,
            'InstagramGraphAPIService.getUserInfo failed: ' + res.getBody());
        return null;
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static InstagramSendResult sendMessage(Map<String, Object> payload) {
        String endpoint = NAMED_CREDENTIAL + '/' + GRAPH_API_VERSION + '/me/messages';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        InstagramSendResult result = new InstagramSendResult();
        result.statusCode  = res.getStatusCode();
        result.rawResponse = res.getBody();

        if (res.getStatusCode() == 200) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            result.messageId   = (String) data.get('message_id');
            result.recipientId = (String) data.get('recipient_id');
            result.success     = true;
        } else {
            result.success = false;
            System.debug(LoggingLevel.ERROR,
                'InstagramGraphAPIService.sendMessage failed: ' + res.getBody());
        }
        return result;
    }

    // ─── DTOs ─────────────────────────────────────────────────────────────────

    public class InstagramSendResult {
        public Boolean success;
        public Integer statusCode;
        public String  messageId;
        public String  recipientId;
        public String  rawResponse;
    }

    public class InstagramUserInfo {
        public String id;
        public String name;
        public String username;
        public String profilePic;
    }
}
