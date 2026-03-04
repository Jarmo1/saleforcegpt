import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getOpenSocialCases from '@salesforce/apex/SocialMessagingController.getOpenSocialCases';
import closeConversation  from '@salesforce/apex/SocialMessagingController.closeConversation';

const PLATFORM_BADGE_CLASSES = {
    Facebook  : 'slds-badge slds-badge_lightest badge-facebook',
    Instagram : 'slds-badge slds-badge_lightest badge-instagram',
    WhatsApp  : 'slds-badge slds-badge_lightest badge-whatsapp'
};

export default class SocialMessagingDashboard extends LightningElement {

    @track selectedCaseId       = null;
    @track selectedPlatformName = null;
    @track selectedPlatform     = 'All';
    @track isLoadingCases       = false;

    _casesResult; // for refreshApex

    platformOptions = [
        { label: 'All Platforms', value: 'All' },
        { label: 'Facebook',      value: 'Facebook' },
        { label: 'Instagram',     value: 'Instagram' },
        { label: 'WhatsApp',      value: 'WhatsApp' }
    ];

    // ─── Wire: open cases ─────────────────────────────────────────────────────

    @wire(getOpenSocialCases)
    wiredCases(result) {
        this._casesResult = result;
    }

    get filteredCases() {
        if (!this._casesResult || !this._casesResult.data) return [];
        const cases = this._casesResult.data;
        return (this.selectedPlatform === 'All'
            ? cases
            : cases.filter(c => c.platform === this.selectedPlatform)
        ).map(c => ({
            ...c,
            listItemClass    : 'conversation-item slds-p-around_small'
                + (c.id === this.selectedCaseId ? ' is-selected' : ''),
            platformBadgeClass : PLATFORM_BADGE_CLASSES[c.platform] || 'slds-badge'
        }));
    }

    get hasCases()      { return this.filteredCases.length > 0; }
    get openCaseCount() { return this._casesResult?.data?.length ?? 0; }

    // ─── Handlers ─────────────────────────────────────────────────────────────

    handlePlatformFilter(event) {
        this.selectedPlatform = event.detail.value;
    }

    handleSelectCase(event) {
        const caseId = event.currentTarget.dataset.id;
        const selected = (this._casesResult?.data ?? []).find(c => c.id === caseId);
        this.selectedCaseId       = caseId;
        this.selectedPlatformName = selected ? selected.platform : null;
    }

    handleCloseConversation(event) {
        const caseId = event.detail.caseId;
        closeConversation({ caseId })
            .then(() => {
                this.selectedCaseId       = null;
                this.selectedPlatformName = null;
                return refreshApex(this._casesResult);
            })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title   : 'Conversation closed',
                    message : 'The conversation has been closed successfully.',
                    variant : 'success'
                }));
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title   : 'Error',
                    message : error.body?.message ?? 'Unable to close the conversation.',
                    variant : 'error'
                }));
            });
    }

    // Auto-refresh every 30 seconds
    connectedCallback() {
        this._refreshInterval = setInterval(() => {
            refreshApex(this._casesResult);
        }, 30000);
    }

    disconnectedCallback() {
        clearInterval(this._refreshInterval);
    }
}
