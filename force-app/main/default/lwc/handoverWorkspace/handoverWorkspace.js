import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

import getHandoverContext from '@salesforce/apex/HandoverWorkspaceController.getHandoverContext';
import updateTargetDate from '@salesforce/apex/HandoverWorkspaceController.updateTargetDate';
import startInspection from '@salesforce/apex/HandoverWorkspaceController.startInspection';
import updateTargetInspectionDate from '@salesforce/apex/HandoverWorkspaceController.updateTargetInspectionDate';
import updateChecklistItemStatus from '@salesforce/apex/HandoverWorkspaceController.updateChecklistItemStatus';
import completeInspection from '@salesforce/apex/HandoverWorkspaceController.completeInspection';
import raiseManualSnag from '@salesforce/apex/HandoverWorkspaceController.raiseManualSnag';
import updateSnagStatus from '@salesforce/apex/HandoverWorkspaceController.updateSnagStatus';
import scheduleAppointment from '@salesforce/apex/HandoverWorkspaceController.scheduleAppointment';
import rescheduleAppointment from '@salesforce/apex/HandoverWorkspaceController.rescheduleAppointment';
import completePhysicalHandover from '@salesforce/apex/HandoverWorkspaceController.completePhysicalHandover';
import completePhysicalHandoverWithDetails from '@salesforce/apex/HandoverWorkspaceController.completePhysicalHandoverWithDetails';
import assignSnagOwnerWithTeam from '@salesforce/apex/HandoverWorkspaceController.assignSnagOwnerWithTeam';
import raiseManualSnagWithTeam from '@salesforce/apex/HandoverWorkspaceController.raiseManualSnagWithTeam';

import completeHandoverCompact from '@salesforce/apex/HandoverWorkspaceController.completeHandoverCompact';
import sendActivityEmail from '@salesforce/apex/HandoverWorkspaceController.sendActivityEmail';
import createActivityTask from '@salesforce/apex/HandoverWorkspaceController.createActivityTask';
import logActivityCall from '@salesforce/apex/HandoverWorkspaceController.logActivityCall';
import completeActivityTask from '@salesforce/apex/HandoverWorkspaceController.completeActivityTask';
import logActivityTask from '@salesforce/apex/HandoverWorkspaceController.logActivityTask';
import updateHandoverOwner from '@salesforce/apex/HandoverWorkspaceController.updateHandoverOwner';
import searchUsers from '@salesforce/apex/HandoverWorkspaceController.searchUsers';
import addChecklistItem from '@salesforce/apex/HandoverWorkspaceController.addChecklistItem';
import deleteChecklistItem from '@salesforce/apex/HandoverWorkspaceController.deleteChecklistItem';
import generateInspectionReport from '@salesforce/apex/HandoverWorkspaceController.generateInspectionReport';
import verifySnag from '@salesforce/apex/HandoverWorkspaceController.verifySnag';
import assignSnagOwner from '@salesforce/apex/HandoverWorkspaceController.assignSnagOwner';
import submitSnagForVerification from '@salesforce/apex/HandoverWorkspaceController.submitSnagForVerification';
import submitExternalInspection from '@salesforce/apex/HandoverWorkspaceController.submitExternalInspection';
import getFormalInspectionReportData from '@salesforce/apex/HandoverWorkspaceController.getFormalInspectionReportData';
import shareInspectionReport from '@salesforce/apex/HandoverWorkspaceController.shareInspectionReport';
import shareSnagWithExternalUser from '@salesforce/apex/HandoverWorkspaceController.shareSnagWithExternalUser';

export default class HandoverWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;
    @api displayMode = 'all';

    get isPathMode() {
        return this.displayMode === 'path' || this.displayMode === 'all';
    }

    get isWorkspaceMode() {
        return this.displayMode === 'workspace' || this.displayMode === 'all';
    }

    @track isLoading = true;
    @track handover = null;
    @track readiness = {};
    @track unitSummary = {};
    @track contactSummary = {};
    @track coOwners = [];
    @track currentInspection = null;
    @track checklistGroups = [];
    @track snagBoard = {
        openSnags: [],
        inProgressSnags: [],
        verificationSnags: [],
        closedSnags: [],
        totalCount: 0,
        openCount: 0,
        inProgressCount: 0,
        verificationCount: 0,
        closedCount: 0,
        blockingCount: 0
    };
    @track documentsList = [];
    @track hasBlockingSnags = false;
    @track externalInspectionUrl = '';
    @track stageSummary = {};
    @track activityTimeline = [];

    // Active stage: 'Readiness' | 'Inspection' | 'Resolution' | 'Appointment' | 'Completed'
    @track currentActiveStage = 'Readiness';
    _hasInitialStageLoaded = false;
    @track activeMainTab = 'process';
    @track relatedLists = {};
    @track inspectionSubView = 'checklist'; // 'checklist' | 'snags'
    @track newSnagTeam = 'Civil & Finishes';
    @track selectedResponsibleTeam = 'Civil & Finishes';
    @track assignmentRemarks = '';
    @track keysSetsCount = 3;
    @track accessCardsCount = 2;
    @track accessDetails = '';
    @track uploadedHandoverDocFiles = [];
    @track uploadedSignedAckFiles = [];
    @track ackDateTime = '';
    @track targetInspectionDate = null;
    @track targetInspectionDateFormatted = 'Not Scheduled';
    @track targetInspectionDateInput = '';
    @track isEditTargetDateModalOpen = false;
    @track isSavingTargetDate = false;

    // Audit View State
    @track showAuditModal = false;
    @track auditView = null;
    @track auditLogFilter = '';

    // Related Records Collapsible State
    @track collapsedSections = {
        booking: false,
        customer: false,
        unit: false,
        inspections: false,
        checklist: false,
        snags: false,
        events: false,
        tasks: false,
        documents: false,
        activities: false
    };

    // View All Modal State
    @track showViewAllModal = false;
    @track viewAllConfig = {
        title: '',
        icon: 'standard:record',
        type: '',
        filterText: ''
    };


    // Property & Customer Details Drawer/Modal
    @track showDetailsDrawer = false;

    // Mini Composer Toolbar in Activity Panel (Default = timeline only)
    @track showMiniComposer = false;
    @track activeMiniComposer = ''; // 'Email' | 'Task' | 'Call'
    @track activityEmailTo = '';
    @track activityEmailSubject = '';
    @track activityEmailBody = '';
    @track activityTaskSubject = '';
    @track activityTaskDueDate = '';
    @track activityTaskPriority = 'Normal';
    @track activityTaskDescription = '';
    @track activityCallSubject = '';
    @track activityCallComments = '';

    // Target Date
    @track targetDateVal = '';
    @track showEditTargetDateModal = false;

    // Modals
    @track showStartInspectionModal = false;
    @track showRaiseSnagModal = false;
    @track showAssignModal = false;
    @track showReopenModal = false;
    @track showRescheduleModal = false;
    @track showChangeOwnerModal = false;
    @track showAddChecklistItemModal = false;
    @track showResolveSnagModal = false;
    @track showExternalFormModal = false;

    // Formal Inspection Report Modal
    @track showInspectionReportModal = false;
    @track formalReportData = null;
    @track showShareReportModal = false;
    @track shareReportEmails = '';
    @track shareReportNote = '';

    // Share Snag with External User Modal
    @track showShareSnagModal = false;
    @track shareSnagId = null;
    @track shareSnagEmail = '';
    @track shareSnagNote = '';

    // Change Owner
    @track ownerSearchTerm = '';
    @track searchedUsers = [];
    @track selectedNewOwnerId = null;
    @track selectedNewOwnerName = '';

    // Add Checklist Item Inputs
    @track newItemName = '';
    @track newItemCategory = 'Civil & Finishes';
    @track newItemLocation = 'Living & Dining';

    // Resolve & Verification Snag Inputs
    @track resolutionComments = '';
    @track evidenceUrl = '';

    // External Inspection Inputs
    @track externalAuditorName = '';
    @track externalAuditorCompany = 'Third-Party Technical Auditor';
    @track externalOverallComments = '';
    @track externalChecklistDraft = [];

    // Inspection Inputs
    @track inspectionType = 'Internal';
    @track inspectorName = '';
    @track inspectorCompany = 'Quality Audit Team';
    @track inspectorEmail = '';

    // Raise Snag Inputs
    @track newSnagLocation = 'Living & Dining';
    @track newSnagCategory = 'Civil & Finishes';
    @track newSnagDesc = '';
    @track newSnagSeverity = 'Minor';
    @track newSnagContractor = 'SafeBuild Contractors';
    @track newSnagDueDate = '';
    @track selectedChecklistItemId = null;

    // Assign / Reopen Snag
    @track selectedSnagId = null;
    @track selectedContractor = 'SafeBuild Contractors';
    @track reopenReason = '';

    // Appointment Form
    @track aptDate = '';
    @track aptSlot = '10:00 AM - 11:30 AM';
    @track aptLocation = 'Tower Lobby / Handover Desk';
    @track aptInstructions = 'Please carry Government Photo IDs of all co-owners, the original Allotment Letter, and Bank Clearance NOC.';

    // Reschedule Form
    @track rescheduleDate = '';
    @track rescheduleSlot = '11:30 AM - 01:00 PM';
    @track rescheduleLocation = 'Tower Lobby / Handover Desk';

    // Handover Completion Checklist
    @track keysHandedOver = false;
    @track cardsHandedOver = false;
    @track docsHandedOver = false;
    @track meterReadingsCaptured = false;
    @track customerAcknowledged = false;
    @track finalRemarks = 'Keys and official possession documents transferred to the customer. All unit features verified.';

    connectedCallback() {
        this.stageChangeListener = (event) => {
            if (event.detail && event.detail.recordId === this.recordId && event.detail.stage) {
                this.currentActiveStage = event.detail.stage;
                this.loadWorkspace();
            }
        };
        window.addEventListener('handoverstagechange', this.stageChangeListener);
        this.loadWorkspace();
    }

    disconnectedCallback() {
        if (this.stageChangeListener) {
            window.removeEventListener('handoverstagechange', this.stageChangeListener);
        }
    }

    async loadWorkspace() {
        this.isLoading = true;
        const currentStageBeforeRefresh = this.currentActiveStage;
        try {
            const data = await getHandoverContext({ handoverId: this.recordId });
            if (data && data.handover) {
                this.handover = data.handover;
                this.readiness = data.readiness || {};
                this.unitSummary = data.unitSummary || {};
                this.contactSummary = data.contactSummary || {};
                this.coOwners = data.coOwners || [];
                this.currentInspection = data.currentInspection;
                this.relatedLists = data.relatedLists || {};
                this.auditView = data.auditView || null;
                this.checklistGroups = this.formatChecklistGroups(data.checklistGroups || []);
                this.snagBoard = this.formatSnagBoard(data.snagBoard || {});
                this.stageSummary = data.stageSummary || {};
                this.documentsList = (data.attachedDocuments || []).map(cdl => {
                    const cd = cdl.ContentDocument || {};
                    const title = cd.Title || 'Document';
                    const ext = cd.FileExtension ? cd.FileExtension.toLowerCase() : '';
                    const fileType = cd.FileType || (ext ? ext.toUpperCase() : 'FILE');
                    const docId = cdl.ContentDocumentId;
                    const createdDate = cd.CreatedDate ? new Date(cd.CreatedDate).toLocaleDateString() : '';
                    let iconName = 'doctype:attachment';
                    if (fileType === 'PDF' || ext === 'pdf') iconName = 'doctype:pdf';
                    else if (['PNG', 'JPG', 'JPEG', 'GIF', 'WEBP'].includes(fileType) || ['png', 'jpg', 'jpeg', 'gif'].includes(ext)) iconName = 'doctype:image';
                    else if (fileType === 'TEXT' || ext === 'txt') iconName = 'doctype:txt';
                    else if (fileType === 'CSV' || ext === 'csv' || fileType === 'EXCEL') iconName = 'doctype:excel';
                    else if (fileType === 'WORD') iconName = 'doctype:word';
                    return {
                        docId,
                        title,
                        fileType,
                        extension: ext,
                        createdDate,
                        iconName
                    };
                });
                this.hasBlockingSnags = data.hasBlockingSnags || (this.snagBoard && this.snagBoard.hasBlockingSnags);
                this.externalInspectionUrl = data.externalInspectionUrl;

                // Activity timeline mapping
                this.activityTimeline = (data.activityTimeline || []).map(act => {
                    let circleClass = 'timeline-icon-wrap circle-blue';
                    let iconName = 'standard:task';
                    if (act.activityType === 'Email') {
                        circleClass = 'timeline-icon-wrap circle-purple';
                        iconName = 'standard:email';
                    } else if (act.activityType === 'Call') {
                        circleClass = 'timeline-icon-wrap circle-green';
                        iconName = 'standard:log_a_call';
                    } else if (act.activityType === 'Event') {
                        circleClass = 'timeline-icon-wrap circle-green';
                        iconName = 'standard:event';
                    }
                    const isTask = act.activityType === 'Task';
                    const isOpenTask = isTask && act.status !== 'Completed';
                    return {
                        ...act,
                        circleClass,
                        iconName,
                        isTask,
                        isOpenTask,
                        isEvent: act.activityType === 'Event',
                        isExpanded: false,
                        chevronIcon: 'utility:chevronright'
                    };
                });

                // Default activity composer fields
                if (!this.activityEmailTo && this.contactSummary?.email) {
                    this.activityEmailTo = this.contactSummary.email;
                }
                if (!this.activityCallSubject) {
                    this.activityCallSubject = `Call with ${this.customerName}`;
                }

                // Sync Target Handover Date
                if (this.handover.Target_Handover_Date__c) {
                    this.targetDateVal = this.handover.Target_Handover_Date__c;
                }

                // Sync Target Inspection Completion Date
                this.targetInspectionDate = data.targetInspectionDate || (this.currentInspection?.Inspection_Date__c || null);
                this.targetInspectionDateFormatted = data.targetInspectionDateFormatted || (this.targetInspectionDate ? new Date(this.targetInspectionDate).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : 'Not Scheduled');
                this.targetInspectionDateInput = this.targetInspectionDate || new Date().toISOString().slice(0, 10);

                // Sync Active Stage only on initial load so user actions (snags, checklists, etc.) keep current stage view
                if (!this._hasInitialStageLoaded && this.handover.Stage__c) {
                    this.syncActiveStage(this.handover.Stage__c);
                    this._hasInitialStageLoaded = true;
                } else if (currentStageBeforeRefresh) {
                    // Explicitly preserve current active stage across refreshes
                    this.currentActiveStage = currentStageBeforeRefresh;
                }

                // Appointment defaults
                if (this.handover.Appointment_Date__c) {
                    this.aptDate = this.handover.Appointment_Date__c;
                } else if (!this.aptDate) {
                    const d = new Date();
                    d.setDate(d.getDate() + 7);
                    this.aptDate = d.toISOString().split('T')[0];
                }
                if (this.handover.Appointment_Time_Slot__c) {
                    this.aptSlot = this.handover.Appointment_Time_Slot__c;
                }
                if (this.handover.Appointment_Location__c) {
                    this.aptLocation = this.handover.Appointment_Location__c;
                }
                if (this.handover.Final_Remarks__c) {
                    this.finalRemarks = this.handover.Final_Remarks__c;
                }
                if (this.handover.Access_Details__c) {
                    this.accessDetails = this.handover.Access_Details__c;
                }
                if (this.handover.Keys_Sets_Count__c) {
                    this.keysSetsCount = this.handover.Keys_Sets_Count__c;
                }
                if (this.handover.Access_Cards_Count__c) {
                    this.accessCardsCount = this.handover.Access_Cards_Count__c;
                }
                if (this.handover.Acknowledgement_Date_Time__c) {
                    this.ackDateTime = this.handover.Acknowledgement_Date_Time__c;
                } else if (!this.ackDateTime) {
                    this.ackDateTime = new Date().toISOString();
                }
                if (this.handover.Keys_Handed_Over__c) {
                    this.keysHandedOver = true;
                }
                if (this.handover.Access_Cards_Handed_Over__c) {
                    this.cardsHandedOver = true;
                }
                if (this.handover.Documents_Handed_Over__c) {
                    this.docsHandedOver = true;
                }
                if (this.handover.Meter_Readings_Captured__c) {
                    this.meterReadingsCaptured = true;
                }
                if (this.handover.Customer_Acknowledgement_Status__c === 'Captured' || this.handover.Customer_Acknowledgement_Status__c === 'Signed' || this.handover.Customer_Acknowledgement_Status__c === 'Acknowledged') {
                    this.customerAcknowledged = true;
                }
            }
        } catch (error) {
            this.showToast('Error Loading Handover', error.body?.message || error.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    get hasSnags() {
        return this.snagBoard && this.snagBoard.totalCount > 0;
    }

    syncActiveStage(stage) {
        if (stage === 'Readiness') this.currentActiveStage = 'Readiness';
        else if (stage === 'Inspection') this.currentActiveStage = 'Inspection';
        else if (stage === 'Snag & Resolution' || stage === 'Resolution') this.currentActiveStage = 'Resolution';
        else if (stage === 'Appointment & Handover' || stage === 'Appointment') this.currentActiveStage = 'Appointment';
        else if (stage === 'Completed' || stage === 'Completed / Post-Sale') this.currentActiveStage = 'Completed';
    }

    formatChecklistGroups(groups) {
        return groups.map(grp => {
            const items = (grp.items || []).map(itm => {
                const res = itm.Result__c;
                const isPass = res === 'Pass';
                const isIssue = res === 'Issue Found' || res === 'Issue';
                const isNA = res === 'N/A';
                const isPending = !isPass && !isIssue && !isNA;

                let linkedSnagName = itm.linkedSnagName || null;
                if (!linkedSnagName) {
                    if (itm.Snag_Checklist_Item__r && itm.Snag_Checklist_Item__r.length > 0) {
                        linkedSnagName = itm.Snag_Checklist_Item__r[0].Name;
                    } else if (itm.Snags__r && itm.Snags__r.length > 0) {
                        linkedSnagName = itm.Snags__r[0].Name;
                    }
                }
                const hasLinkedSnag = Boolean(linkedSnagName);

                let rowClass = 'checklist-row row-pending';
                let statusIcon = '';
                let statusIconClass = 'status-icon icon-pending';
                let resultText = 'PENDING';
                let resultBadgeClass = 'result-badge badge-pending';

                if (isPass) {
                    rowClass = 'checklist-row row-passed';
                    statusIcon = 'Pass';
                    statusIconClass = 'status-icon icon-passed';
                    resultText = 'PASSED';
                    resultBadgeClass = 'result-badge badge-passed';
                } else if (isIssue) {
                    rowClass = 'checklist-row row-issue';
                    statusIcon = 'Issue';
                    statusIconClass = 'status-icon icon-issue';
                    resultText = 'ISSUE FOUND';
                    resultBadgeClass = 'result-badge badge-issue';
                } else if (isNA) {
                    rowClass = 'checklist-row row-na';
                    statusIcon = 'N/A';
                    statusIconClass = 'status-icon icon-na';
                    resultText = 'N/A';
                    resultBadgeClass = 'result-badge badge-na';
                }

                return {
                    ...itm,
                    isPass,
                    isIssue,
                    isNA,
                    isPending,
                    linkedSnagName,
                    hasLinkedSnag,
                    rowClass,
                    statusIcon,
                    statusIconClass,
                    resultText,
                    resultBadgeClass,
                    passBtnLabel: 'Pass',
                    issueBtnLabel: 'Issue',
                    naBtnLabel: 'N/A',
                    passBtnClass: `chk-btn-pass ${isPass ? 'active' : ''}`,
                    issueBtnClass: `chk-btn-issue ${isIssue ? 'active' : ''}`,
                    naBtnClass: `chk-btn-na ${isNA ? 'active' : ''}`
                };
            });

            const totalCount = items.length;
            const answeredCount = items.filter(i => !i.isPending).length;

            return {
                ...grp,
                items,
                totalCount,
                answeredCount
            };
        });
    }

    formatSnagBoard(board) {
        const evidenceFilesMap = board.snagEvidenceFiles || {};
        const processList = (list) => (list || []).map(s => ({
            ...s,
            cardClass: `snag-card ${s.Severity__c === 'Critical' ? 'card-critical' : ''}`,
            severityBadgeClass: `snag-severity-badge severity-${(s.Severity__c || 'minor').toLowerCase()}`,
            evidenceFiles: evidenceFilesMap[s.Id] || []
        }));

        return {
            ...board,
            openSnags: processList(board.openSnags),
            inProgressSnags: processList(board.inProgressSnags),
            verificationSnags: processList(board.verificationSnags),
            closedSnags: processList(board.closedSnags),
            totalCount: board.totalCount || 0,
            openCount: board.openCount || 0,
            inProgressCount: board.inProgressCount || 0,
            verificationCount: board.verificationCount || 0,
            closedCount: board.closedCount || 0,
            blockingCount: board.blockingCount || 0,
            hasBlockingSnags: board.hasBlockingSnags || false
        };
    }

    // ── Drawer Toggle ───────────────────────────────────────────────────
    toggleDetailsDrawer() {
        this.showDetailsDrawer = !this.showDetailsDrawer;
    }

    // ── Mini-Composer Toolbar Controls ──────────────────────────────────
    toggleActivityComposerEmail() {
        if (this.activeMiniComposer === 'Email' && this.showMiniComposer) {
            this.showMiniComposer = false;
            this.activeMiniComposer = '';
        } else {
            this.showMiniComposer = true;
            this.activeMiniComposer = 'Email';
        }
    }

    toggleActivityComposerTask() {
        if (this.activeMiniComposer === 'Task' && this.showMiniComposer) {
            this.showMiniComposer = false;
            this.activeMiniComposer = '';
        } else {
            this.showMiniComposer = true;
            this.activeMiniComposer = 'Task';
        }
    }

    toggleActivityComposerCall() {
        if (this.activeMiniComposer === 'Call' && this.showMiniComposer) {
            this.showMiniComposer = false;
            this.activeMiniComposer = '';
        } else {
            this.showMiniComposer = true;
            this.activeMiniComposer = 'Call';
        }
    }

    closeMiniComposer() {
        this.showMiniComposer = false;
        this.activeMiniComposer = '';
    }

    get isActivityEmailTab() { return this.activeMiniComposer === 'Email'; }
    get isActivityTaskTab() { return this.activeMiniComposer === 'Task'; }
    get isActivityCallTab() { return this.activeMiniComposer === 'Call'; }

    get composerHeaderTitle() {
        if (this.activeMiniComposer === 'Email') return 'Compose Customer Email';
        if (this.activeMiniComposer === 'Task') return 'Create Activity Task';
        if (this.activeMiniComposer === 'Call') return 'Log Customer Discussion / Call';
        return 'Activity Composer';
    }

    get emailActionBtnClass() {
        return `activity-toolbar-btn ${this.activeMiniComposer === 'Email' && this.showMiniComposer ? 'active' : ''}`;
    }

    get taskActionBtnClass() {
        return `activity-toolbar-btn ${this.activeMiniComposer === 'Task' && this.showMiniComposer ? 'active' : ''}`;
    }

    get callActionBtnClass() {
        return `activity-toolbar-btn ${this.activeMiniComposer === 'Call' && this.showMiniComposer ? 'active' : ''}`;
    }

    // ── Getters ─────────────────────────────────────────────────────────
    get handoverNumber() {
        return this.handover?.Name || 'HO-1001';
    }

    get headerLocationText() {
        const p = this.unitSummary?.projectName || 'Project';
        const t = this.unitSummary?.towerName || 'Tower';
        const f = this.unitSummary?.floorName || 'Floor';
        return `${p} · ${t} · ${f}`;
    }

    get unitStatusBadgeText() {
        return this.unitSummary?.unitStatus || 'Assigned';
    }

    get coOwnersCount() {
        return this.coOwners?.length || 0;
    }

    get hasCoOwners() {
        return this.coOwners && this.coOwners.length > 0;
    }

    get bookingReceivedFormatted() {
        return '₹1,50,00,000';
    }

    get targetDateFormatted() {
        if (!this.targetDateVal) return '28 Oct 2026';
        const parts = this.targetDateVal.split('-');
        if (parts.length === 3) {
            const d = new Date(this.targetDateVal);
            return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
        }
        return this.targetDateVal;
    }

    get possessionDateFormatted() {
        return this.readiness?.possessionReadyDate || '27 Sep 2026';
    }

    get completedDateFormatted() {
        if (this.handover?.Completed_Date_Time__c) {
            return new Date(this.handover.Completed_Date_Time__c).toLocaleDateString('en-GB', {
                day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit'
            });
        }
        return new Date().toLocaleDateString('en-GB', {
            day: 'numeric', month: 'short', year: 'numeric'
        });
    }

    get statusBadgeText() {
        return this.handover?.Status__c || 'Possession ready';
    }

    get fullExternalInspectionUrl() {
        if (!this.externalInspectionUrl) {
            return window.location.origin + '/services/apexrest/externalInspection';
        }
        if (this.externalInspectionUrl.startsWith('http')) {
            return this.externalInspectionUrl;
        }
        return window.location.origin + this.externalInspectionUrl;
    }

    get isHandoverCompleted() {
        return this.handover?.Status__c === 'Completed' || this.handover?.Stage__c === 'Completed';
    }

    get isNotCompleted() {
        return !this.isHandoverCompleted;
    }

    get normalizedRecordStage() {
        const stage = this.handover?.Stage__c;
        if (stage === 'Readiness') return 'Readiness';
        if (stage === 'Inspection') return 'Inspection';
        if (stage === 'Snag & Resolution' || stage === 'Resolution') return 'Resolution';
        if (stage === 'Appointment & Handover' || stage === 'Appointment') return 'Appointment';
        if (stage === 'Completed' || stage === 'Completed / Post-Sale') return 'Completed';
        return 'Readiness';
    }

    get isActionDisabled() {
        return this.isLoading || this.isHandoverCompleted || this.isInspectionLocked || this.isPreviousStageViewed;
    }

    get canEditChecklist() {
        return !this.isHandoverCompleted && this.isStageInspection && !this.isInspectionLocked && !this.isPreviousStageViewed;
    }

    get hasUnresolvedSnags() {
        return (this.snagBoard?.openCount || 0) + (this.snagBoard?.inProgressCount || 0) + (this.snagBoard?.verificationCount || 0) > 0;
    }

    get unresolvedSnagsCount() {
        return (this.snagBoard?.openCount || 0) + (this.snagBoard?.inProgressCount || 0) + (this.snagBoard?.verificationCount || 0);
    }

    get isContinueToAppointmentDisabled() {
        return this.isLoading || this.hasUnresolvedSnags || this.isHandoverCompleted || this.isResolutionLocked;
    }

    get isChangeOwnerSaveDisabled() {
        return !this.selectedNewOwnerId || this.isLoading;
    }

    get isSaveNewItemDisabled() {
        return !this.newItemName || !this.newItemCategory || !this.newItemLocation || this.isLoading;
    }

    get currentInspectionToken() {
        return this.currentInspection?.External_Token__c || 'N/A';
    }

    get taskPriorityOptions() {
        return [
            { label: 'Normal', value: 'Normal' },
            { label: 'High', value: 'High' },
            { label: 'Low', value: 'Low' }
        ];
    }

    get headerRecordTitle() {
        return `${this.handoverNumber} · ${this.customerName}`;
    }

    get completedByName() {
        return this.handover?.Completed_By__r?.Name || this.handoverOwnerName || 'Namit Dasappanavar';
    }

    get hasExternalSubmission() {
        return Boolean(this.currentInspection?.External_Submitted__c || (this.currentInspection?.Status__c === 'Completed' && (this.currentInspection?.Inspection_Type__c === 'Third Party' || this.currentInspection?.Inspection_Type__c === 'Hybrid')));
    }

    get externalSubmissionDate() {
        if (this.currentInspection?.External_Submission_Date__c) {
            return new Date(this.currentInspection.External_Submission_Date__c).toLocaleDateString('en-GB', {
                day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit'
            });
        }
        return '';
    }

    get externalInspectorName() {
        return this.currentInspection?.Inspector_Name__c || 'Third-Party Auditor';
    }

    get customerName() {
        return this.contactSummary?.contactName || 'Customer';
    }

    get customerEmail() {
        return this.contactSummary?.email || 'customer@example.com';
    }

    get customerPhone() {
        return this.contactSummary?.phone || '';
    }

    get customerPhoneHref() {
        return this.customerPhone ? `tel:${this.customerPhone}` : 'javascript:void(0);';
    }

    get customerEmailHref() {
        return this.customerEmail ? `mailto:${this.customerEmail}` : 'javascript:void(0);';
    }

    get projectName() {
        return this.unitSummary?.projectName || 'Project';
    }

    get towerName() {
        return this.unitSummary?.towerName || 'Tower A';
    }

    get unitName() {
        return this.unitSummary?.unitName || 'BB-TA200';
    }

    get customerInitials() {
        if (!this.contactSummary?.contactName) return 'CU';
        return this.contactSummary.contactName
            .split(' ')
            .map(n => n[0])
            .join('')
            .toUpperCase()
            .substring(0, 2);
    }

    get handoverOwnerName() {
        return this.handover?.Handover_Owner__r?.Name || 'Namit Dasappanavar';
    }

    get allChecklistItems() {
        const all = [];
        if (this.checklistGroups) {
            for (const grp of this.checklistGroups) {
                if (grp.items) {
                    all.push(...grp.items);
                }
            }
        }
        return all;
    }

    get totalChecklistCount() {
        return this.allChecklistItems.length;
    }

    get passedChecklistCount() {
        return this.allChecklistItems.filter(i => i.isPass).length;
    }

    get issuesChecklistCount() {
        return this.allChecklistItems.filter(i => i.isIssue).length;
    }

    get naChecklistCount() {
        return this.allChecklistItems.filter(i => i.isNA).length;
    }

    get answeredChecklistCount() {
        return this.allChecklistItems.filter(i => !i.isPending).length;
    }

    get pendingChecklistCount() {
        return this.allChecklistItems.filter(i => i.isPending).length;
    }

    get inspectionProgressLabel() {
        const total = this.totalChecklistCount;
        const answered = this.answeredChecklistCount;
        return `${answered} / ${total} completed`;
    }

    get inspectionPercent() {
        const total = this.totalChecklistCount;
        if (total === 0) return 0;
        return Math.round((this.answeredChecklistCount / total) * 100);
    }

    get pendingPillClass() {
        return `metric-pill ${this.pendingChecklistCount === 0 ? 'pill-zero-pending' : 'pill-pending'}`;
    }

    get isCompleteInspectionDisabled() {
        // Checklist must be fully answered (no pending items) and all items that were flagged as Issue must have a snag raised.
        // Open snags do NOT block completing inspection — they will be resolved in Stage 3 (Resolution).
        return this.isLoading || this.pendingChecklistCount > 0 || this.issuesChecklistCount > 0 || this.totalChecklistCount === 0 || this.isHandoverCompleted || this.isInspectionLocked;
    }

    get inspectorDisplay() {
        return this.currentInspection?.Inspector_Name__c || this.handoverOwnerName || 'Namit Dasappanavar';
    }

    get inspectionRoundDisplay() {
        return this.currentInspection?.Inspection_Round__c || 'Round 1';
    }

    // ── Stage Navigation & Gating Engine ──
    get STAGE_ORDER() {
        return ['Readiness', 'Inspection', 'Resolution', 'Appointment', 'Completed'];
    }

    get recordStageIndex() {
        return this.STAGE_ORDER.indexOf(this.normalizedRecordStage);
    }

    get viewingStageIndex() {
        return this.STAGE_ORDER.indexOf(this.currentActiveStage);
    }

    get isPreviousStageViewed() {
        return this.viewingStageIndex < this.recordStageIndex;
    }

    get isCurrentStageViewed() {
        return this.currentActiveStage === this.normalizedRecordStage;
    }

    get recordStageName() {
        return this.normalizedRecordStage;
    }

    get isReadinessLocked() {
        return this.recordStageIndex > 0 || this.isPreviousStageViewed;
    }

    get isInspectionLocked() {
        return this.recordStageIndex > 1 || this.isPreviousStageViewed || this.isInspectionCompleted;
    }

    get isResolutionLocked() {
        return this.recordStageIndex > 2 || this.isPreviousStageViewed;
    }

    get isNotResolutionLocked() {
        return !this.isResolutionLocked && !this.isHandoverCompleted && !this.isPreviousStageViewed;
    }

    get isAppointmentLocked() {
        return this.recordStageIndex > 3 || this.isPreviousStageViewed;
    }

    get isNotAppointmentLocked() {
        return !this.isAppointmentLocked && !this.isHandoverCompleted && !this.isPreviousStageViewed;
    }

    get isAppointmentReadOnly() {
        return this.isAppointmentLocked || this.isHandoverCompleted || this.isPreviousStageViewed;
    }

    get isCustomerInviteSent() {
        return Boolean(this.handover?.Customer_Notification_Sent__c || this.handover?.Customer_Notification_Sent_Date__c);
    }

    get isAppointmentDateDisabled() {
        return this.isAppointmentReadOnly || this.isCustomerInviteSent;
    }

    getStepClass(stageName, stageIdx) {
        const recordIdx = this.recordStageIndex;
        const isCurrentView = this.currentActiveStage === stageName;
        let isCompletedStage = recordIdx > stageIdx || (stageIdx === 4 && this.normalizedRecordStage === 'Completed');
        if (stageIdx === 1 && this.isInspectionCompleted) {
            isCompletedStage = true;
        }
        if (stageIdx === 2 && this.isInspectionCompleted && !this.hasUnresolvedSnags) {
            isCompletedStage = true;
        }

        let classes = ['path-step'];
        if (isCurrentView) {
            classes.push('is-active');
        } else if (isCompletedStage) {
            classes.push('is-complete');
        } else {
            classes.push('is-incomplete');
        }
        return classes.join(' ');
    }

    get stepClassReadiness() { return this.getStepClass('Readiness', 0); }
    get stepClassInspection() { return this.getStepClass('Inspection', 1); }
    get stepClassResolution() { return this.getStepClass('Resolution', 2); }
    get stepClassAppointment() { return this.getStepClass('Appointment', 3); }
    get stepClassCompleted() { return this.getStepClass('Completed', 4); }

    get isStepCompleteReadiness() {
        return this.recordStageIndex > 0 || this.normalizedRecordStage === 'Completed';
    }
    get isStepCompleteInspection() {
        return this.recordStageIndex > 1 || this.isInspectionCompleted || this.normalizedRecordStage === 'Completed';
    }
    get isStepCompleteResolution() {
        return this.recordStageIndex > 2 || (this.isInspectionCompleted && !this.hasUnresolvedSnags) || this.normalizedRecordStage === 'Completed';
    }
    get isStepCompleteAppointment() {
        return this.recordStageIndex > 3 || this.normalizedRecordStage === 'Completed';
    }
    get isStepCompleteCompleted() {
        return this.normalizedRecordStage === 'Completed';
    }

    get isStageReadiness() { return this.currentActiveStage === 'Readiness'; }
    get isStageInspection() { return this.currentActiveStage === 'Inspection'; }
    get isStageResolution() { return this.currentActiveStage === 'Resolution'; }
    get isStageAppointment() { return this.currentActiveStage === 'Appointment'; }
    get isStageCompleted() { return this.currentActiveStage === 'Completed'; }

    // ── Stage-Specific Document Collections ──
    get stageReadinessDocs() {
        return (this.documentsList || []).filter(d => {
            const t = (d.title || '').toLowerCase();
            return t.includes('booking') || t.includes('allotment') || t.includes('welcome') || 
                   t.includes('agreement') || t.includes('statement') || t.includes('ledger') || 
                   t.includes('receipt') || t.includes('kyc') || t.includes('readiness');
        });
    }
    get stageReadinessDocsCount() { return this.stageReadinessDocs.length; }

    get stageInspectionDocs() {
        return (this.documentsList || []).filter(d => {
            const t = (d.title || '').toLowerCase();
            return t.includes('inspection') || t.includes('audit') || t.includes('checklist') || t.includes('qa');
        });
    }
    get stageInspectionDocsCount() { return this.stageInspectionDocs.length; }

    get stageResolutionDocs() {
        return (this.documentsList || []).filter(d => {
            const t = (d.title || '').toLowerCase();
            return t.includes('snag') || t.includes('defect') || t.includes('rectification') || 
                   t.includes('evidence') || t.includes('resolution');
        });
    }
    get stageResolutionDocsCount() { return this.stageResolutionDocs.length; }

    get stageAppointmentDocs() {
        return (this.documentsList || []).filter(d => {
            const t = (d.title || '').toLowerCase();
            return t.includes('possession') || t.includes('key') || t.includes('receipt') || 
                   t.includes('acknowledgement') || t.includes('ack') || t.includes('handover') || 
                   t.includes('warranty') || t.includes('manual') || t.includes('certificate');
        });
    }
    get stageAppointmentDocsCount() { return this.stageAppointmentDocs.length; }

    get stageCompletedDocs() { return this.documentsList || []; }
    get stageCompletedDocsCount() { return this.stageCompletedDocs.length; }

    get cannotStartInspection() {
        return (this.readiness && this.readiness.canStartInspection === false) || this.isReadinessLocked;
    }

    get isInspectionCompleted() {
        const isInspDone = Boolean(this.currentInspection && this.currentInspection.Status__c === 'Completed');
        const isHoDone = Boolean(this.handover && this.handover.Inspection_Status__c === 'Completed');
        return isInspDone || isHoDone;
    }

    get isAppointmentScheduled() {
        return this.handover?.Status__c === 'Appointment Scheduled' || !!this.handover?.Appointment_Date__c;
    }

    get isSectionAComplete() {
        return Boolean(this.keysHandedOver && this.cardsHandedOver && this.keysSetsCount > 0 && this.accessCardsCount > 0);
    }

    get sectionABadgeLabel() {
        return this.isSectionAComplete ? 'Section A Complete' : 'Pending Keys/Cards/Details';
    }

    get sectionABadgeClass() {
        return this.isSectionAComplete ? 'slds-badge slds-theme_success font-weight-bold' : 'slds-badge slds-badge_lightest font-weight-bold';
    }

    get hasExistingHandoverDocs() {
        if (this.relatedLists?.documents && this.relatedLists.documents.length > 0) return true;
        if (this.documentsList && this.documentsList.length > 0) return true;
        return false;
    }

    get isSectionBComplete() {
        return Boolean(this.docsHandedOver && (this.uploadedHandoverDocFiles.length > 0 || this.hasExistingHandoverDocs));
    }

    get sectionBBadgeLabel() {
        return this.isSectionBComplete ? 'Section B Complete' : 'Pending Docs / Upload';
    }

    get sectionBBadgeClass() {
        return this.isSectionBComplete ? 'slds-badge slds-theme_success font-weight-bold' : 'slds-badge slds-badge_lightest font-weight-bold';
    }

    get hasExistingSignedAck() {
        return this.handover?.Customer_Acknowledgement_Status__c === 'Acknowledged' ||
               this.handover?.Customer_Acknowledgement_Status__c === 'Signed';
    }

    get isSectionCComplete() {
        return Boolean(this.customerAcknowledged && (this.uploadedSignedAckFiles.length > 0 || this.hasExistingSignedAck));
    }

    get sectionCBadgeLabel() {
        return this.isSectionCComplete ? 'Section C Complete' : 'Pending Ack / Signed Form';
    }

    get sectionCBadgeClass() {
        return this.isSectionCComplete ? 'slds-badge slds-theme_success font-weight-bold' : 'slds-badge slds-badge_lightest font-weight-bold';
    }

    get isAllHandoverSectionsComplete() {
        return this.isSectionAComplete && this.isSectionBComplete && this.isSectionCComplete;
    }

    get isCompleteHandoverDisabled() {
        return this.isLoading || !this.isAllHandoverSectionsComplete || this.isAppointmentLocked;
    }

    // Related List Getters
    get relatedBooking() { return this.relatedLists?.booking || null; }
    get relatedCustomer() { return this.relatedLists?.customer || null; }
    get relatedUnit() { return this.relatedLists?.unit || null; }
    get relatedInspections() { return this.relatedLists?.inspections || []; }
    get relatedInspectionsCount() { return this.relatedInspections.length; }
    get relatedChecklistItems() { return this.relatedLists?.checklistItems || []; }
    get relatedChecklistCount() { return this.relatedChecklistItems.length; }
    get relatedSnags() { 
        return (this.relatedLists?.snags || []).map(sn => ({
            ...sn,
            severityBadgeClass: sn.Severity__c === 'Critical' ? 'slds-badge slds-theme_error' :
                                sn.Severity__c === 'Major' ? 'slds-badge slds-theme_warning' : 'slds-badge'
        }));
    }
    get relatedSnagsCount() { return this.relatedSnags.length; }
    get relatedEvents() { return this.relatedLists?.events || []; }
    get relatedEventsCount() { return this.relatedEvents.length; }
    get relatedTasks() { return this.relatedLists?.tasks || []; }
    get relatedTasksCount() { return this.relatedTasks.length; }
    get relatedDocuments() {
        return (this.relatedLists?.documents || []).map(cdl => ({
            id: cdl.ContentDocumentId,
            title: cdl.ContentDocument ? cdl.ContentDocument.Title : 'Document',
            fileType: cdl.ContentDocument ? cdl.ContentDocument.FileType : 'PDF',
            downloadUrl: '/sfc/servlet.shepherd/document/download/' + cdl.ContentDocumentId
        }));
    }
    get relatedDocsCount() { return this.relatedDocuments.length; }
    get relatedActivities() { return this.relatedLists?.handoverActivities || []; }
    get relatedActivitiesCount() { return this.relatedActivities.length; }

    // Related List Previews (Cards display first 5 items)
    get relatedInspectionsPreview() { return this.relatedInspections.slice(0, 5); }
    get relatedChecklistPreview() { return this.relatedChecklistItems.slice(0, 5); }
    get relatedSnagsPreview() { return this.relatedSnags.slice(0, 5); }
    get relatedEventsPreview() { return this.relatedEvents.slice(0, 5); }
    get relatedTasksPreview() { return this.relatedTasks.slice(0, 5); }
    get relatedDocumentsPreview() { return this.relatedDocuments.slice(0, 5); }
    get relatedActivitiesPreview() { return this.relatedActivities.slice(0, 5); }

    // Collapsible Sections State & Chevrons
    get isBookingCollapsed() { return !!this.collapsedSections.booking; }
    get isCustomerCollapsed() { return !!this.collapsedSections.customer; }
    get isUnitCollapsed() { return !!this.collapsedSections.unit; }
    get isInspectionsCollapsed() { return !!this.collapsedSections.inspections; }
    get isChecklistCollapsed() { return !!this.collapsedSections.checklist; }
    get isSnagsCollapsed() { return !!this.collapsedSections.snags; }
    get isEventsCollapsed() { return !!this.collapsedSections.events; }
    get isTasksCollapsed() { return !!this.collapsedSections.tasks; }
    get isDocumentsCollapsed() { return !!this.collapsedSections.documents; }
    get isActivitiesCollapsed() { return !!this.collapsedSections.activities; }

    get isBookingExpanded() { return !this.collapsedSections.booking; }
    get isCustomerExpanded() { return !this.collapsedSections.customer; }
    get isUnitExpanded() { return !this.collapsedSections.unit; }
    get isInspectionsExpanded() { return !this.collapsedSections.inspections; }
    get isChecklistExpanded() { return !this.collapsedSections.checklist; }
    get isSnagsExpanded() { return !this.collapsedSections.snags; }
    get isEventsExpanded() { return !this.collapsedSections.events; }
    get isTasksExpanded() { return !this.collapsedSections.tasks; }
    get isDocumentsExpanded() { return !this.collapsedSections.documents; }
    get isActivitiesExpanded() { return !this.collapsedSections.activities; }

    get chevronBooking() { return this.isBookingCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get chevronCustomer() { return this.isCustomerCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get chevronUnit() { return this.isUnitCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get chevronInspections() { return this.isInspectionsCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get chevronChecklist() { return this.isChecklistCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get chevronSnags() { return this.isSnagsCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get chevronEvents() { return this.isEventsCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get chevronTasks() { return this.isTasksCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get chevronDocuments() { return this.isDocumentsCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get chevronActivities() { return this.isActivitiesCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }

    // Audit View Getters
    get auditStages() {
        return this.auditView?.stageHistory || this.auditView?.stages || [];
    }
    get auditLogs() {
        if (!this.auditView?.auditLogs) return [];
        if (this.auditLogFilter) {
            const f = this.auditLogFilter.toLowerCase();
            return this.auditView.auditLogs.filter(l => 
                (l.stageName && l.stageName.toLowerCase().includes(f)) ||
                (l.stage && l.stage.toLowerCase().includes(f)) ||
                (l.eventType && l.eventType.toLowerCase().includes(f)) ||
                (l.actorName && l.actorName.toLowerCase().includes(f)) ||
                (l.actor && l.actor.toLowerCase().includes(f)) ||
                (l.details && l.details.toLowerCase().includes(f)) ||
                (l.channel && l.channel.toLowerCase().includes(f)) ||
                (l.status && l.status.toLowerCase().includes(f))
            );
        }
        return this.auditView.auditLogs;
    }
    get auditLogsCount() {
        return this.auditView?.auditLogs?.length || 0;
    }
    get auditUnitName() {
        return this.auditView?.unitName || this.unitName || '—';
    }
    get auditCustomerName() {
        return this.auditView?.customerName || this.customerName || '—';
    }
    get auditCurrentStage() {
        return this.auditView?.currentStage || this.handover?.Stage__c || 'Readiness';
    }
    get auditStatus() {
        return this.auditView?.currentStatus || this.auditView?.status || this.handover?.Status__c || 'Active';
    }
    get auditBookingRef() {
        return this.auditView?.bookingReference || this.unitSummary?.bookingReference || '—';
    }

    // View All Modal Getters
    get isViewAllInspections() { return this.viewAllConfig.type === 'inspections'; }
    get isViewAllChecklist() { return this.viewAllConfig.type === 'checklist'; }
    get isViewAllSnags() { return this.viewAllConfig.type === 'snags'; }
    get isViewAllEvents() { return this.viewAllConfig.type === 'events'; }
    get isViewAllTasks() { return this.viewAllConfig.type === 'tasks'; }
    get isViewAllDocuments() { return this.viewAllConfig.type === 'documents'; }
    get isViewAllActivities() { return this.viewAllConfig.type === 'activities'; }

    get viewAllItems() {
        const type = this.viewAllConfig.type;
        const filter = (this.viewAllConfig.filterText || '').trim().toLowerCase();
        if (type === 'inspections') {
            return this.relatedInspections.filter(i => !filter || 
                (i.Name && i.Name.toLowerCase().includes(filter)) || 
                (i.Inspector_Name__c && i.Inspector_Name__c.toLowerCase().includes(filter)) ||
                (i.Inspection_Type__c && i.Inspection_Type__c.toLowerCase().includes(filter))
            );
        } else if (type === 'checklist') {
            return this.relatedChecklistItems.filter(c => !filter || 
                (c.Name && c.Name.toLowerCase().includes(filter)) || 
                (c.Category__c && c.Category__c.toLowerCase().includes(filter)) || 
                (c.Location__c && c.Location__c.toLowerCase().includes(filter))
            );
        } else if (type === 'snags') {
            return this.relatedSnags.filter(s => !filter || 
                (s.Name && s.Name.toLowerCase().includes(filter)) || 
                (s.Snag_Description__c && s.Snag_Description__c.toLowerCase().includes(filter)) || 
                (s.Responsible_Team__c && s.Responsible_Team__c.toLowerCase().includes(filter))
            );
        } else if (type === 'events') {
            return this.relatedEvents.filter(e => !filter || 
                (e.Subject && e.Subject.toLowerCase().includes(filter)) || 
                (e.Location && e.Location.toLowerCase().includes(filter))
            );
        } else if (type === 'tasks') {
            return this.relatedTasks.filter(t => !filter || 
                (t.Subject && t.Subject.toLowerCase().includes(filter)) || 
                (t.Status && t.Status.toLowerCase().includes(filter))
            );
        } else if (type === 'documents') {
            return this.relatedDocuments.filter(d => !filter || 
                (d.title && d.title.toLowerCase().includes(filter))
            );
        } else if (type === 'activities') {
            return this.relatedActivities.filter(a => !filter || 
                (a.Name && a.Name.toLowerCase().includes(filter)) || 
                (a.Event_Type__c && a.Event_Type__c.toLowerCase().includes(filter)) || 
                (a.Actor_Name__c && a.Actor_Name__c.toLowerCase().includes(filter)) ||
                (a.Details__c && a.Details__c.toLowerCase().includes(filter))
            );
        }
        return [];
    }

    get viewAllTotalCount() {
        return this.viewAllItems.length;
    }

    get isInspectionChecklistView() {
        return this.inspectionSubView === 'checklist';
    }

    get isInspectionSnagsView() {
        return this.inspectionSubView === 'snags';
    }

    get checklistSubViewBtnClass() {
        return `slds-button ${this.isInspectionChecklistView ? 'slds-button_brand' : 'slds-button_neutral'}`;
    }

    get snagsSubViewBtnClass() {
        return `slds-button ${this.isInspectionSnagsView ? 'slds-button_brand' : 'slds-button_neutral'}`;
    }

    get teamOptions() {
        return [
            { label: 'Civil & Finishes', value: 'Civil & Finishes' },
            { label: 'Electrical', value: 'Electrical' },
            { label: 'Plumbing', value: 'Plumbing' },
            { label: 'Doors & Windows', value: 'Doors & Windows' },
            { label: 'HVAC', value: 'HVAC' },
            { label: 'Fixtures', value: 'Fixtures' },
            { label: 'Painting', value: 'Painting' },
            { label: 'Carpentry', value: 'Carpentry' },
            { label: 'External Contractor', value: 'External Contractor' }
        ];
    }

    get selectedSnagFiles() {
        if (!this.selectedSnagId || !this.snagBoard?.snagEvidenceFiles) return [];
        return this.snagBoard.snagEvidenceFiles[this.selectedSnagId] || [];
    }

    get currentSnagExternalToken() {
        if (!this.selectedSnagId) return null;
        const all = [
            ...(this.snagBoard.openSnags || []),
            ...(this.snagBoard.inProgressSnags || []),
            ...(this.snagBoard.verificationSnags || []),
            ...(this.snagBoard.closedSnags || [])
        ];
        const s = all.find(item => item.Id === this.selectedSnagId);
        return s?.External_Token__c || null;
    }

    get unitAttributesList() {
        const list = [];
        if (this.unitSummary?.carpetArea) list.push({ label: 'Carpet Area', value: this.unitSummary.carpetArea });
        if (this.unitSummary?.saleableArea) list.push({ label: 'Saleable Area', value: this.unitSummary.saleableArea });
        if (this.unitSummary?.builtUpAreaSba) list.push({ label: 'Built-up SBA', value: this.unitSummary.builtUpAreaSba });
        if (this.unitSummary?.deckBalcony) list.push({ label: 'Balcony / Deck', value: this.unitSummary.deckBalcony });
        if (this.unitSummary?.terraceArea) list.push({ label: 'Terrace', value: this.unitSummary.terraceArea });
        if (this.unitSummary?.gardenArea) list.push({ label: 'Private Garden', value: this.unitSummary.gardenArea });
        if (this.unitSummary?.carParkings) list.push({ label: 'Allocated Parking', value: `${this.unitSummary.carParkings} Bay(s)` });
        return list;
    }

    // ── Picklists ───────────────────────────────────────────────────────
    get inspectionTypeOptions() {
        return [
            { label: 'Internal Quality Audit', value: 'Internal' },
            { label: 'Third Party Technical Audit', value: 'Third Party' },
            { label: 'Hybrid Joint Audit', value: 'Hybrid' }
        ];
    }

    get locationOptions() {
        return [
            { label: 'Living & Dining', value: 'Living & Dining' },
            { label: 'Master Bedroom', value: 'Master Bedroom' },
            { label: 'Bedroom 2', value: 'Bedroom 2' },
            { label: 'Bedroom 3', value: 'Bedroom 3' },
            { label: 'Kitchen', value: 'Kitchen' },
            { label: 'Balcony', value: 'Balcony' },
            { label: 'Bathroom', value: 'Bathroom' },
            { label: 'Utility', value: 'Utility' }
        ];
    }

    get categoryOptions() {
        return [
            { label: 'Civil & Finishes', value: 'Civil & Finishes' },
            { label: 'Electrical', value: 'Electrical' },
            { label: 'Plumbing', value: 'Plumbing' },
            { label: 'Doors & Windows', value: 'Doors & Windows' },
            { label: 'HVAC', value: 'HVAC' },
            { label: 'Fixtures', value: 'Fixtures' }
        ];
    }

    get severityOptions() {
        return [
            { label: 'Minor (Aesthetic / Touchup)', value: 'Minor' },
            { label: 'Major (Functional Defect)', value: 'Major' },
            { label: 'Critical (Blocker - Halts Handover)', value: 'Critical' }
        ];
    }

    get contractorOptions() {
        return [
            { label: 'Civil & Finishes Supervisor', value: 'Civil & Finishes Supervisor' },
            { label: 'Electrical Works Supervisor', value: 'Electrical Works Supervisor' },
            { label: 'Plumbing Works Supervisor', value: 'Plumbing Works Supervisor' },
            { label: 'Carpentry & Doors Lead', value: 'Carpentry & Doors Lead' },
            { label: 'Site Quality Manager', value: 'Site Quality Manager' }
        ];
    }

    get timeSlotOptions() {
        return [
            { label: '10:00 AM - 11:30 AM', value: '10:00 AM - 11:30 AM' },
            { label: '11:30 AM - 01:00 PM', value: '11:30 AM - 01:00 PM' },
            { label: '02:00 PM - 03:30 PM', value: '02:00 PM - 03:30 PM' },
            { label: '04:00 PM - 05:30 PM', value: '04:00 PM - 05:30 PM' }
        ];
    }

    // ── Target Date Save ────────────────────────────────────────────────
    handleTargetDateChange(event) {
        this.targetDateVal = event.target.value;
    }

    async handleSaveTargetDate() {
        if (!this.targetDateVal) return;
        this.isLoading = true;
        try {
            await updateTargetDate({ handoverId: this.handover.Id, targetDate: this.targetDateVal });
            this.showToast('Target Date Updated', `Target Handover Date set to ${this.targetDateVal}.`, 'success');
            this.closeEditTargetDateModal();
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Stage 1: Readiness -> Inspection ────────────────────────────────
    openEditTargetDateModal() {
        this.targetInspectionDateInput = this.targetInspectionDate || new Date().toISOString().slice(0, 10);
        this.isEditTargetDateModalOpen = true;
    }

    closeEditTargetDateModal() {
        this.isEditTargetDateModalOpen = false;
    }

    handleTargetInspectionDateInputChange(e) {
        this.targetInspectionDateInput = e.detail.value;
    }

    async handleSaveTargetInspectionDate() {
        if (!this.targetInspectionDateInput) {
            this.showToast('Validation Error', 'Target Inspection Completion Date is required.', 'warning');
            return;
        }
        this.isSavingTargetDate = true;
        try {
            await updateTargetInspectionDate({
                handoverId: this.handover.Id,
                targetDate: this.targetInspectionDateInput
            });
            this.targetInspectionDate = this.targetInspectionDateInput;
            const d = new Date(this.targetInspectionDateInput);
            this.targetInspectionDateFormatted = d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
            this.showToast('Success', 'Target Inspection Completion Date saved.', 'success');
            this.closeEditTargetDateModal();
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error', e.body?.message || e.message, 'error');
        } finally {
            this.isSavingTargetDate = false;
        }
    }

    openStartInspectionModal() {
        if (this.readiness && this.readiness.canStartInspection === false) {
            this.showToast(
                'Readiness Gate Incomplete',
                this.readiness.blockingReason || 'Cannot start inspection until all readiness gates are complete.',
                'error'
            );
            return;
        }
        this.inspectorName = this.handoverOwnerName || 'Quality Audit Team';
        this.targetInspectionDateInput = this.targetInspectionDate || new Date().toISOString().slice(0, 10);
        this.showStartInspectionModal = true;
    }

    closeStartInspectionModal() {
        this.showStartInspectionModal = false;
    }

    handleInspectionTypeChange(e) { this.inspectionType = e.detail.value; }
    handleInspectorNameChange(e) { this.inspectorName = e.detail.value; }
    handleInspectorCompanyChange(e) { this.inspectorCompany = e.detail.value; }
    handleInspectorEmailChange(e) { this.inspectorEmail = e.detail.value; }

    async handleSaveStartInspection() {
        if (!this.inspectorName) {
            this.showToast('Validation Error', 'Inspector Name is required.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await startInspection({
                handoverId: this.handover.Id,
                inspectionType: this.inspectionType || 'Internal',
                inspectorName: this.inspectorName,
                inspectorCompany: this.inspectorCompany || 'Quality Audit Team',
                inspectorEmail: this.inspectorEmail,
                inspectionDate: this.targetInspectionDateInput || null
            });
            this.showToast('Inspection Started', `Inspection round initiated with ${this.inspectorName}.`, 'success');
            this.closeStartInspectionModal();
            this.currentActiveStage = 'Inspection';
            window.dispatchEvent(new CustomEvent('handoverstagechange', {
                detail: { stage: 'Inspection', recordId: this.recordId }
            }));
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error Starting Inspection', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Stage 2: Inspection Checklist Item Actions ─────────────────────
    async handleSetPass(event) {
        const itemId = event.currentTarget ? event.currentTarget.dataset.id : event.target.dataset.id;
        await this.applyItemResult(itemId, 'Pass');
    }

    handleSetIssue(event) {
        const itemId = event.currentTarget ? event.currentTarget.dataset.id : event.target.dataset.id;
        this.selectedChecklistItemId = itemId;
        let foundItm = null;
        for (const grp of this.checklistGroups) {
            const itm = grp.items.find(i => i.Id === itemId);
            if (itm) { foundItm = itm; break; }
        }
        if (foundItm) {
            this.newSnagLocation = foundItm.Location__c || 'Living & Dining';
            this.newSnagCategory = foundItm.Category__c || 'Civil & Finishes';
            this.newSnagDesc = `Issue identified on ${foundItm.Name} in ${this.newSnagLocation}`;
            this.newSnagSeverity = 'Major';
        }
        this.showRaiseSnagModal = true;
    }

    async handleSetNA(event) {
        const itemId = event.currentTarget ? event.currentTarget.dataset.id : event.target.dataset.id;
        await this.applyItemResult(itemId, 'N/A');
    }

    async applyItemResult(itemId, result) {
        if (!itemId) return;

        let previousResult = null;
        let itemFound = false;

        const updatedGroups = this.checklistGroups.map(grp => {
            const updatedItems = grp.items.map(itm => {
                if (itm.Id === itemId) {
                    previousResult = itm.Result__c;
                    itemFound = true;
                    return {
                        ...itm,
                        Result__c: result
                    };
                }
                return itm;
            });
            return {
                ...grp,
                items: updatedItems
            };
        });

        if (itemFound) {
            this.checklistGroups = this.formatChecklistGroups(updatedGroups);
        }

        try {
            await updateChecklistItemStatus({ itemId, result, comments: '' });
        } catch (e) {
            if (previousResult !== null) {
                const rolledBackGroups = this.checklistGroups.map(grp => ({
                    ...grp,
                    items: grp.items.map(itm => itm.Id === itemId ? { ...itm, Result__c: previousResult } : itm)
                }));
                this.checklistGroups = this.formatChecklistGroups(rolledBackGroups);
            }
            this.showToast('Error Updating Checklist Item', e.body?.message || e.message, 'error');
        }
    }

    openAddChecklistItemModal() {
        this.newItemName = '';
        this.newItemCategory = 'Civil & Finishes';
        this.newItemLocation = 'Living & Dining';
        this.showAddChecklistItemModal = true;
    }

    closeAddChecklistItemModal() {
        this.showAddChecklistItemModal = false;
    }

    handleNewItemNameChange(e) { this.newItemName = e.detail.value; }
    handleNewItemCategoryChange(e) { this.newItemCategory = e.detail.value; }
    handleNewItemLocationChange(e) { this.newItemLocation = e.detail.value; }

    async handleSaveChecklistItem() {
        if (!this.newItemName) return;
        this.isLoading = true;
        try {
            await addChecklistItem({
                inspectionId: this.currentInspection.Id,
                name: this.newItemName,
                category: this.newItemCategory,
                location: this.newItemLocation
            });
            this.showToast('Line Item Added', `Check item "${this.newItemName}" added.`, 'success');
            this.closeAddChecklistItemModal();
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error Adding Item', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeleteChecklistItem(event) {
        const itemId = event.target.dataset.id;
        if (!itemId) return;
        this.isLoading = true;
        try {
            await deleteChecklistItem({ itemId });
            this.showToast('Item Removed', 'Checklist line item removed from audit.', 'info');
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error Removing Item', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleDownloadInspectionReport() {
        if (!this.currentInspection) return;
        this.isLoading = true;
        try {
            const res = await generateInspectionReport({ inspectionId: this.currentInspection.Id });
            this.showToast('Report Generated', `Inspection report prepared: ${res.fileName}`, 'success');
            if (res.downloadUrl) {
                const downloadLink = document.createElement('a');
                downloadLink.href = res.downloadUrl;
                downloadLink.download = res.fileName || `Inspection_Report_${this.currentInspection.Name}.pdf`;
                document.body.appendChild(downloadLink);
                downloadLink.click();
                downloadLink.remove();
            } else if (res.pdfUrl) {
                window.open(res.pdfUrl, '_blank');
            }
        } catch (e) {
            this.showToast('Error Generating Report', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleCompleteInspection() {
        if (this.pendingChecklistCount > 0) {
            this.showToast('Checklist Incomplete', `Please verify all checklist items before completing inspection (${this.pendingChecklistCount} items pending).`, 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await completeInspection({ inspectionId: this.currentInspection.Id });
            this.showToast('Inspection Completed', 'Inspection locked and finalized.', 'success');
            await this.loadWorkspace();
            if (this.recordId) {
                notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            }
        } catch (e) {
            this.showToast('Error Completing Inspection', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Stage 3: Snag Management & Verification ─────────────────────────
    openRaiseSnagModal() {
        this.selectedChecklistItemId = null;
        this.newSnagLocation = 'Living & Dining';
        this.newSnagCategory = 'Civil & Finishes';
        this.newSnagDesc = '';
        this.newSnagSeverity = 'Minor';
        this.newSnagTeam = 'Civil & Finishes';
        this.newSnagContractor = '';
        this.newSnagDueDate = null;
        this.showRaiseSnagModal = true;
    }

    closeRaiseSnagModal() {
        this.showRaiseSnagModal = false;
        this.selectedChecklistItemId = null;
    }

    handleSnagLocationChange(e) { this.newSnagLocation = e.detail.value; }
    handleSnagCategoryChange(e) { this.newSnagCategory = e.detail.value; }
    handleSnagDescChange(e) { this.newSnagDesc = e.detail.value; }
    handleSnagSeverityChange(e) { this.newSnagSeverity = e.detail.value; }
    handleSnagContractorChange(e) { this.newSnagContractor = e.detail.value; }
    handleSnagDueDateChange(e) { this.newSnagDueDate = e.detail.value; }

        handleMainTabProcess() { this.activeMainTab = 'process'; }
    handleMainTabRelated() { this.activeMainTab = 'related'; }
    handleSwitchToChecklistSubView() { this.inspectionSubView = 'checklist'; }
    handleSwitchToSnagsSubView() { this.inspectionSubView = 'snags'; }
    handleSnagTeamChange(e) { this.newSnagTeam = e.detail.value; }
    handleResponsibleTeamChange(e) { this.selectedResponsibleTeam = e.detail.value; }
    handleAssignmentRemarksChange(e) { this.assignmentRemarks = e.detail.value; }

    handleCopySnagExternalLink() {
        if (this.currentSnagExternalToken) {
            const url = `${window.location.origin}/services/apexrest/externalSnagResolver?token=${this.currentSnagExternalToken}`;
            navigator.clipboard.writeText(url);
            this.showToast('Link Copied', 'External resolver portal link copied to clipboard.', 'info');
        }
    }

    handleKeysSetsCountChange(e) { this.keysSetsCount = parseInt(e.detail.value, 10); }
    handleAccessCardsCountChange(e) { this.accessCardsCount = parseInt(e.detail.value, 10); }
    handleAccessDetailsChange(e) { this.accessDetails = e.detail.value; }
    handleAckDateTimeChange(e) { this.ackDateTime = e.detail.value; }

    handleSnagUploadFinished(event) {
        const uploadedFiles = event.detail.files || [];
        this.showToast('Evidence Uploaded', `${uploadedFiles.length} file(s) attached to Snag defect record.`, 'success');
        this.loadWorkspace();
    }

    handleHandoverDocUploadFinished(event) {
        const uploadedFiles = event.detail.files || [];
        this.uploadedHandoverDocFiles = [...this.uploadedHandoverDocFiles, ...uploadedFiles];
        this.showToast('Documents Uploaded', `${uploadedFiles.length} handover supporting document(s) uploaded.`, 'success');
    }

    handleSignedAckUploadFinished(event) {
        const uploadedFiles = event.detail.files || [];
        this.uploadedSignedAckFiles = [...this.uploadedSignedAckFiles, ...uploadedFiles];
        this.showToast('Signed Form Uploaded', 'Customer signed possession acknowledgement form uploaded.', 'success');
    }

    toggleActivityExpand(event) {
        const actId = event.currentTarget ? event.currentTarget.dataset.id : event.target.dataset.id;
        this.activityTimeline = this.activityTimeline.map(act => {
            if (act.id === actId) {
                const nextExpanded = !act.isExpanded;
                return {
                    ...act,
                    isExpanded: nextExpanded,
                    chevronIcon: nextExpanded ? 'utility:chevrondown' : 'utility:chevronright'
                };
            }
            return act;
        });
    }

    async handleSaveSnag() {
        if (!this.newSnagDesc) {
            this.showToast('Validation Error', 'Snag description is required.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await raiseManualSnagWithTeam({
                handoverId: this.handover.Id,
                description: this.newSnagDesc,
                category: this.newSnagCategory,
                location: this.newSnagLocation,
                severity: this.newSnagSeverity,
                responsibleTeam: this.newSnagTeam || this.newSnagCategory,
                assignedToName: this.newSnagContractor,
                dueDate: this.newSnagDueDate || null,
                checklistItemId: this.selectedChecklistItemId || null
            });
            this.showToast('Snag Raised', `Snag logged for ${this.newSnagLocation} and assigned to ${this.newSnagTeam}.`, 'success');
            this.closeRaiseSnagModal();
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error Raising Snag', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleOpenAssignModal(event) {
        this.selectedSnagId = event.target.dataset.id;
        this.showAssignModal = true;
    }

    closeAssignModal() {
        this.showAssignModal = false;
        this.selectedSnagId = null;
    }

    handleContractorSelectChange(e) {
        this.selectedContractor = e.detail.value;
    }

    async handleSaveAssignContractor() {
        if (!this.selectedSnagId) return;
        this.isLoading = true;
        try {
            await assignSnagOwnerWithTeam({
                snagId: this.selectedSnagId,
                ownerId: null,
                ownerName: this.selectedContractor,
                responsibleTeam: this.selectedResponsibleTeam,
                remarks: this.assignmentRemarks || `Assigned to ${this.selectedContractor} (${this.selectedResponsibleTeam})`
            });
            this.showToast('Owner & Team Assigned', `Assigned to ${this.selectedContractor} (${this.selectedResponsibleTeam}).`, 'success');
            this.closeAssignModal();
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error Assigning Owner', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    openResolveModal(event) {
        this.selectedSnagId = event.target.dataset.id;
        this.resolutionComments = '';
        this.evidenceUrl = '';
        this.showResolveSnagModal = true;
    }

    closeResolveModal() {
        this.showResolveSnagModal = false;
        this.selectedSnagId = null;
    }

    handleEvidenceUrlChange(e) { this.evidenceUrl = e.detail.value; }
    handleResolutionCommentsChange(e) { this.resolutionComments = e.detail.value; }

    async handleSaveResolveSnag() {
        const hasFiles = this.selectedSnagFiles.length > 0;
        if (!hasFiles && !this.evidenceUrl) {
            this.showToast('Validation Error', 'Please upload at least one photo or video evidence file before submitting for verification.', 'warning');
            return;
        }
        if (!this.resolutionComments) {
            this.showToast('Validation Error', 'Rectification remarks / work details are required.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await submitSnagForVerification({
                snagId: this.selectedSnagId,
                evidenceUrl: this.evidenceUrl || 'Salesforce File Uploaded',
                remarks: this.resolutionComments
            });
            this.showToast('Submitted for Verification', 'Snag submitted to Approver for sign-off.', 'success');
            this.closeResolveModal();
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error Submitting Verification', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleApproveSnag(event) {
        const snagId = event.target.dataset.id;
        if (!snagId) return;
        this.isLoading = true;
        try {
            await verifySnag({ snagId, approved: true, comments: 'Rectification verified and signed off.' });
            this.showToast('Snag Closed', 'Defect verified and officially marked Closed.', 'success');
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error Approving Snag', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleOpenReopenModal(event) {
        this.selectedSnagId = event.target.dataset.id;
        this.reopenReason = '';
        this.showReopenModal = true;
    }

    closeReopenModal() {
        this.showReopenModal = false;
        this.selectedSnagId = null;
    }

    handleReopenReasonChange(e) { this.reopenReason = e.detail.value; }

    async handleSaveReopenSnag() {
        if (!this.reopenReason) {
            this.showToast('Validation Error', 'Rejection reason is required.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await verifySnag({ snagId: this.selectedSnagId, approved: false, comments: this.reopenReason });
            this.showToast('Snag Reopened', 'Snag verification rejected. Returned to In Progress for rework.', 'warning');
            this.closeReopenModal();
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error Rejecting Snag', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleProceedToAppointment() {
        if (this.hasUnresolvedSnags) {
            this.showToast('Snags Pending', `Cannot advance to Appointment while ${this.unresolvedSnagsCount} snags are unresolved or unverified.`, 'warning');
            return;
        }
        this.currentActiveStage = 'Appointment';
    }

    // ── Stage 4: Appointment & Handover ────────────────────────────────
    handleAptDateChange(e) { this.aptDate = e.detail.value; }
    handleAptSlotChange(e) { this.aptSlot = e.detail.value; }
    handleAptLocationChange(e) { this.aptLocation = e.detail.value; }
    handleAptInstructionsChange(e) { this.aptInstructions = e.detail.value; }

    async handleSendCustomerInvite() {
        if (!this.aptDate || !this.aptSlot || !this.aptLocation) {
            this.showToast('Validation Error', 'Please complete Date, Slot, and Location.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            const [startTime, endTime] = this.aptSlot.split(' - ');
            await scheduleAppointment({
                handoverId: this.handover.Id,
                apptDate: this.aptDate,
                startTime: startTime || '10:00 AM',
                endTime: endTime || '11:30 AM',
                location: this.aptLocation,
                customerInstructions: this.aptInstructions
            });
            this.showToast('Invite Dispatched', `Customer invitation dispatched to ${this.customerEmail} and calendar event created.`, 'success');
            await this.loadWorkspace();
            if (this.recordId) {
                notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            }
        } catch (e) {
            this.showToast('Error Scheduling Appointment', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    openRescheduleModal() {
        this.rescheduleDate = this.handover?.Appointment_Date__c || this.aptDate;
        this.rescheduleSlot = this.handover?.Appointment_Time_Slot__c || this.aptSlot;
        this.rescheduleLocation = this.handover?.Appointment_Location__c || this.aptLocation;
        this.showRescheduleModal = true;
    }

    closeRescheduleModal() {
        this.showRescheduleModal = false;
    }

    handleRescheduleDateChange(e) { this.rescheduleDate = e.detail.value; }
    handleRescheduleSlotChange(e) { this.rescheduleSlot = e.detail.value; }
    handleRescheduleLocationChange(e) { this.rescheduleLocation = e.detail.value; }

    async handleSaveRescheduleAppointment() {
        if (!this.rescheduleDate || !this.rescheduleSlot || !this.rescheduleLocation) {
            this.showToast('Validation Error', 'Please complete all fields.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            const [startTime, endTime] = this.rescheduleSlot.split(' - ');
            await rescheduleAppointment({
                handoverId: this.handover.Id,
                newDate: this.rescheduleDate,
                newStartTime: startTime || '11:30 AM',
                newEndTime: endTime || '01:00 PM',
                newLocation: this.rescheduleLocation
            });
            this.showToast('Appointment Rescheduled', 'Updated invitation sent to customer and calendar event adjusted.', 'success');
            this.closeRescheduleModal();
            await this.loadWorkspace();
            if (this.recordId) {
                notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            }
        } catch (e) {
            this.showToast('Error Rescheduling', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleKeysHandedOverChange(e) { this.keysHandedOver = e.target.checked; }
    handleCardsHandedOverChange(e) { this.cardsHandedOver = e.target.checked; }
    handleDocsHandedOverChange(e) { this.docsHandedOver = e.target.checked; }
    handleMeterReadingsCapturedChange(e) { this.meterReadingsCaptured = e.target.checked; }
    handleCustomerAcknowledgedChange(e) { this.customerAcknowledged = e.target.checked; }
    handleFinalRemarksChange(e) { this.finalRemarks = e.detail.value; }

    async handleCompletePhysicalHandover() {
        if (!this.keysHandedOver || !this.docsHandedOver || !this.customerAcknowledged) {
            this.showToast('Checklist Incomplete', 'Please confirm Keys, Required Documents, and Customer Acknowledgement before completing Handover.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await completePhysicalHandover({
                handoverId: this.handover.Id,
                keysCount: 3,
                cardsCount: 2,
                docsHandedOver: this.docsHandedOver,
                electricityReading: 'EL-1002',
                waterReading: 'WM-1002',
                gasReading: 'GP-1002',
                customerAcknowledged: this.customerAcknowledged,
                feedbackRating: 5,
                feedbackRemarks: this.finalRemarks
            });
            this.showToast('Handover Completed', 'Possession transferred, documentation issued, and unit moved to Completed.', 'success');
            this.currentActiveStage = 'Completed';
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error Completing Handover', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Activity Timeline & Mini-Composer Actions ───────────────────────
    handleActivityEmailToChange(e) { this.activityEmailTo = e.detail.value; }
    handleActivityEmailSubjectChange(e) { this.activityEmailSubject = e.detail.value; }
    handleActivityEmailBodyChange(e) { this.activityEmailBody = e.detail.value; }

    handleActivityTaskSubjectChange(e) { this.activityTaskSubject = e.detail.value; }
    handleActivityTaskDueDateChange(e) { this.activityTaskDueDate = e.detail.value; }
    handleActivityTaskPriorityChange(e) { this.activityTaskPriority = e.detail.value; }
    handleActivityTaskDescChange(e) { this.activityTaskDescription = e.detail.value; }

    handleActivityCallSubjectChange(e) { this.activityCallSubject = e.detail.value; }
    handleActivityCallCommentsChange(e) { this.activityCallComments = e.detail.value; }

    async handleRefreshActivities() {
        await this.loadWorkspace();
        this.showToast('Refreshed', 'Activity timeline refreshed.', 'info');
    }

    async handleSendEmail() {
        if (!this.activityEmailTo || !this.activityEmailSubject) {
            this.showToast('Validation Error', 'Recipient Email and Subject are required.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await sendActivityEmail({
                handoverId: this.handover.Id,
                toEmail: this.activityEmailTo,
                subject: this.activityEmailSubject,
                body: this.activityEmailBody || ''
            });
            this.showToast('Email Sent', `Email sent to ${this.activityEmailTo} and recorded in timeline.`, 'success');
            this.activityEmailSubject = '';
            this.activityEmailBody = '';
            this.closeMiniComposer();
            await this.loadWorkspace();
        } catch (err) {
            this.showToast('Error Sending Email', err?.body?.message || err.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleCreateTask() {
        if (!this.activityTaskSubject) {
            this.showToast('Validation Error', 'Task Subject is required.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await createActivityTask({
                handoverId: this.handover.Id,
                subject: this.activityTaskSubject,
                dueDate: this.activityTaskDueDate || null,
                priority: this.activityTaskPriority || 'Normal',
                description: this.activityTaskDescription || ''
            });
            this.showToast('Task Created', 'Task successfully scheduled and linked to Handover.', 'success');
            this.activityTaskSubject = '';
            this.activityTaskDescription = '';
            this.closeMiniComposer();
            await this.loadWorkspace();
        } catch (err) {
            this.showToast('Error Creating Task', err?.body?.message || err.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleLogCall() {
        if (!this.activityCallSubject) {
            this.showToast('Validation Error', 'Call Subject is required.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await logActivityCall({
                handoverId: this.handover.Id,
                subject: this.activityCallSubject,
                comments: this.activityCallComments || 'Customer call logged.'
            });
            this.showToast('Call Logged', 'Call activity successfully recorded.', 'success');
            this.activityCallComments = '';
            this.closeMiniComposer();
            await this.loadWorkspace();
        } catch (err) {
            this.showToast('Error Logging Call', err?.body?.message || err.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleCompleteTask(e) {
        const taskId = e.target.dataset.id;
        if (!taskId) return;
        this.isLoading = true;
        try {
            await completeActivityTask({ taskId });
            this.showToast('Task Completed', 'Task has been marked as Completed.', 'success');
            await this.loadWorkspace();
        } catch (err) {
            this.showToast('Error Completing Task', err?.body?.message || err.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Handover Owner Change ──────────────────────────────────────────
    async openChangeOwnerModal() {
        this.selectedNewOwnerId = null;
        this.selectedNewOwnerName = '';
        this.ownerSearchTerm = '';
        this.searchedUsers = [];
        this.showChangeOwnerModal = true;
        try {
            const users = await searchUsers({ searchTerm: '' });
            this.searchedUsers = (users || []).map(u => ({
                ...u,
                isSelected: u.Id === this.handover?.Handover_Owner__c
            }));
        } catch (e) {
            console.error('Error fetching initial users', e);
        }
    }

    closeChangeOwnerModal() {
        this.showChangeOwnerModal = false;
        this.searchedUsers = [];
        this.selectedNewOwnerId = null;
        this.selectedNewOwnerName = '';
    }

    async handleOwnerSearchChange(e) {
        this.ownerSearchTerm = e.detail.value;
        try {
            const users = await searchUsers({ searchTerm: this.ownerSearchTerm });
            this.searchedUsers = (users || []).map(u => ({
                ...u,
                isSelected: u.Id === this.selectedNewOwnerId
            }));
        } catch (err) {
            console.error('Error searching users', err);
        }
    }

    handleSelectNewOwner(e) {
        const userId = e.currentTarget.dataset.id;
        const userName = e.currentTarget.dataset.name;
        this.selectedNewOwnerId = userId;
        this.selectedNewOwnerName = userName;
        this.searchedUsers = this.searchedUsers.map(u => ({
            ...u,
            isSelected: u.Id === userId
        }));
    }

    async handleSaveChangeOwner() {
        if (!this.selectedNewOwnerId) return;
        this.isLoading = true;
        try {
            await updateHandoverOwner({
                handoverId: this.handover.Id,
                newOwnerId: this.selectedNewOwnerId
            });
            this.showToast('Owner Updated', `Handover Owner updated to ${this.selectedNewOwnerName}. Audit task logged.`, 'success');
            this.closeChangeOwnerModal();
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error Updating Owner', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── External Inspection Modal & Submission ────────────────────────
    openExternalInspectionModal() {
        this.externalAuditorName = this.inspectorName || 'Third-Party Technical Auditor';
        this.externalAuditorCompany = this.inspectorCompany || 'Independent Technical Services';
        this.externalOverallComments = '';

        this.externalChecklistDraft = this.allChecklistItems.map(itm => {
            const isPass = itm.Result__c === 'Pass';
            const isIssue = itm.Result__c === 'Issue Found' || itm.Result__c === 'Issue';
            const isNA = itm.Result__c === 'N/A';
            return {
                id: itm.Id,
                name: itm.Name,
                category: itm.Category__c || 'Civil & Finishes',
                location: itm.Location__c || 'Living & Dining',
                result: itm.Result__c || 'Pending',
                isPass,
                isIssue,
                isNA,
                passBtnClass: `chk-btn-pass ${isPass ? 'active' : ''}`,
                issueBtnClass: `chk-btn-issue ${isIssue ? 'active' : ''}`,
                naBtnClass: `chk-btn-na ${isNA ? 'active' : ''}`
            };
        });

        this.showExternalFormModal = true;
    }

    closeExternalFormModal() {
        this.showExternalFormModal = false;
    }

    handleExtAuditorNameChange(e) { this.externalAuditorName = e.detail.value; }
    handleExtAuditorCompanyChange(e) { this.externalAuditorCompany = e.detail.value; }
    handleExtOverallCommentsChange(e) { this.externalOverallComments = e.detail.value; }

    handleSetExternalItemResult(event) {
        const id = event.target.dataset.id;
        const result = event.target.dataset.result;
        this.externalChecklistDraft = this.externalChecklistDraft.map(item => {
            if (item.id === id) {
                const isPass = result === 'Pass';
                const isIssue = result === 'Issue Found';
                const isNA = result === 'N/A';
                return {
                    ...item,
                    result,
                    isPass,
                    isIssue,
                    isNA,
                    passBtnClass: `chk-btn-pass ${isPass ? 'active' : ''}`,
                    issueBtnClass: `chk-btn-issue ${isIssue ? 'active' : ''}`,
                    naBtnClass: `chk-btn-na ${isNA ? 'active' : ''}`
                };
            }
            return item;
        });
    }

    async handleSubmitExternalInspection() {
        if (!this.currentInspectionToken || this.currentInspectionToken === 'N/A') {
            this.showToast('No External Token', 'Please initialize an inspection before external submission.', 'warning');
            return;
        }
        if (!this.externalAuditorName) {
            this.showToast('Validation Error', 'Auditor Name is required.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            const itemsPayload = this.externalChecklistDraft.map(itm => ({
                id: itm.id,
                name: itm.name,
                category: itm.category,
                location: itm.location,
                result: itm.result || 'Pass',
                comments: itm.result === 'Issue Found' ? `Issue recorded by ${this.externalAuditorName}` : ''
            }));

            await submitExternalInspection({
                token: this.currentInspectionToken,
                inspectorName: this.externalAuditorName,
                inspectorCompany: this.externalAuditorCompany,
                overallComments: this.externalOverallComments,
                itemsJson: JSON.stringify(itemsPayload)
            });

            this.showToast('External Inspection Submitted', 'Audit results processed. Defects logged and stage updated.', 'success');
            this.closeExternalFormModal();
            await this.loadWorkspace();
        } catch (e) {
            this.showToast('Error Submitting Inspection', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCopyExternalUrl() {
        const text = this.fullExternalInspectionUrl;
        try {
            navigator.clipboard.writeText(text);
            this.showToast('Copied', 'Secure third-party auditor link copied to clipboard.', 'success');
        } catch (e) {
            this.showToast('Link', text, 'info');
        }
    }

    navigateToUnit() {
        if (this.handover?.Unit__c) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.handover.Unit__c,
                    actionName: 'view'
                }
            });
        }
    }

    openEditTargetDateModal() {
        this.showEditTargetDateModal = true;
    }

    closeEditTargetDateModal() {
        this.showEditTargetDateModal = false;
    }

    handleSelectStage(event) {
        const targetStage = event.currentTarget.dataset.stage;
        if (!targetStage) return;
        const targetIdx = this.STAGE_ORDER.indexOf(targetStage);
        const recordIdx = this.recordStageIndex;

        // Navigation rules:
        // 1. Can always navigate to previous or current stage (targetIdx <= recordIdx)
        // 2. Can switch freely between Inspection (idx 1) and Snag Resolution (idx 2) once inspection has started (recordIdx >= 1)
        // 3. Appointment & Handover (idx 3) is unlocked if Inspection is completed and all snags are closed & verified
        // 4. Completed (idx 4) is locked until the Handover record itself reaches Completed (recordIdx === 4)
        if (targetIdx > recordIdx) {
            const isInspectionOrResolution = (recordIdx >= 1 && (targetIdx === 1 || targetIdx === 2));
            const isAppointmentUnlocked = (targetIdx === 3 && this.isInspectionCompleted && !this.hasUnresolvedSnags);

            if (!isInspectionOrResolution && !isAppointmentUnlocked) {
                let reason = `Stage "${targetStage}" is locked until previous stage requirements are satisfied.`;
                if (targetIdx === 1) {
                    reason = 'Please click "Start Inspection" in the header to start the inspection first.';
                } else if (targetIdx === 2) {
                    reason = 'Snag Resolution unlocks once an inspection is started.';
                } else if (targetIdx === 3) {
                    reason = 'Appointment & Handover unlocks once the Inspection is completed and all Snags are closed and verified.';
                } else if (targetIdx === 4) {
                    reason = 'Completed stage unlocks once the Handover is completed.';
                }
                this.showToast('Stage Locked', reason, 'info');
                return;
            }
        }
        this.currentActiveStage = targetStage;
        this.activeMainTab = 'process';
        window.dispatchEvent(new CustomEvent('handoverstagechange', {
            detail: { stage: targetStage, recordId: this.recordId }
        }));
    }

    handleReturnToActiveStage() {
        this.currentActiveStage = this.normalizedRecordStage;
        this.activeMainTab = 'process';
        window.dispatchEvent(new CustomEvent('handoverstagechange', {
            detail: { stage: this.currentActiveStage, recordId: this.recordId }
        }));
    }

    handlePreviewDocument(event) {
        const docId = event.currentTarget.dataset.id || event.target.dataset.id;
        if (!docId) {
            this.showToast('Document Preview', 'No document ID available for preview.', 'warning');
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: docId
            }
        });
    }

    handleDownloadDocument(event) {
        const docId = event.currentTarget.dataset.id || event.target.dataset.id;
        if (!docId) {
            this.showToast('Document Download', 'No document ID available for download.', 'warning');
            return;
        }
        const downloadUrl = `/sfc/servlet.shepherd/document/download/${docId}`;
        window.open(downloadUrl, '_blank');
    }


    // ── FORMAL INSPECTION REPORT MODAL ─────────────────────────────────────────
    async handlePreviewInspectionReport() {
        if (!this.currentInspection) {
            this.showToast('Inspection', 'No inspection record found to generate report.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            const data = await getFormalInspectionReportData({ inspectionId: this.currentInspection.Id });
            this.formalReportData = data;
            this.showInspectionReportModal = true;
        } catch (e) {
            this.showToast('Report Error', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCloseInspectionReportModal() {
        this.showInspectionReportModal = false;
    }

    handleDownloadReportFromModal() {
        // Fall back to PDF generation for download
        if (this.currentInspection) {
            generateInspectionReport({ inspectionId: this.currentInspection.Id })
                .then(res => {
                    if (res && res.downloadUrl) window.open(res.downloadUrl, '_blank');
                    else if (res && res.contentDocumentId) {
                        this[NavigationMixin.Navigate]({
                            type: 'standard__namedPage',
                            attributes: { pageName: 'filePreview' },
                            state: { selectedRecordId: res.contentDocumentId }
                        });
                    }
                })
                .catch(e => this.showToast('Download Error', e.body?.message || e.message, 'error'));
        }
    }

    handleOpenShareReportModal() {
        this.shareReportEmails = '';
        this.shareReportNote = '';
        this.showShareReportModal = true;
    }

    handleCloseShareReportModal() {
        this.showShareReportModal = false;
    }

    handleShareReportEmailChange(e) {
        this.shareReportEmails = e.detail.value;
    }

    handleShareReportNoteChange(e) {
        this.shareReportNote = e.detail.value;
    }

    async handleShareInspectionReport() {
        if (!this.shareReportEmails || !this.shareReportEmails.trim()) {
            this.showToast('Share Report', 'Please enter at least one recipient email.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await shareInspectionReport({
                inspectionId: this.currentInspection.Id,
                recipientEmails: this.shareReportEmails,
                note: this.shareReportNote
            });
            this.showToast('Report Shared', `Inspection report sent to ${this.shareReportEmails}.`, 'success');
            this.showShareReportModal = false;
        } catch (e) {
            this.showToast('Share Error', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── SHARE SNAG WITH EXTERNAL USER ──────────────────────────────────────────
    handleOpenShareSnagModal(event) {
        this.shareSnagId = event.currentTarget.dataset.id || event.target.dataset.id;
        this.shareSnagEmail = '';
        this.shareSnagNote = '';
        this.showShareSnagModal = true;
    }

    handleCloseShareSnagModal() {
        this.showShareSnagModal = false;
        this.shareSnagId = null;
    }

    handleShareSnagEmailChange(e) {
        this.shareSnagEmail = e.detail.value;
    }

    handleShareSnagNoteChange(e) {
        this.shareSnagNote = e.detail.value;
    }

    async handleShareSnag() {
        if (!this.shareSnagId) {
            this.showToast('Share Snag', 'No snag selected.', 'warning');
            return;
        }
        if (!this.shareSnagEmail || !this.shareSnagEmail.trim()) {
            this.showToast('Share Snag', 'Please enter a recipient email address.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await shareSnagWithExternalUser({
                snagId: this.shareSnagId,
                recipientEmail: this.shareSnagEmail,
                note: this.shareSnagNote
            });
            this.showToast('Snag Shared', `Snag details shared with ${this.shareSnagEmail}.`, 'success');
            this.showShareSnagModal = false;
        } catch (e) {
            this.showToast('Share Error', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleNavigateToRecord(event) {
        event.preventDefault();
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.id;
        if (recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    actionName: 'view'
                }
            });
        }
    }

    handleInitiateRental() {
        const bookingId = this.relatedBooking?.Id || this.handover?.Booking__c;
        if (bookingId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: bookingId,
                    actionName: 'view'
                }
            });
            this.showToast('Rental Management', 'Navigating to Booking record. Use the "Initiate Rental" button in the header.', 'info');
        } else {
            this.showToast('Booking Not Linked', 'No Booking record is linked to this Handover to initiate Rental.', 'warning');
        }
    }

    handleNavigateToBooking() {
        const bookingId = this.relatedBooking?.Id || this.handover?.Booking__c;
        if (bookingId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: bookingId,
                    actionName: 'view'
                }
            });
        }
    }

    toggleSection(event) {
        const sec = event.currentTarget.dataset.section;
        if (sec) {
            this.collapsedSections = {
                ...this.collapsedSections,
                [sec]: !this.collapsedSections[sec]
            };
        }
    }

    openViewAllModal(event) {
        const type = event.currentTarget.dataset.type;
        let title = '';
        let icon = 'standard:record';
        if (type === 'inspections') {
            title = 'Inspections';
            icon = 'standard:survey';
        } else if (type === 'checklist') {
            title = 'Inspection Checklist Items';
            icon = 'standard:task2';
        } else if (type === 'snags') {
            title = 'Snags & Defects';
            icon = 'standard:incident';
        } else if (type === 'events') {
            title = 'Appointments & Events';
            icon = 'standard:event';
        } else if (type === 'tasks') {
            title = 'Tasks';
            icon = 'standard:task';
        } else if (type === 'documents') {
            title = 'Documents & Files';
            icon = 'standard:file';
        } else if (type === 'activities') {
            title = 'Handover Activity History';
            icon = 'standard:custom_notification';
        }
        this.viewAllConfig = {
            title,
            icon,
            type,
            filterText: ''
        };
        this.showViewAllModal = true;
    }

    closeViewAllModal() {
        this.showViewAllModal = false;
    }

    handleViewAllFilter(event) {
        this.viewAllConfig = {
            ...this.viewAllConfig,
            filterText: event.target.value
        };
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}