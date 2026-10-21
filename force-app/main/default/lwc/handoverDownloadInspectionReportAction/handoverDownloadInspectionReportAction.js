import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getHandoverInspectionReportSummary from '@salesforce/apex/HandoverWorkspaceController.getHandoverInspectionReportSummary';
import generateInspectionReport from '@salesforce/apex/HandoverWorkspaceController.generateInspectionReport';

export default class HandoverDownloadInspectionReportAction extends LightningElement {
    _recordId;
    _hasLoaded = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && !this._hasLoaded) {
            this.loadInspectionSummary();
        }
    }

    @track isLoading = true;
    @track isDownloading = false;
    @track reportData = null;
    @track hasInspection = false;

    connectedCallback() {
        if (this._recordId && !this._hasLoaded) {
            this.loadInspectionSummary();
        }
    }

    async loadInspectionSummary() {
        if (!this._recordId) {
            return;
        }
        this._hasLoaded = true;
        this.isLoading = true;
        try {
            const data = await getHandoverInspectionReportSummary({ handoverId: this._recordId });
            if (data && data.inspection) {
                this.reportData = data;
                this.hasInspection = true;
            } else {
                this.reportData = null;
                this.hasInspection = false;
            }
        } catch (error) {
            this.showToast('Error Loading Inspection', error?.body?.message || error.message, 'error');
            this.hasInspection = false;
        } finally {
            this.isLoading = false;
        }
    }

    get formattedInspectionDate() {
        if (this.reportData?.inspection?.Inspection_Date__c) {
            return new Date(this.reportData.inspection.Inspection_Date__c).toLocaleDateString('en-GB', {
                day: '2-digit', month: 'short', year: 'numeric'
            });
        }
        return 'Not Recorded';
    }

    async handleDownloadPdf() {
        if (!this.reportData?.inspection?.Id) return;
        this.isDownloading = true;
        try {
            const res = await generateInspectionReport({ inspectionId: this.reportData.inspection.Id });
            this.showToast(
                'Report Download Initiated',
                `Official PDF prepared: ${res.fileName}`,
                'success'
            );

            if (res.downloadUrl) {
                const downloadLink = document.createElement('a');
                downloadLink.href = res.downloadUrl;
                downloadLink.download = res.fileName || 'Inspection_Report.pdf';
                document.body.appendChild(downloadLink);
                downloadLink.click();
                downloadLink.remove();
            } else if (res.pdfUrl) {
                window.open(res.pdfUrl, '_blank');
            }

            if (this._recordId) {
                notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
            }
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showToast('Error Generating PDF', error?.body?.message || error.message, 'error');
        } finally {
            this.isDownloading = false;
        }
    }

    handleOpenPdfTab() {
        if (!this.reportData?.inspection?.Id) return;
        const pdfUrl = `/apex/InspectionReportPDF?id=${this.reportData.inspection.Id}`;
        window.open(pdfUrl, '_blank');
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
