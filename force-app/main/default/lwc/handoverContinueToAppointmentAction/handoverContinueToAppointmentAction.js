import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getHandoverContext from '@salesforce/apex/HandoverWorkspaceController.getHandoverContext';
import proceedToAppointment from '@salesforce/apex/HandoverWorkspaceController.proceedToAppointment';

export default class HandoverContinueToAppointmentAction extends LightningElement {
    _recordId;
    _hasLoaded = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && !this._hasLoaded) {
            this.loadContext();
        }
    }

    @track isLoading = true;
    @track isSubmitting = false;
    @track canProceed = false;
    @track blockingReason = '';
    @track handoverName = '';

    connectedCallback() {
        if (this._recordId && !this._hasLoaded) {
            this.loadContext();
        }
    }

    async loadContext() {
        if (!this._recordId) return;
        this._hasLoaded = true;
        this.isLoading = true;
        try {
            const data = await getHandoverContext({ handoverId: this._recordId });
            this.handoverName = data?.handover?.Name || 'Handover';
            const isInspDone = data?.handover?.Inspection_Status__c === 'Completed';
            const unclosedSnags = (data?.snagBoard?.openCount || 0) + (data?.snagBoard?.inProgressCount || 0) + (data?.snagBoard?.verificationCount || 0);

            if (!isInspDone) {
                this.canProceed = false;
                this.blockingReason = 'Inspection must be completed before continuing to Appointment.';
            } else if (unclosedSnags > 0) {
                this.canProceed = false;
                this.blockingReason = `Cannot continue to Appointment while ${unclosedSnags} snag(s) are unresolved or unverified.`;
            } else {
                this.canProceed = true;
                this.blockingReason = '';
            }
        } catch (error) {
            this.showToast('Error', error?.body?.message || error.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleAdvanceToAppointment() {
        this.isSubmitting = true;
        try {
            await proceedToAppointment({ handoverId: this._recordId });
            this.showToast('Advanced to Appointment', 'Handover has progressed to Stage 4: Appointment & Handover.', 'success');

            if (this._recordId) {
                await notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
            }

            window.dispatchEvent(new CustomEvent('handoverstagechange', {
                detail: { stage: 'Appointment', recordId: this._recordId }
            }));

            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showToast('Error Advancing Stage', error?.body?.message || error.message, 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
