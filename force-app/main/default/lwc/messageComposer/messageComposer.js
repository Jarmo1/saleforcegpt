import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import sendReply from '@salesforce/apex/SocialMessagingController.sendReply';

export default class MessageComposer extends LightningElement {

    @api caseId;
    @api platform;

    @track replyText  = '';
    @track isSending  = false;

    get placeholderText() {
        return `Type a message to send via ${this.platform ?? 'social'}…`;
    }

    get isSendDisabled() {
        return this.isSending || !this.replyText.trim();
    }

    handleTextChange(event) {
        this.replyText = event.detail.value;
    }

    // Ctrl+Enter to send
    handleKeyDown(event) {
        if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
            this.handleSend();
        }
    }

    handleSend() {
        const text = this.replyText.trim();
        if (!text || this.isSending) return;

        this.isSending = true;
        sendReply({ caseId: this.caseId, replyText: text })
            .then(() => {
                this.replyText = '';
                this.isSending = false;
                this.dispatchEvent(new CustomEvent('sent'));
            })
            .catch(error => {
                this.isSending = false;
                this.dispatchEvent(new ShowToastEvent({
                    title   : 'Send failed',
                    message : error.body?.message ?? 'Unable to send message.',
                    variant : 'error'
                }));
            });
    }
}
