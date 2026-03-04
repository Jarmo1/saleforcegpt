/**
 * OmniChannelRoutingService
 * Core service that bridges inbound social messages to Salesforce Omni-Channel.
 *
 * Flow:
 *  1. Inbound message arrives via SocialWebhookController
 *  2. Upsert a Contact based on the platform user ID
 *  3. Create / reuse a MessagingSession (or Case)
 *  4. Create a PendingServiceRouting record to push work to Omni-Channel
 *  5. Agents see the work item in the Omni-Channel widget
 */
public with sharing class OmniChannelRoutingService {

    // The DeveloperName of the ServiceChannel for social messaging
    // (defined in force-app/main/default/serviceChannels/)
    private static final String SERVICE_CHANNEL_NAME = 'SocialMessagingChannel';

    // The DeveloperName of the routing configuration queue
    private static final String QUEUE_DEVELOPER_NAME = 'Social_Messaging_Queue';

    // ─── Main entry point ─────────────────────────────────────────────────────

    /**
     * Called by SocialWebhookController when a new inbound message is received.
     * @param platformUserId  The sender's ID on the platform (e.g., Facebook PSID)
     * @param messageText     The text content of the message
     * @param platform        'Facebook' | 'Instagram' | 'WhatsApp'
     * @param externalMsgId   Platform-specific message ID (for deduplication)
     */
    public static void routeInboundMessage(
        String platformUserId,
        String messageText,
        String platform,
        String externalMsgId
    ) {
        // Deduplicate: skip if we've already processed this external message ID
        if (String.isNotBlank(externalMsgId) && isDuplicate(externalMsgId)) {
            return;
        }

        // Upsert the contact
        Contact contact = upsertContact(platformUserId, platform);

        // Find or create an open Case for this conversation
        Case conversationCase = upsertConversationCase(contact, platform, platformUserId);

        // Log the inbound message as a Case Comment
        CaseComment comment = new CaseComment(
            ParentId     = conversationCase.Id,
            CommentBody  = '[' + platform + ' Inbound] ' + messageText,
            IsPublished  = false
        );
        insert comment;

        // Mark external message ID as processed (stored on Case)
        if (String.isNotBlank(externalMsgId)) {
            conversationCase.Last_External_Message_Id__c = externalMsgId;
            update conversationCase;
        }

        // Route to Omni-Channel if the case is not already assigned to an agent
        if (conversationCase.OwnerId == getQueueId()) {
            createPendingServiceRouting(conversationCase);
        }
    }

    // ─── Reply from agent → send back to platform ────────────────────────────

    /**
     * Called from LWC when an agent sends a reply.
     * Routes the message back to the correct platform API.
     */
    @AuraEnabled
    public static void sendReply(Id caseId, String replyText) {
        Case c = [
            SELECT Platform__c, Platform_User_Id__c, ContactId
            FROM Case
            WHERE Id = :caseId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (c.Platform__c == 'Facebook') {
            FacebookGraphAPIService.sendTextMessage(c.Platform_User_Id__c, replyText);
        } else if (c.Platform__c == 'Instagram') {
            InstagramGraphAPIService.sendTextMessage(c.Platform_User_Id__c, replyText);
        }

        // Log outbound message as a public Case Comment
        insert new CaseComment(
            ParentId    = caseId,
            CommentBody = '[' + c.Platform__c + ' Outbound] ' + replyText,
            IsPublished = true
        );
    }

    // ─── Upsert helpers ───────────────────────────────────────────────────────

    private static Contact upsertContact(String platformUserId, String platform) {
        String externalId = platform + '_' + platformUserId;
        List<Contact> existing = [
            SELECT Id, FirstName, LastName, Email
            FROM Contact
            WHERE Social_Platform_Id__c = :externalId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        // Try to fetch name from the platform API
        String displayName = 'Unknown ' + platform + ' User';
        try {
            if (platform == 'Facebook') {
                FacebookGraphAPIService.FacebookUserProfile profile =
                    FacebookGraphAPIService.getUserProfile(platformUserId);
                if (profile != null && String.isNotBlank(profile.name)) {
                    displayName = profile.name;
                }
            } else if (platform == 'Instagram') {
                InstagramGraphAPIService.InstagramUserInfo info =
                    InstagramGraphAPIService.getUserInfo(platformUserId);
                if (info != null && String.isNotBlank(info.name)) {
                    displayName = info.name;
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'Could not fetch profile for ' + platformUserId + ': ' + e.getMessage());
        }

        List<String> nameParts = displayName.split(' ');
        Contact c = new Contact(
            FirstName             = nameParts.size() > 1 ? nameParts[0] : 'Social',
            LastName              = nameParts.size() > 1
                ? String.join(nameParts.subList(1, nameParts.size()), ' ')
                : displayName,
            Social_Platform_Id__c = externalId,
            Social_Platform__c    = platform,
            LeadSource            = 'Social Media'
        );
        insert c;
        return c;
    }

    private static Case upsertConversationCase(Contact contact, String platform, String platformUserId) {
        // Look for an open case for this platform user
        List<Case> openCases = [
            SELECT Id, OwnerId, Status, Platform__c, Platform_User_Id__c, Last_External_Message_Id__c
            FROM Case
            WHERE ContactId           = :contact.Id
              AND Platform__c         = :platform
              AND Status             != 'Closed'
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!openCases.isEmpty()) {
            return openCases[0];
        }

        // Create a new case and assign to the social messaging queue
        Id queueId = getQueueId();
        Case newCase = new Case(
            ContactId         = contact.Id,
            Subject           = 'Inbound ' + platform + ' Message',
            Status            = 'New',
            Origin            = 'Social Media',
            Platform__c       = platform,
            Platform_User_Id__c = platformUserId,
            OwnerId           = queueId
        );
        insert newCase;
        return newCase;
    }

    // ─── Omni-Channel routing ─────────────────────────────────────────────────

    private static void createPendingServiceRouting(Case c) {
        ServiceChannel channel = [
            SELECT Id
            FROM ServiceChannel
            WHERE DeveloperName = :SERVICE_CHANNEL_NAME
            LIMIT 1
        ];

        PendingServiceRouting psr = new PendingServiceRouting(
            CapacityWeight     = 1,
            IsReadyForRouting  = true,
            RoutingModel       = 'LeastActive',
            RoutingPriority    = 1,
            ServiceChannelId   = channel.Id,
            WorkItemId         = c.Id
        );
        insert psr;
    }

    // ─── Utility ──────────────────────────────────────────────────────────────

    private static Id getQueueId() {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type          = 'Queue'
              AND DeveloperName = :QUEUE_DEVELOPER_NAME
            LIMIT 1
        ];
        return queues.isEmpty() ? UserInfo.getUserId() : queues[0].Id;
    }

    private static Boolean isDuplicate(String externalMsgId) {
        return [
            SELECT COUNT()
            FROM Case
            WHERE Last_External_Message_Id__c = :externalMsgId
        ] > 0;
    }
}
