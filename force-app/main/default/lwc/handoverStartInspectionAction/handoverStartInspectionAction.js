import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getHandoverContext from '@salesforce/apex/HandoverWorkspaceController.getHandoverContext';
import startInspection from '@salesforce/apex/HandoverWorkspaceController.startInspection';

export default class HandoverStartInspectionAction extends LightningElement {
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
    @track contextData = null;
    @track isReadinessBlocked = false;
    @track blockingReason = '';

    // Form inputs
    @track inspectionType = 'Internal';
    @track inspectorName = '';
    @track inspectorCompany = 'Quality Audit Team';
    @track inspectorEmail = '';
    @track targetInspectionDate = '';

    get inspectionTypeOptions() {
        return [
            { label: 'Internal Developer QA', value: 'Internal' },
            { label: 'Independent Technical Audit', value: 'Third Party' },
            { label: 'Joint Customer & Auditor Review', value: 'Hybrid' }
        ];
    }

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
            this.contextData = data;
            const readiness = data?.readiness;

            if (readiness && readiness.canStartInspection === false) {
                this.isReadinessBlocked = true;
                this.blockingReason = readiness.blockingReason || 'Prerequisites for inspection are not satisfied.';
            } else {
                this.isReadinessBlocked = false;
                this.blockingReason = '';
                this.inspectorName = data.handover?.Handover_Owner__r?.Name || 'Lead Auditor';
                this.targetInspectionDate = data.currentInspection?.Inspection_Date__c || new Date().toISOString().slice(0, 10);
            }
        } catch (error) {
            this.showToast('Error Validating Readiness', error?.body?.message || error.message, 'error');
            this.isReadinessBlocked = true;
            this.blockingReason = error?.body?.message || error.message;
        } finally {
            this.isLoading = false;
        }
    }

    handleInspectionTypeChange(e) { this.inspectionType = e.detail.value; }
    handleInspectorNameChange(e) { this.inspectorName = e.detail.value; }
    handleInspectorCompanyChange(e) { this.inspectorCompany = e.detail.value; }
    handleInspectorEmailChange(e) { this.inspectorEmail = e.detail.value; }
    handleTargetInspectionDateChange(e) { this.targetInspectionDate = e.detail.value; }

    get isStartDisabled() {
        return this.isSubmitting || !this.inspectorName || !this.inspectionType;
    }

    async handleConfirmStart() {
        if (!this.inspectorName) {
            this.showToast('Validation Error', 'Lead Inspector Name is required.', 'warning');
            return;
        }

        this.isSubmitting = true;
        try {
            await startInspection({
                handoverId: this._recordId,
                inspectionType: this.inspectionType || 'Internal',
                inspectorName: this.inspectorName,
                inspectorCompany: this.inspectorCompany || 'Quality Audit Team',
                inspectorEmail: this.inspectorEmail,
                inspectionDate: this.targetInspectionDate || null
            });

            this.showToast('Inspection Started', `Inspection round initiated with ${this.inspectorName}.`, 'success');
            
            // Dispatch event to advance workspace stage
            window.dispatchEvent(new CustomEvent('handoverstagechange', {
                detail: { stage: 'Inspection', recordId: this._recordId }
            }));

            await notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showToast('Error Starting Inspection', error?.body?.message || error.message, 'error');
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
