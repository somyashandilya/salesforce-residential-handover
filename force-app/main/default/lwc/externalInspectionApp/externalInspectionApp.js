import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getExternalInspectionContext from '@salesforce/apex/HandoverWorkspaceController.getExternalInspectionContext';
import getHandoverContext from '@salesforce/apex/HandoverWorkspaceController.getHandoverContext';
import updateChecklistItemStatus from '@salesforce/apex/HandoverWorkspaceController.updateChecklistItemStatus';
import completeInspection from '@salesforce/apex/HandoverWorkspaceController.completeInspection';

export default class ExternalInspectionApp extends LightningElement {
    @api token;
    @track isLoading = true;
    @track checklistGroups = [];
    @track currentInspection;
    @track unitSummary;
    @track isSubmitted = false;

    connectedCallback() {
        this.loadInspectionData();
    }

    get resolvedToken() {
        if (this.token) return this.token;
        if (typeof window !== 'undefined' && window.location && window.location.search) {
            const params = new URLSearchParams(window.location.search);
            return params.get('c__token') || params.get('token');
        }
        return null;
    }

    async loadInspectionData() {
        this.isLoading = true;
        try {
            const token = this.resolvedToken;
            let data;
            if (token) {
                data = await getExternalInspectionContext({ token });
            }
            if (!data) {
                data = await getHandoverContext({ handoverId: null });
            }

            if (data) {
                this.currentInspection = data.currentInspection;
                this.unitSummary = data.unitSummary;
                this.checklistGroups = this.formatGroups(data.checklistGroups || []);

                if (this.currentInspection && this.currentInspection.Status__c === 'Completed') {
                    this.isSubmitted = true;
                }
            }
        } catch (error) {
            this.showToast('Error Loading Inspection', error.body?.message || error.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    formatGroups(rawGroups) {
        return rawGroups.map(grp => {
            const rawItems = grp.items || [];
            const formattedItems = rawItems.map(itm => {
                const isPassed = itm.Result__c === 'Pass';
                const isIssue = itm.Result__c === 'Issue Found';
                const isNA = itm.Result__c === 'N/A';

                let rowClass = 'item-row item-row_pending';
                if (isPassed) rowClass = 'item-row item-row_passed';
                else if (isIssue) rowClass = 'item-row item-row_issue';
                else if (isNA) rowClass = 'item-row item-row_na';

                return {
                    ...itm,
                    isPassed,
                    isIssue,
                    isNA,
                    rowClass,
                    passBtnClass: `slds-button slds-button_small ${isPassed ? 'btn-pass-active' : 'slds-button_neutral'}`,
                    issueBtnClass: `slds-button slds-button_small ${isIssue ? 'btn-issue-active' : 'slds-button_neutral'}`,
                    naBtnClass: `slds-button slds-button_small ${isNA ? 'btn-na-active' : 'slds-button_neutral'}`
                };
            });

            return {
                category: grp.category,
                itemCountText: `${formattedItems.length} items`,
                items: formattedItems
            };
        });
    }

    get inspectionTitle() {
        const u = this.unitSummary?.unitName || 'Unit';
        return `External Property Inspection · Unit ${u}`;
    }

    get inspectionSubtitle() {
        const parts = [];
        if (this.unitSummary?.projectName) parts.push(this.unitSummary.projectName);
        if (this.unitSummary?.towerName) parts.push(this.unitSummary.towerName);
        if (this.unitSummary?.configuration && this.unitSummary.configuration !== 'N/A') parts.push(this.unitSummary.configuration);
        const area = this.unitSummary?.builtUpAreaSba || this.unitSummary?.carpetArea || this.unitSummary?.saleableArea;
        if (area) parts.push(`(${area})`);
        parts.push('Secure Token Access');
        return parts.join(' · ');
    }

    get unitName() {
        return this.unitSummary?.unitName || 'Unit';
    }

    get inspectionRef() {
        return this.currentInspection?.Name || '';
    }

    get inspectionStatusText() {
        return this.currentInspection?.Status__c || 'Active';
    }

    get totalItemsCount() {
        let count = 0;
        (this.checklistGroups || []).forEach(g => {
            count += (g.items || []).length;
        });
        return count;
    }

    get completedCount() {
        let count = 0;
        (this.checklistGroups || []).forEach(g => {
            (g.items || []).forEach(i => {
                if (i.Result__c) count++;
            });
        });
        return count;
    }

    async handleSetPass(event) {
        const itemId = event.currentTarget.dataset.id;
        this.optimisticUpdate(itemId, 'Pass');
        await this.persistItem(itemId, 'Pass', '');
    }

    async handleSetIssue(event) {
        const itemId = event.currentTarget.dataset.id;
        this.optimisticUpdate(itemId, 'Issue Found');
        await this.persistItem(itemId, 'Issue Found', 'Identified defect during external inspection');
    }

    async handleSetNA(event) {
        const itemId = event.currentTarget.dataset.id;
        this.optimisticUpdate(itemId, 'N/A');
        await this.persistItem(itemId, 'N/A', 'Not applicable');
    }

    optimisticUpdate(itemId, newResult) {
        this.checklistGroups = this.checklistGroups.map(grp => ({
            ...grp,
            items: grp.items.map(itm => {
                if (itm.Id === itemId) {
                    const isPassed = newResult === 'Pass';
                    const isIssue = newResult === 'Issue Found';
                    const isNA = newResult === 'N/A';

                    let rowClass = 'item-row item-row_pending';
                    if (isPassed) rowClass = 'item-row item-row_passed';
                    else if (isIssue) rowClass = 'item-row item-row_issue';
                    else if (isNA) rowClass = 'item-row item-row_na';

                    return {
                        ...itm,
                        Result__c: newResult,
                        isPassed,
                        isIssue,
                        isNA,
                        rowClass,
                        passBtnClass: `slds-button slds-button_small ${isPassed ? 'btn-pass-active' : 'slds-button_neutral'}`,
                        issueBtnClass: `slds-button slds-button_small ${isIssue ? 'btn-issue-active' : 'slds-button_neutral'}`,
                        naBtnClass: `slds-button slds-button_small ${isNA ? 'btn-na-active' : 'slds-button_neutral'}`
                    };
                }
                return itm;
            })
        }));
    }

    async persistItem(itemId, result, comments) {
        try {
            await updateChecklistItemStatus({ itemId, result, comments });
        } catch (error) {
            this.showToast('Error Saving Status', error.body?.message || error.message, 'error');
            await this.loadInspectionData();
        }
    }

    async handleSubmitInspection() {
        if (!this.currentInspection) return;
        this.isLoading = true;
        try {
            await completeInspection({ inspectionId: this.currentInspection.Id });
            this.isSubmitted = true;
            this.showToast('Submitted', 'Inspection audit completed and locked.', 'success');
        } catch (error) {
            this.showToast('Error Submitting Inspection', error.body?.message || error.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}