# Omni-Channel Social Messaging for Salesforce

Connect **Facebook Messenger** and **Instagram DMs** (and more) to Salesforce **Omni-Channel** so agents can handle all social conversations in one unified agent workspace.

---

## Architecture

```
Facebook / Instagram
        │
        │  Webhooks (POST)
        ▼
Salesforce Sites / Experience Cloud
  └── SocialWebhookController (REST Apex)
          │
          ▼
   OmniChannelRoutingService
     ├── Upsert Contact  (Social_Platform_Id__c)
     ├── Upsert Case     (Platform__c, Platform_User_Id__c)
     ├── Log CaseComment (message thread)
     └── PendingServiceRouting → Omni-Channel Queue
                                       │
                                       ▼
                              Agent receives work item
                              via Omni-Channel widget
                                       │
                                       ▼
                         socialMessagingDashboard (LWC)
                           └── conversationThread
                                 └── messageComposer
                                       │
                                       ▼
                       FacebookGraphAPIService / InstagramGraphAPIService
                                       │
                                       ▼
                          Message delivered to customer
```

---

## Project Structure

```
force-app/main/default/
├── classes/
│   ├── FacebookGraphAPIService.cls          # Outbound Facebook Graph API calls
│   ├── InstagramGraphAPIService.cls         # Outbound Instagram Graph API calls
│   ├── SocialWebhookController.cls          # REST endpoint for webhooks (GET + POST)
│   ├── OmniChannelRoutingService.cls        # Routes messages to Omni-Channel
│   ├── SocialMessagingController.cls        # AuraEnabled controller for LWC
│   └── SocialWebhookControllerTest.cls      # Unit tests
├── lwc/
│   ├── socialMessagingDashboard/            # Main agent dashboard (App Builder component)
│   ├── conversationThread/                  # Per-conversation message thread
│   ├── messageComposer/                     # Reply text area + send button
│   └── channelStatusPanel/                  # Shows connected/disconnected channels
├── objects/
│   ├── Case/fields/
│   │   ├── Platform__c                      # Facebook | Instagram | WhatsApp | Twitter
│   │   ├── Platform_User_Id__c              # Sender's ID on the platform
│   │   └── Last_External_Message_Id__c      # For deduplication
│   ├── Contact/fields/
│   │   ├── Social_Platform_Id__c            # Unique: "Facebook_12345"
│   │   └── Social_Platform__c
│   └── Social_Channel_Config__c/            # Channel config & webhook tokens
├── serviceChannels/
│   └── SocialMessagingChannel               # Omni-Channel service channel (Case)
├── queueRoutingConfigs/
│   └── Social_Messaging_Routing             # LeastActive routing, 120s timeout
├── queues/
│   └── Social_Messaging_Queue               # Queue for incoming social cases
├── namedCredentials/
│   ├── Facebook_Graph_API                   # Graph API base URL + auth
│   └── Instagram_Graph_API
├── connectedApps/
│   └── OmniChannelSocialApp
└── permissionsets/
    ├── OmniChannelSocialAgent               # Read access for agents
    └── OmniChannelSocialAdmin               # Full access for admins
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| Salesforce Edition | Enterprise, Unlimited, or Developer |
| Feature Licences | **Digital Engagement** or **Omni-Channel** add-on |
| Facebook App | Created at [developers.facebook.com](https://developers.facebook.com) with `pages_messaging` permission |
| Instagram Professional Account | Linked to a Facebook Page |
| Salesforce CLI | `sf` (v2+) |

---

## Deployment

### 1. Authenticate your org
```bash
sf org login web --alias my-org
```

### 2. Deploy
```bash
./scripts/shell/deploy.sh my-org
```

### 3. Seed sample channel data
```bash
sf apex run --file scripts/apex/setup-sample-data.apex --target-org my-org
```

### 4. Configure Named Credentials
Go to **Setup → Security → Named Credentials**:
- **Facebook Graph API** → add your Facebook Page Access Token
- **Instagram Graph API** → add your Instagram Page Access Token

### 5. Register Webhooks in Meta App Dashboard
| Field | Value |
|---|---|
| Callback URL | `https://YOUR_SITE.force.com/services/apexrest/social/webhook` |
| Verify Token | Value from `Social_Channel_Config__c.Webhook_Verify_Token__c` |
| Subscribed Fields | `messages`, `messaging_postbacks`, `message_reads` |

### 6. Assign Permission Sets
```bash
# Agents
sf org assign permset --name OmniChannelSocialAgent --target-org my-org

# Admins
sf org assign permset --name OmniChannelSocialAdmin --target-org my-org
```

### 7. Add Dashboard to Lightning App
1. Open **App Builder** in Setup
2. Create or edit a Lightning App Page
3. Drag **Social Messaging Dashboard** onto the page
4. Activate the page

---

## Supported Platforms

| Platform | Inbound | Outbound | Status |
|---|---|---|---|
| Facebook Messenger | ✅ | ✅ | Supported |
| Instagram DM | ✅ | ✅ | Supported |
| WhatsApp Business | ⚠️ | ⚠️ | Configuration ready, API integration pending |
| Twitter / X DM | ⚠️ | ⚠️ | Configuration ready, API integration pending |

---

## Testing

```bash
sf apex run test \
  --class-names SocialWebhookControllerTest \
  --result-format human \
  --target-org my-org
```

---

## Security Considerations

- **Never commit** Page Access Tokens to source control — configure them in Named Credentials after deployment.
- The webhook verify token is stored in `Social_Channel_Config__c` — restrict field-level security to admins only.
- All SOQL uses `WITH SECURITY_ENFORCED` to enforce sharing rules.
- The webhook endpoint is public (Salesforce Sites) — Facebook/Instagram signature validation is recommended for production (add `X-Hub-Signature-256` check in `SocialWebhookController`).
