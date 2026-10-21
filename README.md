# Salesforce Residential Handover Module

[![Salesforce DX](https://img.shields.io/badge/Salesforce%20DX-v64.0-blue.svg)](https://developer.salesforce.com/)
[![Tests](https://img.shields.io/badge/Apex%20Tests-11%2F11%20Passed%20(100%25)-brightgreen.svg)]()
[![LWC](https://img.shields.io/badge/LWC-Enterprise%20Journey-orange.svg)]()

A complete, production-grade Salesforce solution for residential property developers. Manages the end-to-end customer handover lifecycle from unit readiness clearance, room-by-room quality audit, and subcontractor snag rectification, to appointment scheduling, physical key handover, meter readings, and automated possession pack generation.

---

## Table of Contents
1. [Project Overview](#project-overview)
2. [Handover Business Process & Stage Progression](#handover-business-process--stage-progression)
3. [Metadata Inventory](#metadata-inventory)
4. [Prerequisites & Org Configuration](#prerequisites--org-configuration)
5. [Local Development Setup](#local-development-setup)
6. [Deployment Instructions](#deployment-instructions)
7. [Running Tests & Verifying Functionality](#running-tests--verifying-functionality)
8. [Developer Takeover Checklist](#developer-takeover-checklist)
9. [Architecture & Documentation Index](#architecture--documentation-index)

---

## 1. Project Overview

The **Residential Handover Module** automates and governs the handover of residential units (apartments, villas, plots) to homebuyers upon construction completion.

### Key Capabilities
- **Readiness Gatekeeper:** Automated 4-gate validation (Booking clearance, Financial clearance, Occupancy Certificate clearance, Unit readiness).
- **Quality Audit Matrix:** Room-by-room, checklist-driven inspection with photo attachments and spatial floorplan location pins.
- **Snag Kanban Board:** Interactive 4-column defect resolution board (`OPEN` ➔ `IN_PROGRESS` ➔ `VERIFICATION` ➔ `CLOSED`) with contractor team assignment and photo evidence submission.
- **External Auditor Access:** Secure, tokenized REST endpoint (`/services/apexrest/externalInspection/*`) for external QA inspectors without internal Salesforce login.
- **Appointment & Reschedule Workflow:** Automated customer invitation dispatch with state-driven button toggle (**Invite Customer** ➔ **Reschedule**), calendar event generation, and card input locking.
- **Possession Ceremony & Document Generation:** Digital meter readings capture (Electricity, Water, Gas), key/access card tracking, customer satisfaction rating, and automated PDF possession letter generation.

---

## 2. Handover Business Process & Stage Progression

The journey progresses sequentially across **5 stages**:

```
[1. Readiness] ➔ [2. Inspection & Audit] ➔ [3. Snag Resolution] ➔ [4. Appointment & Handover] ➔ [5. Completed]
```

### Stage Summary & Key Actions

| Stage # | Stage Name | Entry Criteria | Header Actions | Next Transition |
|---|---|---|---|---|
| **1** | **Readiness** | Automatically spawned on Booking confirmation. | **Start Inspection**, Edit, Delete | Clicking **Start Inspection** validates gates, seeds checklist, and advances to Stage 2. |
| **2** | **Inspection & Audit** | Inspection round initialized. | **Inspection Done** (before complete), **Download Inspection Report** (after complete) | Clicking **Inspection Done** enforces that all checklist items are Pass/NA and snags are verified/closed. |
| **3** | **Snag Resolution** | Issues raised during inspection. | Header retains standard actions; stage path enables navigation. | All snags moved to `CLOSED` and verified; checklist items update to `Pass`. |
| **4** | **Appointment & Handover** | Inspection completed & snags resolved. | **Invite Customer** (pre-invite) / **Reschedule** (post-invite) | Customer invitation sent, appointment date locked. On arrival, user proceeds to Stage 5. |
| **5** | **Completed** | Customer arrived on site. | Download Inspection Report | Physical keys issued, meter readings logged, digital signee captured, possession pack generated. |

---

## 3. Metadata Inventory

All code and metadata are located under `force-app/main/default/`:

### Lightning Web Components (LWC)
- `handoverWorkspace`: The central single-page application orchestrating all 5 stages, stage path, readiness cards, checklist matrix, snag Kanban board, and possession forms.
- `handoverStartInspectionAction`: Quick action modal validating readiness prerequisites and initiating inspection rounds.
- `handoverInspectionDoneAction`: Quick action modal enforcing completion rules (all Pass/NA, zero unverified snags).
- `handoverDownloadInspectionReportAction`: Quick action modal providing instant report preview and Visualforce PDF download.
- `handoverContinueToAppointmentAction`: Quick action helper for appointment progression.
- `externalInspectionApp`: Standalone mobile-optimized inspection application for external auditors.

### Apex Classes & Triggers
- `HandoverWorkspaceController.cls`: Primary AuraEnabled controller for all workspace actions, snag management, appointment scheduling, and document generation.
- `HandoverWorkspaceControllerTest.cls`: Comprehensive unit test suite covering the full 5-stage lifecycle (100% pass rate).
- `HandoverTestDataFactory.cls`: Test utility provisioning mock Projects, Towers, Floors, Units, Person Accounts, Opportunities, and Bookings.
- `HandoverNotificationEngine.cls`: Notification engine dispatching Tasks, Calendar Events, Customer Emails, and `Handover_Event_Log__c` audit logs.
- `HandoverDocumentGenerator.cls`: Generates official possession certificates and attaches them to Salesforce Files (`ContentVersion`).
- `InspectionReportPDFController.cls`: Visualforce controller generating printable/downloadable inspection audit PDF reports.
- `InspectionReportPDFControllerTest.cls`: Unit test suite for PDF generation.
- `ExternalInspectionService.cls`: Secure `@RestResource` API (`/services/apexrest/externalInspection/*`) for external token-based auditing.
- `BookingHandoverHandler.cls`: Trigger handler creating `Handover__c` when `Booking__c` is marked Confirmed.
- `BookingHandoverTrigger.trigger`: Apex trigger on `Booking__c`.
- `InspectionTrigger.trigger`: Apex trigger on `Inspection__c` continuously syncing `Handover__c.Inspection_Status__c`.
- `RentResaleWorkspaceController.cls`: Shared controller handling post-handover transition into leasing/resale.

### Visualforce Pages
- `InspectionReportPDF.page`: Formally formatted inspection audit report rendered as PDF.

### Custom Objects
- `Handover__c` (61 custom fields)
- `Inspection__c` (25 custom fields)
- `Inspection_Checklist_Item__c` (10 custom fields)
- `Snag__c` (24 custom fields)
- `Handover_Event_Log__c` (9 custom fields)
- `Unit__c` (Handover extensions: `Current_Handover__c`, `Possession_Readiness_Status__c`, `Possession_Ready_Date__c`)
- `Booking__c` (Handover extensions: `Handover__c`, `Possession_Date__c`, `Ownership_Transfer_In_Progress__c`)

### FlexiPages & Record Pages
- `Handover_Record_Page.flexipage-meta.xml`: Dynamic Actions record page hosting `handoverWorkspace`, standard activity timeline, and related lists.
- `Handover_Workspace_App.flexipage-meta.xml`: App page for the Handover Hub navigation tab.

### Permission Sets
- `Residential_Handover_Manager.permissionset-meta.xml`: Grants comprehensive permissions for Handover leads, auditors, and operations admins.

---

## 4. Prerequisites & Org Configuration

Before deploying this module to your Salesforce org, ensure the following are configured:

1. **Person Accounts Enabled:** Org must support Person Accounts (`Account.PersonEmail`, `Account.PersonContactId`).
2. **Salesforce Files Enabled:** Ensure standard Content functionality is available.
3. **Core Real Estate Objects:** The org must have `Property__c`, `Tower__c`, `Floor__c`, `Unit__c`, and `Booking__c`. See [DEPENDENCIES.md](DEPENDENCIES.md) for required fields.
4. **Email Deliverability:** Set Setup ➔ Deliverability to **All email** if you wish to verify automated customer invitation emails.

---

## 5. Local Development Setup

### 1. Prerequisites
- **Node.js** >= 18.x
- **Salesforce CLI (`sf`)** >= 2.0.0
- **Git** >= 2.30

### 2. Clone the Repository
```bash
git clone https://github.com/somyasharmawarp/salesforce-residential-handover.git
cd salesforce-residential-handover
```

### 3. Install Dependencies
```bash
npm install
```

### 4. Authenticate to your Salesforce Org
```bash
# Authenticate via browser
sf org login web --alias my-dev-org --set-default

# Or authenticate using an existing auth URL
sf org login sfdx-url --sfdx-url-file authFile.json --alias my-dev-org --set-default
```

---

## 6. Deployment Instructions

### Deploy via Salesforce CLI (Source Format)
Deploy the complete Handover package to your authenticated default org:

```bash
sf project deploy start --metadata-dir deployment/package.xml --wait 15
```

Alternatively, deploy using source path:
```bash
sf project deploy start --source-dir force-app/main/default --wait 15
```

### Assign the Permission Set
Assign the Handover Manager permission set to your user:
```bash
sf org assign permset --name Residential_Handover_Manager
```

---

## 7. Running Tests & Verifying Functionality

Run the automated Apex test suite:

```bash
sf apex run test --class-names HandoverWorkspaceControllerTest InspectionReportPDFControllerTest --code-coverage --result-format human
```

Expected result:
```
=== Test Results
TEST NAME                                                                        OUTCOME  RUNTIME (MS)
───────────────────────────────────────────────────────────────────────────────  ───────  ────────────
HandoverWorkspaceControllerTest.testBookingTriggerAndHandoverInitialization      Pass     7237
HandoverWorkspaceControllerTest.testExternalInspectionService                    Pass     3091
HandoverWorkspaceControllerTest.testHandoverWorkspaceLifecycle                   Pass     9442
HandoverWorkspaceControllerTest.testInspectionCompletionAndProceedToAppointment  Pass     1461
HandoverWorkspaceControllerTest.testStartInspectionGatingAndNoDuplicates         Pass     1399
HandoverWorkspaceControllerTest.testTargetedEnhancementsAndRelatedLists          Pass     5257
HandoverWorkspaceControllerTest.testTargetedFunctionalCorrections                Pass     1272
HandoverWorkspaceControllerTest.testTargetedSnagLifecycleAndAppointment          Pass     2562
InspectionReportPDFControllerTest.testInspectionReportWithHandoverId             Pass     2754
InspectionReportPDFControllerTest.testInspectionReportWithInspectionId           Pass     1944
InspectionReportPDFControllerTest.testInspectionReportWithNullId                 Pass     12

=== Test Summary
Outcome: Passed (11/11 tests, 100% pass rate)
```

---

## 8. Developer Takeover Checklist

Follow these steps to validate your environment and take over development:

- [ ] **Step 1:** Verify Person Accounts are active in the target org.
- [ ] **Step 2:** Deploy metadata using `deployment/package.xml`.
- [ ] **Step 3:** Assign permission set `Residential_Handover_Manager` to your user account.
- [ ] **Step 4:** Execute the Apex test suite and ensure 11/11 tests pass.
- [ ] **Step 5:** Seed sample Handover test data by executing:
  ```bash
  sf apex run --file scripts/apex/seed_handover.apex
  ```
- [ ] **Step 6:** Open the seeded Handover record in Lightning Experience and verify the 5-stage path displays properly.
- [ ] **Step 7:** Verify Stage 1 Header has **Start Inspection** button.
- [ ] **Step 8:** Click **Start Inspection** and confirm checklist items load in Stage 2.
- [ ] **Step 9:** Mark checklist items as Pass or raise a Snag. Verify snags appear on the Stage 3 Kanban board.
- [ ] **Step 10:** Complete the inspection and verify **Download Inspection Report** appears in the header and downloads a valid PDF.
- [ ] **Step 11:** Advance to Stage 4 (Appointment). Verify **Invite Customer** is shown before sending, and toggles to **Reschedule** after sending with card inputs disabled.
- [ ] **Step 12:** Advance to Stage 5 (Completed). Enter meter readings and key counts, click Complete Handover, and verify possession letter is attached to Files.

---

## 9. Architecture & Documentation Index

- **[HANDOVER_TECHNICAL_DOCUMENTATION.md](HANDOVER_TECHNICAL_DOCUMENTATION.md):** Deep-dive technical architecture, state machine diagrams, LDS cache invalidation, and external REST API specifications.
- **[DEPENDENCIES.md](DEPENDENCIES.md):** Complete listing of required objects, fields, relationships, and platform capabilities.
- **[deployment/package.xml](deployment/package.xml):** Official metadata manifest for deployments and retrievals.
