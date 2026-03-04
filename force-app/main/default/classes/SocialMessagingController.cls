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
     * Returns channel connection status from Social_Channel_Config__c.
     */
    @AuraEnabled(cacheable=true)
    public static List<ChannelStatusWrapper> getChannelStatuses() {
        List<Social_Channel_Config__c> configs = [
            SELECT Id, Name, Platform__c, Is_Active__c, Last_Verified_Date__c, Page_Name__c
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
    }
}
