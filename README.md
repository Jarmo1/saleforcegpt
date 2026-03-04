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
│   ├── FacebookGraphAPIService.cls            # Outbound Facebook Messenger Graph API calls
│   ├── InstagramGraphAPIService.cls           # Outbound Instagram API (graph.instagram.com)
│   ├── InstagramOAuthService.cls              # Instagram Login OAuth 2.0 flow + token refresh
│   ├── InstagramTokenRefreshScheduler.cls     # Scheduled Apex: refreshes tokens daily
│   ├── SocialWebhookController.cls            # REST webhook (GET verify + POST events)
│   ├── OmniChannelRoutingService.cls          # Routes messages → Contact → Case → Omni-Channel
│   ├── SocialMessagingController.cls          # AuraEnabled controller for LWC
│   └── SocialWebhookControllerTest.cls        # Unit tests
├── lwc/
│   ├── socialMessagingDashboard/              # Main agent dashboard (App Builder component)
│   ├── conversationThread/                    # Per-conversation message thread
│   ├── messageComposer/                       # Reply textarea + send button
│   └── channelStatusPanel/                    # Shows connected/disconnected channels + token status
├── objects/
│   ├── Case/fields/
│   │   ├── Platform__c                        # Facebook | Instagram | WhatsApp | Twitter
│   │   ├── Platform_User_Id__c                # Sender's platform ID (IGSID for Instagram)
│   │   └── Last_External_Message_Id__c        # For deduplication
│   ├── Contact/fields/
│   │   ├── Social_Platform_Id__c              # Unique: "Facebook_12345"
│   │   └── Social_Platform__c
│   └── Social_Channel_Config__c/fields/
│       ├── Platform__c                        # Facebook | Instagram | etc.
│       ├── Is_Active__c                       # Active flag
│       ├── Page_Name__c                       # Display name / username
│       ├── Webhook_Verify_Token__c            # Webhook hub.challenge token
│       ├── Instagram_App_Id__c                # Meta App ID (for OAuth URL)
│       ├── App_Secret__c                      # Meta App Secret (webhook sig validation)
│       ├── OAuth_Redirect_Uri__c              # Callback URL registered in Meta App
│       ├── Access_Token__c                    # Long-lived Instagram User Access Token
│       └── Token_Expiry_Date__c              # Token expiry (60 days from issue)
├── serviceChannels/
│   └── SocialMessagingChannel                 # Omni-Channel service channel (Case)
├── queueRoutingConfigs/
│   └── Social_Messaging_Routing               # LeastActive routing, 120s timeout
├── queues/
│   └── Social_Messaging_Queue                 # Incoming social cases queue
├── namedCredentials/
│   ├── Facebook_Graph_API                     # https://graph.facebook.com + Bearer token
│   ├── Instagram_Graph_API                    # https://graph.instagram.com + Bearer token
│   └── Instagram_OAuth_API                    # https://api.instagram.com (no auth)
├── connectedApps/
│   └── OmniChannelSocialApp
└── permissionsets/
    ├── OmniChannelSocialAgent                 # Read access for agents
    └── OmniChannelSocialAdmin                 # Full access for admins
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| Salesforce Edition | Enterprise, Unlimited, or Developer |
| Feature Licences | **Digital Engagement** or **Omni-Channel** add-on |
| Meta Developer Account | [developers.facebook.com](https://developers.facebook.com) — Business app type |
| Facebook App | `pages_messaging` permission for Messenger |
| Instagram Professional Account | Business or Creator account (**no Facebook Page link required** for Instagram Login API) |
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

### 4. Configure Facebook Named Credential
Go to **Setup → Named Credentials → Facebook Graph API**:
- Set a custom `Authorization` header: `Bearer {YOUR_FACEBOOK_PAGE_ACCESS_TOKEN}`

---

## Instagram Setup (Instagram API with Instagram Login)

> This app uses the **Instagram API with Instagram Login** (launched July 2024).
> The old Messenger-for-Instagram approach (requiring a Facebook Page) is being deprecated.

### Step 1 — Create a Meta App
1. Go to [developers.facebook.com](https://developers.facebook.com) → **My Apps → Create App**
2. Select **Business** type
3. Add the **Instagram** product
4. Note your **App ID** and **App Secret**

### Step 2 — Configure the Social_Channel_Config__c record
Update your Instagram config record with:
```
Instagram_App_Id__c     = '1234567890'         (your Meta App ID)
App_Secret__c           = 'abc123...'          (your Meta App Secret)
OAuth_Redirect_Uri__c   = 'https://YOUR_SITE.force.com/services/apexrest/social/oauth/callback'
Webhook_Verify_Token__c = 'some_secure_token'
```

### Step 3 — Register the Redirect URI in the Meta App
In the Meta App Dashboard → **Instagram → Settings**:
- Add the `OAuth_Redirect_Uri__c` value as a valid OAuth Redirect URI

### Step 4 — Run the OAuth flow
Call `SocialMessagingController.getInstagramAuthUrl(configId)` from an admin UI or:
```bash
sf apex run --target-org my-org <<'EOF'
Id configId = [SELECT Id FROM Social_Channel_Config__c
               WHERE Platform__c = 'Instagram' LIMIT 1].Id;
String url = SocialMessagingController.getInstagramAuthUrl(configId);
System.debug('Open this URL in a browser: ' + url);
EOF
```
Open the returned URL in a browser, grant permissions, and the callback will exchange the code for a long-lived token stored in `Access_Token__c`.

### Step 5 — Configure Named Credential
**Setup → Named Credentials → Instagram Graph API:**
- URL: `https://graph.instagram.com`
- Protocol: Custom (No Authentication)
- Add custom header: `Authorization` → `Bearer {value from Access_Token__c}`

### Step 6 — Required Meta App Permissions
Request these in **App Review**:
| Permission | Purpose |
|---|---|
| `instagram_business_basic` | Read account info |
| `instagram_manage_messages` | Send and receive DMs |

### Step 7 — Register Instagram Webhook
In Meta App Dashboard → **Webhooks → Instagram**:
| Field | Value |
|---|---|
| Callback URL | `https://YOUR_SITE.force.com/services/apexrest/social/webhook` |
| Verify Token | `Webhook_Verify_Token__c` value |
| Subscribe fields | `messages`, `messaging_reactions` |

### Step 8 — Register Facebook Messenger Webhook (if using Facebook too)
Same callback URL, same verify token, subscribe to: `messages`, `messaging_postbacks`, `message_reads`

---

## Assign Permission Sets
```bash
sf org assign permset --name OmniChannelSocialAgent --target-org my-org
sf org assign permset --name OmniChannelSocialAdmin --target-org my-org
```

## Add Dashboard to Lightning App
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

## Token Refresh (Automatic)

Instagram long-lived tokens expire after **60 days**. The `InstagramTokenRefreshScheduler` runs daily at 2 AM and refreshes any token expiring within 7 days. It is registered automatically by the setup script.

To check scheduled jobs:
```bash
sf apex run --target-org my-org <<'EOF'
System.debug([SELECT Id, CronJobDetail.Name, State, NextFireTime
              FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Instagram%']);
EOF
```

---

## Supported Platforms

| Platform | Inbound | Outbound | API |
|---|---|---|---|
| Facebook Messenger | ✅ | ✅ | graph.facebook.com — Page Access Token |
| Instagram DM | ✅ | ✅ | graph.instagram.com — Instagram Login (no FB Page needed) |
| WhatsApp Business | ⚠️ | ⚠️ | Config ready, API integration pending |
| Twitter / X DM | ⚠️ | ⚠️ | Config ready, API integration pending |

---

## Security Considerations

- **Never commit** access tokens or app secrets to source control.
- `App_Secret__c`, `Access_Token__c` fields — restrict FLS to Admins only in Salesforce.
- All SOQL uses `WITH SECURITY_ENFORCED` to enforce object/field-level sharing.
- `SocialWebhookController` validates `X-Hub-Signature-256` when `App_Secret__c` is set — always configure this in production.
- Instagram OAuth uses the `state` parameter set to the `Social_Channel_Config__c` ID for CSRF protection.
