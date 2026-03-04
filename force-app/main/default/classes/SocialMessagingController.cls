/**
 * SocialMessagingController
 * AuraEnabled controller methods consumed by the socialMessagingDashboard LWC.
 */
public with sharing class SocialMessagingController {

    // ─── Dashboard data ───────────────────────────────────────────────────────

    /**
     * Returns open social messaging cases for the current user's queue(s).
     */
    @AuraEnabled(cacheable=true)
    public static List<CaseWrapper> getOpenSocialCases() {
        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Status, Platform__c,
                   Platform_User_Id__c, CreatedDate,
                   Contact.Name, Contact.Social_Platform__c
            FROM Case
            WHERE Origin  = 'Social Media'
              AND Status != 'Closed'
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];

        List<CaseWrapper> wrappers = new List<CaseWrapper>();
        for (Case c : cases) {
            CaseWrapper w = new CaseWrapper();
            w.id           = c.Id;
            w.caseNumber   = c.CaseNumber;
            w.subject      = c.Subject;
            w.status       = c.Status;
            w.platform     = c.Platform__c;
            w.contactName  = c.Contact != null ? c.Contact.Name : 'Unknown';
            w.createdDate  = c.CreatedDate;
            wrappers.add(w);
        }
        return wrappers;
    }

    /**
     * Returns the message thread (Case Comments) for a given Case.
     */
    @AuraEnabled(cacheable=false)
    public static List<MessageWrapper> getMessageThread(Id caseId) {
        List<CaseComment> comments = [
            SELECT Id, CommentBody, CreatedDate, IsPublished, CreatedBy.Name
            FROM CaseComment
            WHERE ParentId = :caseId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];

        List<MessageWrapper> messages = new List<MessageWrapper>();
        for (CaseComment cc : comments) {
            MessageWrapper m = new MessageWrapper();
            m.id          = cc.Id;
            m.body        = cc.CommentBody;
            m.createdDate = cc.CreatedDate;
            m.isOutbound  = cc.IsPublished;
            m.authorName  = cc.CreatedBy.Name;
            messages.add(m);
        }
        return messages;
    }

    /**
     * Sends a reply from the agent back to the platform.
     */
    @AuraEnabled
    public static void sendReply(Id caseId, String replyText) {
        OmniChannelRoutingService.sendReply(caseId, replyText);
    }

    /**
     * Closes a conversation Case.
     */
    @AuraEnabled
    public static void closeConversation(Id caseId) {
        Case c = new Case(Id = caseId, Status = 'Closed');
        update c;
    }

    /**
     * Builds the Instagram OAuth authorization URL for an admin to connect
     * an Instagram Business account via Instagram Login (Instagram API with Instagram Login).
     *
     * The Social_Channel_Config__c record must have Instagram_App_Id__c and
     * OAuth_Redirect_Uri__c populated before calling this.
     *
     * The returned URL should be opened in a browser (window.open / NavigationMixin).
     * After the user grants permission Instagram redirects back to OAuth_Redirect_Uri__c
     * with ?code=... which must be handled by the SocialOAuthCallbackController.
     */
    @AuraEnabled
    public static String getInstagramAuthUrl(Id configId) {
        Social_Channel_Config__c cfg = [
            SELECT Instagram_App_Id__c, OAuth_Redirect_Uri__c
            FROM Social_Channel_Config__c
            WHERE Id = :configId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (String.isBlank(cfg.Instagram_App_Id__c)) {
            throw new AuraHandledException(
                'Instagram App ID is not set on this channel config record.'
            );
        }
        if (String.isBlank(cfg.OAuth_Redirect_Uri__c)) {
            throw new AuraHandledException(
                'OAuth Redirect URI is not set on this channel config record.'
            );
        }
        return InstagramOAuthService.buildAuthorizationUrl(
            cfg.Instagram_App_Id__c,
            cfg.OAuth_Redirect_Uri__c,
            String.valueOf(configId)   // state param used as CSRF token
        );
    }

    /**
     * Returns channel connection status from Social_Channel_Config__c.
     * Includes token expiry info so the dashboard can warn about expiring tokens.
     */
    @AuraEnabled(cacheable=true)
    public static List<ChannelStatusWrapper> getChannelStatuses() {
        List<Social_Channel_Config__c> configs = [
            SELECT Id, Name, Platform__c, Is_Active__c, Last_Verified_Date__c,
                   Page_Name__c, Token_Expiry_Date__c
            FROM Social_Channel_Config__c
            WITH SECURITY_ENFORCED
            ORDER BY Platform__c
        ];

        List<ChannelStatusWrapper> statuses = new List<ChannelStatusWrapper>();
        for (Social_Channel_Config__c cfg : configs) {
            ChannelStatusWrapper s = new ChannelStatusWrapper();
            s.id               = cfg.Id;
            s.name             = cfg.Name;
            s.platform         = cfg.Platform__c;
            s.isActive         = cfg.Is_Active__c;
            s.lastVerifiedDate = cfg.Last_Verified_Date__c;
            s.pageName         = cfg.Page_Name__c;
            s.tokenExpiryDate  = cfg.Token_Expiry_Date__c;
            s.tokenExpiringSoon = cfg.Token_Expiry_Date__c != null
                && cfg.Token_Expiry_Date__c < DateTime.now().addDays(7);
            statuses.add(s);
        }
        return statuses;
    }

    // ─── Wrapper classes ──────────────────────────────────────────────────────

    public class CaseWrapper {
        @AuraEnabled public Id       id;
        @AuraEnabled public String   caseNumber;
        @AuraEnabled public String   subject;
        @AuraEnabled public String   status;
        @AuraEnabled public String   platform;
        @AuraEnabled public String   contactName;
        @AuraEnabled public DateTime createdDate;
    }

    public class MessageWrapper {
        @AuraEnabled public Id       id;
        @AuraEnabled public String   body;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Boolean  isOutbound;
        @AuraEnabled public String   authorName;
    }

    public class ChannelStatusWrapper {
        @AuraEnabled public Id       id;
        @AuraEnabled public String   name;
        @AuraEnabled public String   platform;
        @AuraEnabled public Boolean  isActive;
        @AuraEnabled public DateTime lastVerifiedDate;
        @AuraEnabled public String   pageName;
        @AuraEnabled public DateTime tokenExpiryDate;
        @AuraEnabled public Boolean  tokenExpiringSoon;
    }
}
