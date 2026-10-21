# Residential Handover — Architecture Dependencies & Prerequisites

This document outlines all system, object, field, Apex, permission, and automation dependencies required to deploy, execute, and maintain the **Residential Handover implementation** in a Salesforce environment.

---

## 1. Salesforce Platform Features & Org Prerequisites

Before deploying the Handover metadata to a target Salesforce org, ensure the following platform capabilities and configurations are enabled:

| Feature / Setting | Description | Required By |
|---|---|---|
| **Person Accounts** | Org must have Person Accounts activated. Accounts represent residential buyers with `PersonEmail`, `PersonContactId`, and `Phone`. | `Handover__c.Customer__c`, `BookingHandoverHandler`, `HandoverTestDataFactory` |
| **Salesforce Files (Content)** | `ContentVersion`, `ContentDocument`, and `ContentDocumentLink` enabled for automated PDF possession letters and inspection audit storage. | `HandoverDocumentGenerator`, `HandoverWorkspaceController.generateInspectionReport` |
| **Lightning Experience** | Dynamic Actions, Lightning Record Pages (`FlexiPage`), and custom Lightning Web Components (LWC). | `Handover_Record_Page`, `HandoverWorkspace` |
| **Apex REST Services** | Custom REST endpoints (`@RestResource`) enabled for external token-based auditor access. | `ExternalInspectionService` (`/services/apexrest/externalInspection/*`) |
| **Visualforce PDF Rendering** | Standard Visualforce PDF rendering engine (`renderAs="pdf"`). | `InspectionReportPDF.page` |
| **Email Deliverability** | Org email deliverability set to "All email" for customer appointment invitations and snag notifications. | `HandoverNotificationEngine`, `HandoverWorkspaceController` |

---

## 2. Core Real Estate Object Dependencies (Prerequisites)

The Handover module links directly to the real estate property hierarchy and booking lifecycle. The following custom objects and fields must exist in the target org:

### 2.1 `Property__c` (Project Master)
- `Name` (Text) — Project Name (e.g., "Varthur Vista")
- `OC_Received__c` (Checkbox) — Occupancy Certificate cleared for the project

### 2.2 `Tower__c` (Tower / Block Master)
- `Name` (Text) — Tower identifier (e.g., "Tower B")
- `Property__c` (Lookup to `Property__c`)
- `OC_Received__c` (Checkbox) — Occupancy Certificate cleared for the tower

### 2.3 `Floor__c` (Floor Master)
- `Name` (Text) — Floor identifier (e.g., "12th")
- `Tower__c` (Lookup to `Tower__c`)
- `Property__c` (Lookup to `Property__c`)

### 2.4 `Unit__c` (Apartment / Flat Master)
- `Name` (Text) — Unit number (e.g., "1204")
- `Property__c` (Lookup to `Property__c`)
- `Tower__c` (Lookup to `Tower__c`)
- `Floor__c` (Lookup to `Floor__c`)
- `Carpet_Area__c` (Number)
- `BHK_Configuration__c` (Picklist / Text, e.g., "3 BHK Canopy")
- `Status__c` (Picklist, e.g., "Booked", "Handed Over")
- **Handover Extensions on `Unit__c`:**
  - `Current_Handover__c` (Lookup to `Handover__c`) — Active handover journey for this unit
  - `Possession_Readiness_Status__c` (Picklist: `Pending`, `Ready`, `Handed Over`)
  - `Possession_Ready_Date__c` (Date)

### 2.5 `Booking__c` (Sales Booking Master)
- `Name` (Text / AutoNumber)
- `Project__c` (Lookup to `Property__c`)
- `Unit_Id__c` (Lookup to `Unit__c`)
- `Account_Id__c` (Lookup to `Account`)
- `Opportunity_Id__c` (Lookup to `Opportunity`)
- `Status__c` (Picklist: `Draft`, `Confirmed`, `Closed Won`)
- `Is_Token_Recieved__c` (Checkbox)
- `Token_Amount__c` (Currency)
- `Allotment_Shared__c` (Checkbox)
- **Handover Extensions on `Booking__c`:**
  - `Handover__c` (Lookup to `Handover__c`) — Bi-directional lookup to Handover record
  - `Possession_Date__c` (Date)
  - `Ownership_Transfer_In_Progress__c` (Checkbox)

---

## 3. Dedicated Handover Module Custom Objects

These 5 custom objects are packaged within this repository:

| Object | API Name | Responsibility |
|---|---|---|
| **Handover** | `Handover__c` | Master record orchestrating the 5-stage handover journey from Readiness to Completed. Tracks milestones, blockers, meter readings, keys, appointment scheduling, and completion signatures. |
| **Property Inspection** | `Inspection__c` | Represents an audit round (Internal QA, Customer Joint Inspection, Snag Re-inspection). Holds audit metrics, lock state, and secure external auditor token. |
| **Inspection Checklist Item** | `Inspection_Checklist_Item__c` | Granular audit checkpoints (Living Room, Kitchen, Electrical, Plumbing, Fixtures). Stores Result (`Pass`, `Issue`, `N/A`), photo attachments, and spatial location pins. |
| **Snag** | `Snag__c` | Defects or rectifications raised during inspection. Tracks contractor assignment, responsible team, severity, SLA due dates, resolution comments, evidence photos, verification, and closure. |
| **Handover Event Log** | `Handover_Event_Log__c` | Immutable compliance and audit trail recording state transitions, notifications dispatched, actors, channels, timestamps, and trigger sources. |

---

## 4. Apex Classes & Triggers

| Class / Trigger Name | Layer | Responsibility |
|---|---|---|
| `HandoverWorkspaceController` | Apex Controller (`@AuraEnabled`) | Core backend for `handoverWorkspace` and all quick action LWCs. Implements stage gating, checklist updating, snag board CRUD, appointment booking/rescheduling, report generation, and handover finalization. |
| `HandoverWorkspaceControllerTest` | Apex Test | 100% test coverage suite validating the entire 5-stage lifecycle, snag verification rules, appointment email dispatch, and edge cases. |
| `HandoverTestDataFactory` | Test Utility | Provisions end-to-end test data (`Property`, `Tower`, `Floor`, `Unit`, `Person Account`, `Opportunity`, `Booking`, and `Handover`). |
| `HandoverNotificationEngine` | Service | Centralized event logger and automated dispatcher for Tasks, Calendar Events, Customer Emails, and `Handover_Event_Log__c` entries. |
| `HandoverDocumentGenerator` | Service | Automates generation of Official Possession Letters, Keys & Cards Handover Certificates, and attaches them to `ContentVersion` / `ContentDocumentLink`. |
| `InspectionReportPDFController` | Visualforce Controller | Generates printable and downloadable official PDF audit reports containing category breakdowns, defect summaries, and developer sign-offs. |
| `InspectionReportPDFControllerTest` | Apex Test | Test coverage for the PDF report controller across all valid and invalid ID parameters. |
| `ExternalInspectionService` | REST Service (`@RestResource`) | Secure external REST endpoint (`/services/apexrest/externalInspection/*`) allowing third-party inspectors to review checklists and submit results without Salesforce licenses. |
| `BookingHandoverHandler` | Trigger Handler | Automatically creates a `Handover__c` record in Stage 1 (Readiness) when a `Booking__c` is marked Confirmed or Closed Won. |
| `BookingHandoverTrigger` | Apex Trigger | Fires `after insert, after update` on `Booking__c` to invoke `BookingHandoverHandler`. |
| `InspectionTrigger` | Apex Trigger | Fires `after insert, after update, after delete, after undelete` on `Inspection__c` to continuously sync `Handover__c.Inspection_Status__c`. |
| `RentResaleWorkspaceController` | Shared Controller Dependency | Handles the post-handover transition when an owner requests leasing or resale services directly from the completed handover card. |

---

## 5. Lightning Web Components (LWC)

| Component Name | Target | Purpose |
|---|---|---|
| `handoverWorkspace` | Record Page & App Tab | The primary single-page workspace containing the interactive Stage Path (1 to 5), Readiness Gate Cards, Checklist Audit Matrix, 4-column Snag Kanban Board, Appointment Scheduling / Rescheduling, and Handover Finalization form. |
| `handoverStartInspectionAction` | Quick Action Modal | Modal on Stage 1 (Readiness) allowing the user to validate prerequisites, configure inspector details, and transition to Stage 2. |
| `handoverInspectionDoneAction` | Quick Action Modal | Modal on Stage 2 validating strict checklist completion (all Pass or N/A, zero unverified snags) before locking the inspection round. |
| `handoverDownloadInspectionReportAction` | Quick Action Modal | Modal on header action bar providing instant preview and PDF download of the signed Inspection Audit Report. |
| `handoverContinueToAppointmentAction` | Quick Action Modal | Helper action for advancing to appointment scheduling once all snags are verified. |
| `externalInspectionApp` | Standalone App / Site | Responsive web application for mobile and tablet third-party auditors using one-time token authentication. |

---

## 6. Permission Sets

| Permission Set | Target Personas | Grants |
|---|---|---|
| `Residential_Handover_Manager` | Handover Lead, Quality Auditor, Relationship Manager, Operations Admin | Full CRUD + View All / Modify All on `Handover__c`, `Inspection__c`, `Inspection_Checklist_Item__c`, `Snag__c`, `Handover_Event_Log__c`, plus read access to `Booking__c` and `Unit__c`. |

---

## 7. Cross-Module Interactions

- **Sales / Booking Module:** Handover is spawned automatically via `BookingHandoverTrigger` once booking criteria are satisfied.
- **Service / Activities:** Standard Salesforce `Task` and `Event` records are automatically logged against `Handover__c` and visible in the standard Salesforce Activity Timeline.
- **Rent & Resale Module:** Upon completion of Stage 5, the owner can initiate post-sale leasing or secondary resale, delegating to `RentResaleWorkspaceController.createRequestFromHandover`.
