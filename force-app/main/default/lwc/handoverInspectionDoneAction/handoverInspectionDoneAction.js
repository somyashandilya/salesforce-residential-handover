import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getInspectionCompletionStatus from '@salesforce/apex/HandoverWorkspaceController.getInspectionCompletionStatus';
import completeInspection from '@salesforce/apex/HandoverWorkspaceController.completeInspection';

export default class HandoverInspectionDoneAction extends LightningElement {
    _recordId;
    _hasLoaded = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && !this._hasLoaded) {
            this.loadStatus();
        }
    }

    @track isLoading = true;
    @track isSubmitting = false;
    @track statusData = null;

    connectedCallback() {
        if (this._recordId && !this._hasLoaded) {
            this.loadStatus();
        }
    }

    async loadStatus() {
        if (!this._recordId) return;
        this._hasLoaded = true;
        this.isLoading = true;
        try {
            const data = await getInspectionCompletionStatus({ handoverId: this._recordId });
            this.statusData = data;
        } catch (error) {
            this.showToast('Error', error?.body?.message || error.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    get hasInspection() {
        return Boolean(this.statusData?.hasInspection);
    }

    get canComplete() {
        return Boolean(this.statusData?.canComplete);
    }

    get isAlreadyCompleted() {
        return this.statusData?.inspectionStatus === 'Completed';
    }

    async handleCompleteInspection() {
        if (!this.statusData?.inspectionId) return;
        this.isSubmitting = true;
        try {
            await completeInspection({ inspectionId: this.statusData.inspectionId });
            this.showToast('Inspection Completed', 'Inspection has been finalized and locked.', 'success');

            if (this._recordId) {
                await notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
            }

            window.dispatchEvent(new CustomEvent('handoverstagechange', {
                detail: { stage: 'Inspection', recordId: this._recordId }
            }));

            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showToast('Cannot Complete Inspection', error?.body?.message || error.message, 'error');
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
