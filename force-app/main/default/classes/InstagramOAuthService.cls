/**
 * InstagramOAuthService
 * Manages the Instagram Login OAuth 2.0 flow for the Instagram API with Instagram Login.
 *
 * Flow overview:
 * ┌──────────┐  1. Redirect to auth URL     ┌──────────────────────┐
 * │  Admin   │ ─────────────────────────── ▶ │ api.instagram.com    │
 * │  Browser │ ◀ ───────────────────────── │ /oauth/authorize     │
 * └──────────┘  2. Callback with ?code=...  └──────────────────────┘
 *       │
 *       │ 3. exchangeCodeForShortLivedToken()
 *       ▼
 * ┌──────────────────────────┐
 * │  api.instagram.com       │  → short-lived token (1 hour)
 * │  /oauth/access_token     │
 * └──────────────────────────┘
 *       │
 *       │ 4. exchangeForLongLivedToken()
 *       ▼
 * ┌──────────────────────────┐
 * │  graph.instagram.com     │  → long-lived token (60 days)
 * │  /access_token           │
 * └──────────────────────────┘
 *       │
 *       │ 5. Store in Social_Channel_Config__c
 *       ▼
 * ┌──────────────────────────┐
 * │  Named Credential update │  (manual step — admin pastes token)
 * └──────────────────────────┘
 *
 * Required Meta App scopes:
 *   instagram_business_basic
 *   instagram_manage_messages
 *
 * Named Credentials needed:
 *   Instagram_OAuth_API  → https://api.instagram.com
 *   Instagram_Graph_API  → https://graph.instagram.com
 */
public with sharing class InstagramOAuthService {

    private static final String OAUTH_NC    = 'callout:Instagram_OAuth_API';
    private static final String GRAPH_NC    = 'callout:Instagram_Graph_API';
    private static final String API_VERSION = 'v21.0';

    // Scopes required for Instagram messaging
    public static final String REQUIRED_SCOPES =
        'instagram_business_basic,instagram_manage_messages';

    // ─── Step 1: Build the authorization URL ──────────────────────────────────

    /**
     * Returns the URL to redirect the admin to in order to begin OAuth.
     *
     * @param appId        Instagram App ID from Meta App Dashboard
     * @param redirectUri  The Salesforce Site URL callback registered in the Meta App
     * @param state        CSRF token / state parameter (store in session before redirect)
     */
    public static String buildAuthorizationUrl(
        String appId,
        String redirectUri,
        String state
    ) {
        return 'https://api.instagram.com/oauth/authorize'
            + '?client_id='     + EncodingUtil.urlEncode(appId, 'UTF-8')
            + '&redirect_uri='  + EncodingUtil.urlEncode(redirectUri, 'UTF-8')
            + '&scope='         + EncodingUtil.urlEncode(REQUIRED_SCOPES, 'UTF-8')
            + '&response_type=code'
            + '&state='         + EncodingUtil.urlEncode(state, 'UTF-8');
    }

    // ─── Step 2: Exchange auth code → short-lived token ───────────────────────

    /**
     * Calls api.instagram.com/oauth/access_token.
     * Returns a short-lived token valid for 1 hour.
     *
     * @param appId       Instagram App ID
     * @param appSecret   Instagram App Secret (store only in Social_Channel_Config__c)
     * @param redirectUri Must exactly match the URI used in Step 1
     * @param code        The ?code= value from the OAuth callback
     */
    public static TokenExchangeResult exchangeCodeForShortLivedToken(
        String appId,
        String appSecret,
        String redirectUri,
        String code
    ) {
        String body = 'client_id='     + EncodingUtil.urlEncode(appId, 'UTF-8')
            + '&client_secret='        + EncodingUtil.urlEncode(appSecret, 'UTF-8')
            + '&grant_type=authorization_code'
            + '&redirect_uri='         + EncodingUtil.urlEncode(redirectUri, 'UTF-8')
            + '&code='                 + EncodingUtil.urlEncode(code, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(OAUTH_NC + '/oauth/access_token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(body);
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        return parseTokenResponse(res, true);
    }

    // ─── Step 3: Exchange short-lived → long-lived token (60 days) ───────────

    /**
     * Calls graph.instagram.com/access_token with grant_type=ig_exchange_token.
     * The returned long-lived token is valid for 60 days and can be refreshed.
     */
    public static TokenExchangeResult exchangeForLongLivedToken(
        String appSecret,
        String shortLivedToken
    ) {
        String endpoint = GRAPH_NC + '/access_token'
            + '?grant_type=ig_exchange_token'
            + '&client_secret=' + EncodingUtil.urlEncode(appSecret, 'UTF-8')
            + '&access_token='  + EncodingUtil.urlEncode(shortLivedToken, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        return parseTokenResponse(res, false);
    }

    // ─── Step 4: Refresh a long-lived token before it expires ────────────────

    /**
     * Long-lived tokens expire after 60 days.
     * Call this at least once every 60 days (a scheduled Apex job is recommended).
     * Calls GET graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token
     */
    public static TokenExchangeResult refreshLongLivedToken(String longLivedToken) {
        String endpoint = GRAPH_NC + '/refresh_access_token'
            + '?grant_type=ig_refresh_token'
            + '&access_token=' + EncodingUtil.urlEncode(longLivedToken, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        return parseTokenResponse(res, false);
    }

    // ─── Persist token to Social_Channel_Config__c ────────────────────────────

    /**
     * Stores the long-lived token and expiry in the Social_Channel_Config__c record.
     * Also fetches and stores the Instagram Account ID from /me.
     *
     * @param configId   ID of the Social_Channel_Config__c record for this Instagram account
     * @param token      The long-lived Instagram User Access Token
     * @param expiresIn  Seconds until expiry (typically 5183944 ≈ 60 days)
     */
    public static void persistToken(Id configId, String token, Integer expiresIn) {
        Social_Channel_Config__c cfg = new Social_Channel_Config__c(
            Id                    = configId,
            Access_Token__c       = token,
            Token_Expiry_Date__c  = DateTime.now().addSeconds(expiresIn),
            Is_Active__c          = true,
            Last_Verified_Date__c = DateTime.now()
        );
        update cfg;
    }

    // ─── Check if a token needs refreshing ────────────────────────────────────

    /**
     * Returns true if the stored token will expire within the next 7 days.
     * Use this in a Scheduled Apex to proactively refresh tokens.
     */
    public static Boolean needsRefresh(Social_Channel_Config__c config) {
        if (config.Token_Expiry_Date__c == null) return true;
        return config.Token_Expiry_Date__c < DateTime.now().addDays(7);
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static TokenExchangeResult parseTokenResponse(HttpResponse res, Boolean isShortLived) {
        TokenExchangeResult result = new TokenExchangeResult();
        result.statusCode  = res.getStatusCode();
        result.rawResponse = res.getBody();

        if (res.getStatusCode() == 200) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            result.success      = true;
            result.accessToken  = (String)  data.get('access_token');
            result.tokenType    = (String)  data.get('token_type');
            result.isShortLived = isShortLived;

            Object exp = data.get('expires_in');
            result.expiresIn = (exp != null) ? Integer.valueOf(String.valueOf(exp)) : null;
        } else {
            result.success      = false;
            System.debug(LoggingLevel.ERROR,
                'InstagramOAuthService token exchange error '
                + res.getStatusCode() + ': ' + res.getBody());
        }
        return result;
    }

    // ─── DTOs ─────────────────────────────────────────────────────────────────

    public class TokenExchangeResult {
        public Boolean success;
        public Integer statusCode;
        public String  accessToken;
        public String  tokenType;
        public Integer expiresIn;      // seconds; null for short-lived if not returned
        public Boolean isShortLived;
        public String  rawResponse;
    }
}
