import { LightningElement, wire } from 'lwc';
import getChannelStatuses from '@salesforce/apex/SocialMessagingController.getChannelStatuses';

const PLATFORM_ICONS = {
    Facebook  : 'utility:like',
    Instagram : 'utility:photo',
    WhatsApp  : 'utility:chat',
    Twitter   : 'utility:twitter'
};

export default class ChannelStatusPanel extends LightningElement {

    isLoading = true;
    channels  = [];

    @wire(getChannelStatuses)
    wiredChannels({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.channels = data.map(ch => ({
                ...ch,
                icon        : PLATFORM_ICONS[ch.platform] ?? 'utility:connected_apps',
                iconClass   : ch.isActive ? 'icon-active' : 'icon-inactive',
                cardClass   : 'channel-card slds-box slds-box_xx-small'
                    + (ch.isActive ? ' channel-active' : ' channel-inactive'),
                statusLabel : ch.isActive ? 'Connected' : 'Disconnected',
                badgeClass  : ch.isActive ? 'badge-connected' : 'badge-disconnected'
            }));
        }
    }
}
