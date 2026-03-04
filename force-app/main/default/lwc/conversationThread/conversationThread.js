import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMessageThread from '@salesforce/apex/SocialMessagingController.getMessageThread';

const PLATFORM_ICONS = {
    Facebook  : 'utility:like',
    Instagram : 'utility:photo',
    WhatsApp  : 'utility:chat'
};

export default class ConversationThread extends LightningElement {

    @api caseId;
    @api platform;

    @track messages       = [];
    @track isLoadingMessages = true;
    @track contactName    = '';
    @track caseNumber     = '';

    _pollInterval;

    // ─── Wire: message thread ─────────────────────────────────────────────────

    @wire(getMessageThread, { caseId: '$caseId' })
    wiredMessages({ data, error }) {
        this.isLoadingMessages = false;
        if (data) {
            this.messages = data.map(m => ({
                ...m,
                bubbleClass      : m.isOutbound ? 'msg-bubble msg-outbound' : 'msg-bubble msg-inbound',
                bubbleInnerClass : m.isOutbound ? 'bubble-inner outbound-inner' : 'bubble-inner inbound-inner',
                formattedDate    : new Date(m.createdDate).toLocaleString()
            }));
            this.scrollToBottom();
        } else if (error) {
            this.showError('Failed to load messages: ' + (error.body?.message ?? error));
        }
    }

    // ─── Computed ─────────────────────────────────────────────────────────────

    get platformIcon() {
        return PLATFORM_ICONS[this.platform] ?? 'utility:chat';
    }

    get hasMessages() {
        return this.messages.length > 0;
    }

    // ─── Handlers ─────────────────────────────────────────────────────────────

    handleRefresh() {
        this.isLoadingMessages = true;
        // Trigger wire re-evaluation
        getMessageThread({ caseId: this.caseId })
            .then(data => {
                this.isLoadingMessages = false;
                this.messages = data.map(m => ({
                    ...m,
                    bubbleClass      : m.isOutbound ? 'msg-bubble msg-outbound' : 'msg-bubble msg-inbound',
                    bubbleInnerClass : m.isOutbound ? 'bubble-inner outbound-inner' : 'bubble-inner inbound-inner',
                    formattedDate    : new Date(m.createdDate).toLocaleString()
                }));
                this.scrollToBottom();
            })
            .catch(err => {
                this.isLoadingMessages = false;
                this.showError(err.body?.message ?? 'Refresh failed');
            });
    }

    handleMessageSent() {
        this.handleRefresh();
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', {
            detail: { caseId: this.caseId }
        }));
    }

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    connectedCallback() {
        // Poll for new messages every 15 seconds
        this._pollInterval = setInterval(() => this.handleRefresh(), 15000);
    }

    disconnectedCallback() {
        clearInterval(this._pollInterval);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    scrollToBottom() {
        requestAnimationFrame(() => {
            const body = this.refs?.threadBody;
            if (body) body.scrollTop = body.scrollHeight;
        });
    }

    showError(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }
}
