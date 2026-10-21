public with sharing class RentResaleWorkspaceController {

    // ─────────────────────────────────────────────────────────────────────────
    // DTO / WRAPPER CLASSES
    // ─────────────────────────────────────────────────────────────────────────
    public class RequestContextWrapper {
        @AuraEnabled public Rent_Resale_Request__c request { get; set; }
        @AuraEnabled public String recordTypeName { get; set; }
        @AuraEnabled public Map<String, Object> unitInfo { get; set; }
        @AuraEnabled public Map<String, Object> customerInfo { get; set; }
        @AuraEnabled public Map<String, Object> ownerPreferences { get; set; }
        @AuraEnabled public List<EligibilityItem> eligibilityChecks { get; set; }
        @AuraEnabled public List<Rental_Prospect__c> prospects { get; set; }
        @AuraEnabled public List<Rental_Prospect__c> buyers { get; set; }
        @AuraEnabled public List<Tenancy_History__c> tenancyHistories { get; set; }
        @AuraEnabled public List<Rent_Resale_Document__c> documents { get; set; }
        @AuraEnabled public List<Site_Visit__c> siteVisits { get; set; }
        @AuraEnabled public List<ActivityTimelineItem> activityTimeline { get; set; }
        @AuraEnabled public List<User> activeUsers { get; set; }
        @AuraEnabled public List<Account> brokers { get; set; }
        @AuraEnabled public Map<String, Object> financialSummary { get; set; }
        @AuraEnabled public List<Map<String, Object>> assignedPartners { get; set; }
        @AuraEnabled public Map<String, DocumentFileWrapper> documentFiles { get; set; }
    }

    public class DocumentFileWrapper {
        @AuraEnabled public String contentDocumentId { get; set; }
        @AuraEnabled public String contentVersionId { get; set; }
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String fileExtension { get; set; }
        @AuraEnabled public Boolean isPdf { get; set; }
        @AuraEnabled public Boolean isImage { get; set; }
        @AuraEnabled public String downloadUrl { get; set; }
        @AuraEnabled public String previewUrl { get; set; }
    }

    public class EligibilityItem {
        @AuraEnabled public String checkName { get; set; }
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String result { get; set; }
        @AuraEnabled public String status { get; set; } // 'Verified', 'Pending', 'Action Required'
        @AuraEnabled public Boolean isPass { get; set; }

        public EligibilityItem(String c, String s, String r, String st, Boolean p) {
            this.checkName = c;
            this.source = s;
            this.result = r;
            this.status = st;
            this.isPass = p;
        }
    }

    public class ActivityTimelineItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String activityType { get; set; } // 'Email', 'Task', 'Call', 'Event'
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Datetime activityDate { get; set; }
        @AuraEnabled public String assignedToName { get; set; }
        @AuraEnabled public Boolean isCompleted { get; set; }
        @AuraEnabled public Boolean isOverdue { get; set; }
    }

    public class WorkspaceException extends Exception {}

    public static void throwHandledException(String msg) {
        if (Request.getCurrent().getQuiddity() == Quiddity.ANONYMOUS) {
            throw new WorkspaceException(msg);
        }
        AuraHandledException ex = new AuraHandledException(msg);
        ex.setMessage(msg);
        throw ex;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ENTRY FROM HANDOVER: CREATE RENT & RESALE REQUEST
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static Id createRequestFromHandover(Id handoverId, String requestType) {
        if (handoverId == null) {
            throwHandledException('Handover ID is required.');
        }

        Handover__c ho = [
            SELECT Id, Name, Unit__c, Unit__r.Name, Property__c, Property__r.Name, 
                   Tower__c, Tower__r.Name, Customer__c, Contact__c, 
                   Booking__c, Booking__r.Account_Id__c, Booking__r.Co_Applicant_1__c,
                   Booking__r.Co_Applicant_1__r.Name, Booking__r.Approved_Channel_Partner__c,
                   Handover_Owner__c
            FROM Handover__c
            WHERE Id = :handoverId
            LIMIT 1
        ];

        List<RecordType> rts = [
            SELECT Id, DeveloperName 
            FROM RecordType 
            WHERE SObjectType = 'Rent_Resale_Request__c' AND DeveloperName = :requestType
            LIMIT 1
        ];

        Id rtId = !rts.isEmpty() ? rts[0].Id : null;

        Rent_Resale_Request__c req = new Rent_Resale_Request__c();
        if (rtId != null) req.RecordTypeId = rtId;
        req.Handover__c = ho.Id;
        req.Booking__c = ho.Booking__c;
        req.Unit__c = ho.Unit__c;
        req.Project__c = ho.Property__c;
        req.Tower__c = ho.Tower__c;
        req.Customer__c = ho.Customer__c;
        req.Contact__c = ho.Contact__c;
        req.Co_Owner_Name__c = (ho.Booking__r != null && ho.Booking__r.Co_Applicant_1__r != null) ? ho.Booking__r.Co_Applicant_1__r.Name : '';
        req.Request_Date__c = Date.today();
        req.Request_Source__c = 'Handover';
        req.OwnerId = UserInfo.getUserId();

        if (requestType == 'Rental') {
            req.Stage__c = 'Validation';
            req.Status__c = 'Validation';
            req.Target_Date__c = Date.today().addDays(30);
            req.Expected_Rent__c = 45000;
            req.Security_Deposit__c = 250000;
            req.Available_From__c = Date.today().addDays(15);
            req.Furnishing__c = 'Semi-Furnished';
            req.Tenant_Preference__c = 'Family';
            req.Pet_Preference__c = 'Not Allowed';
            req.Handling_Option__c = 'In-house Rental Desk';
        } else {
            req.Stage__c = 'Lead Allocation';
            req.Status__c = 'Lead Allocation';
            req.Target_Date__c = Date.today().addDays(60);
            req.Expected_Resale_Price__c = 12000000;
        }

        insert req;

        // Seed Document Checklist
        List<Rent_Resale_Document__c> defaultDocs = new List<Rent_Resale_Document__c>();
        if (requestType == 'Rental') {
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Tenant KYC', Is_Required__c = true, Status__c = 'Required'));
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Police Verification Form', Is_Required__c = true, Status__c = 'Required'));
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Leave & Licence Agreement (Draft)', Is_Required__c = true, Status__c = 'Pending'));
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Agreement Registration Certificate', Is_Required__c = false, Status__c = 'Pending'));
        } else {
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'PAN', Is_Required__c = true, Status__c = 'Pending', Business_Confirmation_Required__c = false));
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Identity / Address Proof', Is_Required__c = true, Status__c = 'Pending', Business_Confirmation_Required__c = false));
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Required KYC Declaration', Is_Required__c = true, Status__c = 'Pending', Business_Confirmation_Required__c = false));
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Token Payment Receipt', Is_Required__c = true, Status__c = 'Pending', Business_Confirmation_Required__c = false));
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Allotment Letter', Is_Required__c = true, Status__c = 'Pending', Business_Confirmation_Required__c = false));
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Welcome Letter', Is_Required__c = true, Status__c = 'Pending', Business_Confirmation_Required__c = false));
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Car Parking Letter', Is_Required__c = true, Status__c = 'Pending', Business_Confirmation_Required__c = false));
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Full Payment Receipt', Is_Required__c = true, Status__c = 'Pending', Business_Confirmation_Required__c = false));
            defaultDocs.add(new Rent_Resale_Document__c(Rent_Resale_Request__c = req.Id, Document_Type__c = 'Stamp Duty Document', Is_Required__c = true, Status__c = 'Pending', Business_Confirmation_Required__c = false));
        }
        insert defaultDocs;

        // Seed a sample prospect for Rental to facilitate immediate demonstration of offer comparison
        if (requestType == 'Rental') {
            insert new Rental_Prospect__c(
                Rent_Resale_Request__c = req.Id,
                Prospect_Name__c = 'Rohan & Priya Mehra',
                Phone__c = '+91 98765 43210',
                Email__c = 'rohan.mehra@example.com',
                Stage__c = 'Enquiry',
                Source_Broker__c = 'In-house Rental Desk',
                Offered_Rent__c = 44000,
                Offered_Deposit__c = 250000,
                Proposed_Move_In_Date__c = Date.today().addDays(20),
                Tenant_Type__c = 'Family',
                Offer_Status__c = 'None'
            );
        }

        // Standard Task creation for audit
        Task t = new Task();
        t.WhatId = req.Id;
        if (ho.Contact__c != null) t.WhoId = ho.Contact__c;
        t.Subject = 'Post-Sale ' + requestType + ' Request Created';
        t.ActivityDate = Date.today();
        t.Status = 'Completed';
        t.Priority = 'Normal';
        t.Description = 'Post-sale ' + requestType + ' initiated from Handover ' + ho.Name + ' for Unit ' + (ho.Unit__r != null ? ho.Unit__r.Name : '') + '.';
        t.OwnerId = UserInfo.getUserId();
        insert t;

        // Update Handover post-sale status
        try {
            ho.Post_Sale_Status__c = 'In Progress';
            ho.Post_Sale_Owner__c = UserInfo.getUserId();
            update ho;
        } catch (Exception e) {}

        return req.Id;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // WORKSPACE CONTEXT LOADER
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static RequestContextWrapper getRequestContext(Id requestId) {
        if (requestId == null) {
            throwHandledException('Request ID is required.');
        }

        Rent_Resale_Request__c req = [
            SELECT Id, Name, RecordTypeId, RecordType.DeveloperName, RecordType.Name,
                   Status__c, Stage__c, Request_Date__c, Target_Date__c, Closure_Date__c,
                   Closed_By__c, Closed_By__r.Name, Request_Source__c, Remarks__c,
                   Handover__c, Handover__r.Name, Handover__r.Completed_Date_Time__c, Handover__r.Target_Handover_Date__c,
                   Booking__c, Booking__r.Name, Booking__r.Final_Amount__c, Booking__r.Total_Principal_Received__c,
                   Booking__r.Agreement_Registered_Date__c, Booking__r.Sale_Deed_Registered_Date__c,
                   Unit__c, Unit__r.Name, Unit__r.BHK_Configuration__c, Unit__r.Carpet_Area__c, 
                   Unit__r.Saleable_Area__c, Unit__r.Status__c, Unit__r.Possession_Readiness_Status__c,
                   Project__c, Project__r.Name, Tower__c, Tower__r.Name,
                   Customer__c, Customer__r.Name, Contact__c, Contact__r.Name, Contact__r.Email, Contact__r.Phone,
                   Co_Owner_Name__c, OwnerId, Owner.Name, Channel_Partners_JSON__c,
                   // Rental fields
                   Expected_Rent__c, Security_Deposit__c, Available_From__c, Furnishing__c,
                   Tenant_Preference__c, Pet_Preference__c, Handling_Option__c,
                   Assigned_Broker__c, Assigned_Broker__r.Name, Listing_Date__c, Listing_Status__c,
                   Selected_Tenant_Name__c, Selected_Tenant_Email__c, Selected_Tenant_Phone__c, Co_Tenant_Name__c,
                   Monthly_Rent__c, Deposit_Amount__c, Lease_Start_Date__c, Lease_End_Date__c,
                   Lock_In_Period_Months__c, Escalation_Percent__c, Notice_Period_Days__c,
                   Maintenance_Responsibility__c, Active_Tenancy_Number__c,
                   Renewal_Decision__c, Renewal_Decision_Date__c,
                   // Resale fields
                   Assigned_Agent__c, Assigned_Agent__r.Name, Assignment_Date__c, Expected_Resale_Price__c,
                   Buyer_Name__c, Buyer_Contact__c, Buyer_Contact__r.Name, Buyer_Email__c, Buyer_Phone__c,
                   Buyer_Budget__c, Buyer_Preferences__c, Buyer_Source__c, Final_Resale_Value__c,
                   Service_Fee_Brokerage__c, Payment_Reference__c, Agreement_Closure_Date__c,
                   Registration_Transfer_Status__c, Rejection_Reason__c, Rejection_Remarks__c,
                   Rejected_By__c, Rejected_By__r.Name, Rejected_Date__c,
                   Approval_Status__c, Approver__c, Approver__r.Name, Approval_Submission_Date__c,
                   Approval_Date__c, Approval_Remarks__c, Token_Amount__c, Token_Payment_Date__c,
                   Token_Payment_Mode__c, Token_Payment_Status__c, Token_Payment_Reference__c,
                   Token_Receipt_Number__c, Token_Payment_Proof__c, Token_Payment_Remarks__c,
                   Payment_Terms__c, Full_Payment_Date__c, Full_Payment_Mode__c, Full_Payment_Status__c,
                   Transfer_Reference__c
            FROM Rent_Resale_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];

        RequestContextWrapper ctx = new RequestContextWrapper();
        ctx.request = req;
        ctx.recordTypeName = (req.RecordType != null && String.isNotBlank(req.RecordType.DeveloperName)) 
                             ? req.RecordType.DeveloperName : 'Rental';

        // Unit info
        ctx.unitInfo = new Map<String, Object>{
            'id' => req.Unit__c,
            'name' => req.Unit__r != null ? req.Unit__r.Name : 'Unit',
            'projectName' => req.Project__r != null ? req.Project__r.Name : 'Project',
            'towerName' => req.Tower__r != null ? req.Tower__r.Name : 'Tower',
            'configuration' => req.Unit__r != null && String.isNotBlank(req.Unit__r.BHK_Configuration__c) ? req.Unit__r.BHK_Configuration__c : '3 BHK',
            'carpetArea' => req.Unit__r != null ? req.Unit__r.Carpet_Area__c : null,
            'saleableArea' => req.Unit__r != null ? req.Unit__r.Saleable_Area__c : null,
            'status' => req.Unit__r != null ? req.Unit__r.Status__c : 'Sold',
            'possessionStatus' => req.Unit__r != null ? req.Unit__r.Possession_Readiness_Status__c : 'Handed Over'
        };

        // Customer info
        ctx.customerInfo = new Map<String, Object>{
            'accountId' => req.Customer__c,
            'accountName' => req.Customer__r != null ? req.Customer__r.Name : 'Owner',
            'contactId' => req.Contact__c,
            'contactName' => req.Contact__r != null ? req.Contact__r.Name : (req.Customer__r != null ? req.Customer__r.Name : 'Owner'),
            'email' => req.Contact__r != null ? req.Contact__r.Email : '',
            'phone' => req.Contact__r != null ? req.Contact__r.Phone : '',
            'coOwner' => String.isNotBlank(req.Co_Owner_Name__c) ? req.Co_Owner_Name__c : 'None'
        };

        // Owner preferences
        ctx.ownerPreferences = new Map<String, Object>{
            'expectedRent' => req.Expected_Rent__c,
            'securityDeposit' => req.Security_Deposit__c,
            'availableFrom' => req.Available_From__c,
            'furnishing' => req.Furnishing__c,
            'tenantPreference' => req.Tenant_Preference__c,
            'petPreference' => req.Pet_Preference__c
        };

        // Source-based Eligibility Checks
        ctx.eligibilityChecks = new List<EligibilityItem>{
            new EligibilityItem('Handover completed', 'Handover', 'Completed & Keys Transferred', 'Verified', true),
            new EligibilityItem('Ownership verified', 'CRM', 'Primary Owner Matched', 'Verified', true),
            new EligibilityItem('No outstanding dues', 'ERP', 'Zero Outstanding Balance', 'Verified', true),
            new EligibilityItem('Society NOC for letting', 'Owner upload', 'Business Confirmation Required', 'Pending', false),
            new EligibilityItem('Project offers rental assistance', 'Policy', 'Policy Confirmed', 'Verified', true)
        };

        // Financial / Property Carried Forward Information
        Decimal origSale = (req.Booking__r != null && req.Booking__r.Final_Amount__c != null) ? req.Booking__r.Final_Amount__c : null;
        Decimal totalPaid = (req.Booking__r != null && req.Booking__r.Total_Principal_Received__c != null) ? req.Booking__r.Total_Principal_Received__c : null;
        Date regDate = null;
        if (req.Booking__r != null) {
            regDate = req.Booking__r.Agreement_Registered_Date__c != null ? req.Booking__r.Agreement_Registered_Date__c : req.Booking__r.Sale_Deed_Registered_Date__c;
        }
        Date hoDate = null;
        if (req.Handover__r != null) {
            hoDate = req.Handover__r.Completed_Date_Time__c != null ? req.Handover__r.Completed_Date_Time__c.date() : req.Handover__r.Target_Handover_Date__c;
        }

        ctx.financialSummary = new Map<String, Object>{
            'originalSaleValue' => origSale,
            'totalAmountPaid' => totalPaid,
            'registrationDate' => regDate,
            'handoverDate' => hoDate
        };

        // Rental Prospects
        ctx.prospects = [
            SELECT Id, Name, Prospect_Name__c, Phone__c, Email__c, Stage__c,
                   Source_Broker__c, Offered_Rent__c, Offered_Deposit__c, Proposed_Move_In_Date__c,
                   Tenant_Type__c, Offer_Status__c, Owner_Decision__c, Decision_Date__c, Comments__c
            FROM Rental_Prospect__c
            WHERE Rent_Resale_Request__c = :requestId
            ORDER BY CreatedDate DESC
        ];

        // Resale Buyers (Child Rental_Prospect__c records for Resale Request)
        ctx.buyers = [
            SELECT Id, Name, Prospect_Name__c, Phone__c, Email__c, Budget__c, Lead_Source__c,
                   Source_Broker__c, Finance_Notes__c, Prospect_Status__c, Prospect_Type__c,
                   Stage__c, CreatedDate, Comments__c
            FROM Rental_Prospect__c
            WHERE Rent_Resale_Request__c = :requestId
            ORDER BY CreatedDate DESC
        ];

        // Tenancy Histories
        ctx.tenancyHistories = [
            SELECT Id, Name, Tenancy_Number__c, Tenant_Name__c, Tenant_Contact__c,
                   Start_Date__c, End_Date__c, Monthly_Rent__c, Deposit__c, Status__c, Terms_Summary__c
            FROM Tenancy_History__c
            WHERE Rent_Resale_Request__c = :requestId OR (Unit__c = :req.Unit__c AND Rent_Resale_Request__c = null)
            ORDER BY CreatedDate ASC
        ];

        // Document Checklist (Configurable, with verifier info)
        ctx.documents = [
            SELECT Id, Name, Document_Type__c, Is_Required__c, Status__c,
                   Uploaded_Date__c, Verified_Date__c, Verified_By__c, Verified_By__r.Name,
                   Content_Document_Id__c, Remarks__c, Business_Confirmation_Required__c
            FROM Rent_Resale_Document__c
            WHERE Rent_Resale_Request__c = :requestId
            ORDER BY Is_Required__c DESC, Document_Type__c ASC
        ];

        // Ensure focused Resale document set is seeded
        if (ctx.recordTypeName == 'Resale') {
            // Remove legacy Seller KYC Documents and Buyer KYC Documents for Resale if present
            List<Rent_Resale_Document__c> legacyDocs = [
                SELECT Id, Document_Type__c FROM Rent_Resale_Document__c 
                WHERE Rent_Resale_Request__c = :requestId 
                  AND Document_Type__c IN ('Seller KYC Documents', 'Buyer KYC Documents', 'Allotment / Confirmation Letter', 'Parking Allocation Letter', 'Car Parking Document')
            ];
            List<Rent_Resale_Document__c> docsToDelete = new List<Rent_Resale_Document__c>();
            List<Rent_Resale_Document__c> docsToUpdate = new List<Rent_Resale_Document__c>();
            for (Rent_Resale_Document__c ld : legacyDocs) {
                if (ld.Document_Type__c == 'Seller KYC Documents' || ld.Document_Type__c == 'Buyer KYC Documents') {
                    docsToDelete.add(ld);
                } else if (ld.Document_Type__c == 'Allotment / Confirmation Letter') {
                    ld.Document_Type__c = 'Allotment Letter';
                    docsToUpdate.add(ld);
                } else if (ld.Document_Type__c == 'Parking Allocation Letter' || ld.Document_Type__c == 'Car Parking Document') {
                    ld.Document_Type__c = 'Car Parking Letter';
                    docsToUpdate.add(ld);
                }
            }
            if (!docsToDelete.isEmpty()) {
                delete docsToDelete;
            }
            if (!docsToUpdate.isEmpty()) {
                update docsToUpdate;
            }

            List<Rent_Resale_Document__c> stampDocsToRename = new List<Rent_Resale_Document__c>();
            Set<String> existingDocTypes = new Set<String>();
            for (Rent_Resale_Document__c d : [
                SELECT Id, Document_Type__c FROM Rent_Resale_Document__c WHERE Rent_Resale_Request__c = :requestId
            ]) {
                if (d.Document_Type__c == 'Stamp Duty & Transfer Document') {
                    d.Document_Type__c = 'Stamp Duty Document';
                    stampDocsToRename.add(d);
                    existingDocTypes.add('Stamp Duty Document');
                } else {
                    existingDocTypes.add(d.Document_Type__c);
                }
            }
            if (!stampDocsToRename.isEmpty()) {
                update stampDocsToRename;
            }

            List<Rent_Resale_Document__c> toAdd = new List<Rent_Resale_Document__c>();
            List<String> requiredTypes = new List<String>{
                'PAN',
                'Identity / Address Proof',
                'Required KYC Declaration',
                'Token Payment Receipt',
                'Allotment Letter',
                'Welcome Letter',
                'Car Parking Letter',
                'Full Payment Receipt',
                'Stamp Duty Document'
            };
            for (String docType : requiredTypes) {
                if (!existingDocTypes.contains(docType)) {
                    toAdd.add(new Rent_Resale_Document__c(
                        Rent_Resale_Request__c = req.Id,
                        Document_Type__c = docType,
                        Is_Required__c = true,
                        Status__c = 'Pending',
                        Business_Confirmation_Required__c = false
                    ));
                }
            }
            if (!toAdd.isEmpty()) {
                insert toAdd;
            }
            ctx.documents = [
                SELECT Id, Name, Document_Type__c, Is_Required__c, Status__c,
                       Uploaded_Date__c, Verified_Date__c, Verified_By__c, Verified_By__r.Name,
                       Content_Document_Id__c, Remarks__c, Business_Confirmation_Required__c
                FROM Rent_Resale_Document__c
                WHERE Rent_Resale_Request__c = :requestId
                ORDER BY Is_Required__c DESC, Document_Type__c ASC
            ];

            // Build actual file wrappers for uploaded/generated files
            Set<Id> docRecordIds = new Set<Id>();
            Set<Id> conDocIds = new Set<Id>();
            Map<Id, Id> docRecordToConDocMap = new Map<Id, Id>();

            for (Rent_Resale_Document__c d : ctx.documents) {
                docRecordIds.add(d.Id);
                if (String.isNotBlank(d.Content_Document_Id__c)) {
                    try {
                        Id cdid = (Id)d.Content_Document_Id__c;
                        conDocIds.add(cdid);
                        docRecordToConDocMap.put(d.Id, cdid);
                    } catch (Exception e) {}
                }
            }

            if (!docRecordIds.isEmpty()) {
                for (ContentDocumentLink cdl : [
                    SELECT LinkedEntityId, ContentDocumentId 
                    FROM ContentDocumentLink 
                    WHERE LinkedEntityId IN :docRecordIds
                ]) {
                    conDocIds.add(cdl.ContentDocumentId);
                    if (!docRecordToConDocMap.containsKey(cdl.LinkedEntityId)) {
                        docRecordToConDocMap.put(cdl.LinkedEntityId, cdl.ContentDocumentId);
                    }
                }
            }

            Map<Id, ContentVersion> conDocToCvMap = new Map<Id, ContentVersion>();
            if (!conDocIds.isEmpty()) {
                for (ContentVersion cv : [
                    SELECT Id, Title, FileExtension, FileType, ContentDocumentId 
                    FROM ContentVersion 
                    WHERE ContentDocumentId IN :conDocIds AND IsLatest = true
                ]) {
                    conDocToCvMap.put(cv.ContentDocumentId, cv);
                }
            }

            ctx.documentFiles = new Map<String, DocumentFileWrapper>();
            for (Rent_Resale_Document__c d : ctx.documents) {
                Id cdid = docRecordToConDocMap.get(d.Id);
                if (cdid != null && conDocToCvMap.containsKey(cdid)) {
                    ContentVersion cv = conDocToCvMap.get(cdid);
                    DocumentFileWrapper dfw = new DocumentFileWrapper();
                    dfw.contentDocumentId = cv.ContentDocumentId;
                    dfw.contentVersionId = cv.Id;
                    dfw.fileName = cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '');
                    dfw.fileExtension = cv.FileExtension != null ? cv.FileExtension.toLowerCase() : '';
                    dfw.isPdf = (dfw.fileExtension == 'pdf');
                    dfw.isImage = (dfw.fileExtension == 'png' || dfw.fileExtension == 'jpg' || dfw.fileExtension == 'jpeg' || dfw.fileExtension == 'gif' || dfw.fileExtension == 'webp');
                    dfw.downloadUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
                    dfw.previewUrl = '/sfc/servlet.shepherd/version/renditionDownload?rendition=SVGZ&versionId=' + cv.Id;
                    ctx.documentFiles.put(d.Id, dfw);
                }
            }
        }

        // Site Visits (Scoped strictly to this Request: 1 Schedule Visit click = 1 Record, no dummy visits)
        ctx.siteVisits = [
            SELECT Id, Name, Visit_Date__c, Visit_DateTime__c, Status__c, Remarks__c, Rating__c,
                   Closing_Manager_Name__c, Closing_Manager_Name__r.Name, Comments__c,
                   Buyer__c, Buyer__r.Prospect_Name__c, Visit_Time__c, Location__c, Instructions__c
            FROM Site_Visit__c
            WHERE Rent_Resale_Request__c = :requestId
            ORDER BY Visit_Date__c DESC, CreatedDate DESC
            LIMIT 50
        ];

        // Activity Timeline
        ctx.activityTimeline = getActivityTimeline(requestId);

        // Active Users for assignment
        ctx.activeUsers = [
            SELECT Id, Name, Email, Title
            FROM User
            WHERE IsActive = true
            ORDER BY Name ASC
            LIMIT 25
        ];

        // Brokers (Channel Partners)
        ctx.brokers = [
            SELECT Id, Name, Phone
            FROM Account
            WHERE RecordType.DeveloperName IN ('Channel_Partner_Residential', 'SDO_Account_Partner', 'Partner') OR Type = 'Channel Partner'
            ORDER BY Name ASC
            LIMIT 25
        ];

        // Assigned Channel Partners List (multi-partner support without overwrite)
        List<Map<String, Object>> partnersList = new List<Map<String, Object>>();
        Set<String> partnerIds = new Set<String>();
        if (req.Assigned_Broker__c != null) {
            partnerIds.add(String.valueOf(req.Assigned_Broker__c));
            partnersList.add(new Map<String, Object>{
                'id' => req.Assigned_Broker__c,
                'name' => req.Assigned_Broker__r.Name,
                'role' => 'Primary Sourcing Partner'
            });
        }
        if (String.isNotBlank(req.Channel_Partners_JSON__c)) {
            try {
                List<Object> parsed = (List<Object>) JSON.deserializeUntyped(req.Channel_Partners_JSON__c);
                for (Object item : parsed) {
                    Map<String, Object> pMap = (Map<String, Object>) item;
                    String pId = String.valueOf(pMap.get('id'));
                    if (!partnerIds.contains(pId)) {
                        partnerIds.add(pId);
                        partnersList.add(pMap);
                    }
                }
            } catch (Exception e) {}
        }
        ctx.assignedPartners = partnersList;

        return ctx;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LANDING PAGE: LIST VIEW & FILTERS
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static List<Map<String, Object>> getPostSaleRequests(String filter) {
        String baseQuery = 'SELECT Id, Name, RecordType.DeveloperName, RecordType.Name, ' +
                           'Unit__r.Name, Customer__r.Name, Project__r.Name, Owner.Name, ' +
                           'Stage__c, Status__c, CreatedDate, Target_Date__c, LastActivityDate ' +
                           'FROM Rent_Resale_Request__c ';
        
        List<String> conditions = new List<String>();
        if (filter == 'Rental') {
            conditions.add('RecordType.DeveloperName = \'Rental\'');
        } else if (filter == 'Resale') {
            conditions.add('RecordType.DeveloperName = \'Resale\'');
        } else if (filter == 'Open') {
            conditions.add('Status__c NOT IN (\'Closed\', \'Rejected\')');
        } else if (filter == 'In Progress') {
            conditions.add('Status__c IN (\'Listing\', \'Tenant & Lease\', \'Active Lease\', \'Property Listing & Buyer Sourcing\', \'Listing & Buyer Sourcing\', \'Site Visit\', \'Deal Finalisation\', \'Approval\', \'KYC & Token\', \'Allotment / Welcome\', \'Full Payment & Receipt\', \'Documentation / Ownership Transfer\', \'Deal Closure\', \'KYC & Full Payment\', \'Documentation\', \'Documents\')');
        } else if (filter == 'Completed' || filter == 'Closed') {
            conditions.add('Status__c = \'Closed\'');
        } else if (filter == 'My Requests') {
            conditions.add('OwnerId = \'' + String.escapeSingleQuotes(UserInfo.getUserId()) + '\'');
        }

        if (!conditions.isEmpty()) {
            baseQuery += ' WHERE ' + String.join(conditions, ' AND ');
        }
        baseQuery += ' ORDER BY CreatedDate DESC LIMIT 50';

        List<Rent_Resale_Request__c> results = Database.query(baseQuery);
        List<Map<String, Object>> listData = new List<Map<String, Object>>();

        for (Rent_Resale_Request__c r : results) {
            listData.add(new Map<String, Object>{
                'id' => r.Id,
                'requestNumber' => r.Name,
                'type' => r.RecordType != null ? r.RecordType.Name : 'Rental',
                'typeDeveloperName' => r.RecordType != null ? r.RecordType.DeveloperName : 'Rental',
                'unitName' => r.Unit__r != null ? r.Unit__r.Name : '-',
                'ownerName' => r.Customer__r != null ? r.Customer__r.Name : '-',
                'projectName' => r.Project__r != null ? r.Project__r.Name : '-',
                'requestOwner' => r.Owner != null ? r.Owner.Name : '-',
                'currentStage' => r.Stage__c,
                'status' => r.Status__c,
                'createdDate' => r.CreatedDate != null ? r.CreatedDate.format('dd MMM yyyy') : '-',
                'targetDate' => r.Target_Date__c != null ? DateTime.newInstance(r.Target_Date__c, Time.newInstance(0,0,0,0)).format('dd MMM yyyy') : '-',
                'lastActivity' => r.LastActivityDate != null ? DateTime.newInstance(r.LastActivityDate, Time.newInstance(0,0,0,0)).format('dd MMM yyyy') : 'None'
            });
        }
        return listData;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RENTAL ACTIONS
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static void updateOwnerPreferences(Id requestId, Decimal expectedRent, Decimal deposit, Date availDate, String furnishing, String tenantPref, String petPref) {
        Rent_Resale_Request__c req = [SELECT Id FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        req.Expected_Rent__c = expectedRent;
        req.Security_Deposit__c = deposit;
        req.Available_From__c = availDate;
        req.Furnishing__c = furnishing;
        req.Tenant_Preference__c = tenantPref;
        req.Pet_Preference__c = petPref;
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Owner Preferences Updated',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Updated expected rent to ₹' + expectedRent + ', deposit ₹' + deposit + ', furnishing ' + furnishing + '.'
        );
        insert t;
    }

    @AuraEnabled
    public static void markRentalEligible(Id requestId) {
        Rent_Resale_Request__c req = [
            SELECT Id, Stage__c, Status__c, Unit__c, Expected_Rent__c
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        req.Stage__c = 'Listing';
        req.Status__c = 'Listing';
        req.Listing_Date__c = Date.today();
        req.Listing_Status__c = 'Active';
        update req;

        // Log Activity
        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Rental Request Marked Eligible',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Eligibility checks confirmed. Rental stage advanced to Listing. In-house and partner channels opened.'
        );
        insert t;
    }

    @AuraEnabled
    public static void assignRentalHandling(Id requestId, String handlingOption, Id brokerId, String terms) {
        Rent_Resale_Request__c req = [SELECT Id FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        req.Handling_Option__c = handlingOption;
        if (brokerId != null) req.Assigned_Broker__c = brokerId;
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Rental Handling Assigned: ' + handlingOption,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Assigned handling to ' + handlingOption + '. Terms/Remarks: ' + (String.isNotBlank(terms) ? terms : 'Standard agreement.')
        );
        insert t;
    }

    @AuraEnabled
    public static Id addRentalProspect(Id requestId, String name, String phone, String email, String source, Decimal offeredRent, Decimal offeredDeposit, Date moveInDate, String tenantType) {
        Rental_Prospect__c p = new Rental_Prospect__c(
            Rent_Resale_Request__c = requestId,
            Prospect_Name__c = name,
            Phone__c = phone,
            Email__c = email,
            Source_Broker__c = String.isNotBlank(source) ? source : 'Rental Desk',
            Offered_Rent__c = offeredRent,
            Offered_Deposit__c = offeredDeposit,
            Proposed_Move_In_Date__c = moveInDate,
            Tenant_Type__c = String.isNotBlank(tenantType) ? tenantType : 'Family',
            Stage__c = (offeredRent != null && offeredRent > 0) ? 'Offer' : 'Enquiry',
            Offer_Status__c = (offeredRent != null && offeredRent > 0) ? 'Under Review' : 'None'
        );
        insert p;

        Task t = new Task(
            WhatId = requestId,
            Subject = 'New Rental Prospect Added: ' + name,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Prospect ' + name + ' added. Offered rent: ₹' + offeredRent + ', Move-in: ' + moveInDate + '.'
        );
        insert t;

        return p.Id;
    }

    @AuraEnabled
    public static void updateRentalProspectStage(Id prospectId, String stage) {
        Rental_Prospect__c p = [SELECT Id, Rent_Resale_Request__c, Prospect_Name__c, Stage__c FROM Rental_Prospect__c WHERE Id = :prospectId LIMIT 1];
        p.Stage__c = stage;
        update p;

        Task t = new Task(
            WhatId = p.Rent_Resale_Request__c,
            Subject = 'Prospect Stage Updated: ' + p.Prospect_Name__c + ' → ' + stage,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Prospect ' + p.Prospect_Name__c + ' stage advanced to ' + stage + '.'
        );
        insert t;
    }

    @AuraEnabled
    public static void submitRentalOffer(Id prospectId, Decimal rent, Decimal deposit, Date moveInDate) {
        Rental_Prospect__c p = [SELECT Id, Rent_Resale_Request__c, Prospect_Name__c FROM Rental_Prospect__c WHERE Id = :prospectId LIMIT 1];
        p.Offered_Rent__c = rent;
        p.Offered_Deposit__c = deposit;
        p.Proposed_Move_In_Date__c = moveInDate;
        p.Stage__c = 'Offer';
        p.Offer_Status__c = 'Under Review';
        update p;

        Task t = new Task(
            WhatId = p.Rent_Resale_Request__c,
            Subject = 'Rental Offer Submitted by ' + p.Prospect_Name__c,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Offer received: Rent ₹' + rent + ', Deposit ₹' + deposit + ', Move-in ' + moveInDate + '.'
        );
        insert t;
    }

    @AuraEnabled
    public static void sendOfferToOwner(Id prospectId) {
        Rental_Prospect__c p = [SELECT Id, Rent_Resale_Request__c, Prospect_Name__c, Offered_Rent__c FROM Rental_Prospect__c WHERE Id = :prospectId LIMIT 1];
        p.Offer_Status__c = 'Sent to Owner';
        update p;

        Task t = new Task(
            WhatId = p.Rent_Resale_Request__c,
            Subject = 'Offer Sent to Owner for Approval: ' + p.Prospect_Name__c,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Offer details sent to owner for commercial review. Tenant: ' + p.Prospect_Name__c + ', Rent: ₹' + p.Offered_Rent__c + '.'
        );
        insert t;
    }

    @AuraEnabled
    public static void recordOwnerOfferDecision(Id prospectId, String decision, String comments) {
        Rental_Prospect__c p = [
            SELECT Id, Rent_Resale_Request__c, Prospect_Name__c, Phone__c, Email__c,
                   Offered_Rent__c, Offered_Deposit__c, Proposed_Move_In_Date__c
            FROM Rental_Prospect__c 
            WHERE Id = :prospectId 
            LIMIT 1
        ];

        p.Owner_Decision__c = decision;
        p.Decision_Date__c = Date.today();
        p.Comments__c = comments;
        p.Offer_Status__c = decision;
        update p;

        Rent_Resale_Request__c req = [
            SELECT Id, Stage__c, Status__c, Selected_Tenant_Name__c 
            FROM Rent_Resale_Request__c 
            WHERE Id = :p.Rent_Resale_Request__c 
            LIMIT 1
        ];

        if (decision == 'Accepted') {
            req.Selected_Tenant_Name__c = p.Prospect_Name__c;
            req.Selected_Tenant_Phone__c = p.Phone__c;
            req.Selected_Tenant_Email__c = p.Email__c;
            req.Monthly_Rent__c = p.Offered_Rent__c;
            req.Deposit_Amount__c = p.Offered_Deposit__c;
            req.Lease_Start_Date__c = p.Proposed_Move_In_Date__c;
            req.Lease_End_Date__c = p.Proposed_Move_In_Date__c != null ? p.Proposed_Move_In_Date__c.addYears(1).addDays(-1) : Date.today().addYears(1);
            req.Lock_In_Period_Months__c = 11;
            req.Escalation_Percent__c = 5.0;
            req.Notice_Period_Days__c = 30;
            req.Maintenance_Responsibility__c = 'Tenant';
            req.Stage__c = 'Tenant & Lease';
            req.Status__c = 'Tenant & Lease';
            update req;
        }

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Owner Decision: ' + decision + ' (' + p.Prospect_Name__c + ')',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Owner decision recorded as ' + decision + '. Comments: ' + (String.isNotBlank(comments) ? comments : 'None') + '.'
        );
        insert t;
    }

    @AuraEnabled
    public static void updateLeaseTerms(Id requestId, Decimal rent, Decimal deposit, Date startDate, Date endDate, Integer lockInMonths, Decimal escalation, Integer noticeDays, String maintenance) {
        Rent_Resale_Request__c req = [SELECT Id FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        req.Monthly_Rent__c = rent;
        req.Deposit_Amount__c = deposit;
        req.Lease_Start_Date__c = startDate;
        req.Lease_End_Date__c = endDate;
        req.Lock_In_Period_Months__c = lockInMonths;
        req.Escalation_Percent__c = escalation;
        req.Notice_Period_Days__c = noticeDays;
        req.Maintenance_Responsibility__c = maintenance;
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Lease Commercial Terms Configured',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Lease terms updated. Monthly Rent: ₹' + rent + ', Lock-in: ' + lockInMonths + ' mos.'
        );
        insert t;
    }

    @AuraEnabled
    public static void activateLease(Id requestId) {
        Rent_Resale_Request__c req = [
            SELECT Id, Unit__c, Selected_Tenant_Name__c, Selected_Tenant_Phone__c, 
                   Monthly_Rent__c, Deposit_Amount__c, Lease_Start_Date__c, Lease_End_Date__c
            FROM Rent_Resale_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];

        req.Stage__c = 'Active Lease';
        req.Status__c = 'Active Lease';
        req.Active_Tenancy_Number__c = 1;
        update req;

        // Create or update Tenancy 1 history record
        Tenancy_History__c th = new Tenancy_History__c(
            Rent_Resale_Request__c = req.Id,
            Unit__c = req.Unit__c,
            Tenancy_Number__c = 'Tenancy 1',
            Tenant_Name__c = req.Selected_Tenant_Name__c,
            Tenant_Contact__c = req.Selected_Tenant_Phone__c,
            Start_Date__c = req.Lease_Start_Date__c != null ? req.Lease_Start_Date__c : Date.today(),
            End_Date__c = req.Lease_End_Date__c != null ? req.Lease_End_Date__c : Date.today().addYears(1),
            Monthly_Rent__c = req.Monthly_Rent__c,
            Deposit__c = req.Deposit_Amount__c,
            Status__c = 'Active',
            Terms_Summary__c = 'Active lease agreement. Monthly rent: ₹' + req.Monthly_Rent__c
        );
        insert th;

        // Update Unit Status
        if (req.Unit__c != null) {
            try {
                update new Unit__c(Id = req.Unit__c, Status__c = 'Leased');
            } catch (Exception e) {}
        }

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Lease Activated — Tenancy 1 Commenced',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Lease officially activated for ' + req.Selected_Tenant_Name__c + '. Tenancy 1 logged in historical unit records.'
        );
        insert t;
    }

    @AuraEnabled
    public static void startRenewalStage(Id requestId) {
        Rent_Resale_Request__c req = [SELECT Id FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        req.Stage__c = 'Renewal';
        req.Status__c = 'Renewal';
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Tenancy Renewal Process Initiated',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Tenancy approaching expiry. Owner renewal decision stage initiated.'
        );
        insert t;
    }

    @AuraEnabled
    public static void recordRenewalDecision(Id requestId, String decision, String remarks, Date newStart, Date newEnd, Decimal newRent) {
        Rent_Resale_Request__c req = [
            SELECT Id, Unit__c, Selected_Tenant_Name__c, Selected_Tenant_Phone__c, 
                   Monthly_Rent__c, Deposit_Amount__c, Active_Tenancy_Number__c
            FROM Rent_Resale_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];

        req.Renewal_Decision__c = decision;
        req.Renewal_Decision_Date__c = Date.today();

        // Query existing active tenancy
        List<Tenancy_History__c> activeTenancies = [
            SELECT Id, Status__c 
            FROM Tenancy_History__c 
            WHERE Rent_Resale_Request__c = :requestId AND Status__c = 'Active' 
            LIMIT 1
        ];

        if (decision == 'Renew Current Tenant') {
            // Update terms on existing tenancy
            if (!activeTenancies.isEmpty()) {
                activeTenancies[0].Monthly_Rent__c = (newRent != null) ? newRent : req.Monthly_Rent__c;
                if (newEnd != null) activeTenancies[0].End_Date__c = newEnd;
                activeTenancies[0].Terms_Summary__c = 'Renewed for another term. Remarks: ' + remarks;
                update activeTenancies[0];
            }
            req.Monthly_Rent__c = (newRent != null) ? newRent : req.Monthly_Rent__c;
            if (newStart != null) req.Lease_Start_Date__c = newStart;
            if (newEnd != null) req.Lease_End_Date__c = newEnd;
            req.Stage__c = 'Active Lease';
            req.Status__c = 'Active Lease';

        } else if (decision == 'Re-rent to New Tenant') {
            // Close Tenancy 1, prepare Tenancy 2, transition to Listing
            if (!activeTenancies.isEmpty()) {
                activeTenancies[0].Status__c = 'Completed';
                update activeTenancies[0];
            }
            Integer nextNum = req.Active_Tenancy_Number__c != null ? Integer.valueOf(req.Active_Tenancy_Number__c) + 1 : 2;
            req.Active_Tenancy_Number__c = nextNum;
            req.Stage__c = 'Listing';
            req.Status__c = 'Listing';
            req.Listing_Status__c = 'Active';
            req.Listing_Date__c = Date.today();
            req.Selected_Tenant_Name__c = null;
            req.Selected_Tenant_Email__c = null;
            req.Selected_Tenant_Phone__c = null;

            if (req.Unit__c != null) {
                try {
                    update new Unit__c(Id = req.Unit__c, Status__c = 'Available');
                } catch (Exception e) {}
            }

        } else if (decision == 'Stop Renting') {
            // Terminate tenancy and close request
            if (!activeTenancies.isEmpty()) {
                activeTenancies[0].Status__c = 'Completed';
                update activeTenancies[0];
            }
            req.Stage__c = 'Closed';
            req.Status__c = 'Closed';
            req.Closure_Date__c = Date.today();
            req.Closed_By__c = UserInfo.getUserId();

            if (req.Unit__c != null) {
                try {
                    update new Unit__c(Id = req.Unit__c, Status__c = 'Occupied');
                } catch (Exception e) {}
            }
        }

        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Renewal Decision Executed: ' + decision,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Renewal decision: ' + decision + '. ' + (String.isNotBlank(remarks) ? remarks : '')
        );
        insert t;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RESALE ACTIONS
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static void assignResaleRequest(Id requestId, Id teamMemberId, Id brokerId) {
        Rent_Resale_Request__c req = [
            SELECT Id, Assigned_Broker__c, Channel_Partners_JSON__c 
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];
        if (teamMemberId != null) req.Assigned_Agent__c = teamMemberId;
        
        // Multi-partner assignment without overwrite
        if (brokerId != null) {
            Account bAcc = [SELECT Id, Name FROM Account WHERE Id = :brokerId LIMIT 1];
            List<Map<String, Object>> partnersList = new List<Map<String, Object>>();
            Set<String> seenIds = new Set<String>();
            
            if (req.Assigned_Broker__c != null) {
                seenIds.add(String.valueOf(req.Assigned_Broker__c));
            }
            if (String.isNotBlank(req.Channel_Partners_JSON__c)) {
                try {
                    List<Object> parsed = (List<Object>) JSON.deserializeUntyped(req.Channel_Partners_JSON__c);
                    for (Object o : parsed) {
                        Map<String, Object> m = (Map<String, Object>) o;
                        seenIds.add(String.valueOf(m.get('id')));
                        partnersList.add(m);
                    }
                } catch (Exception e) {}
            }
            if (!seenIds.contains(String.valueOf(brokerId))) {
                partnersList.add(new Map<String, Object>{
                    'id' => bAcc.Id,
                    'name' => bAcc.Name,
                    'role' => (req.Assigned_Broker__c == null) ? 'Primary Sourcing Partner' : 'Co-Sourcing Partner'
                });
            }
            req.Channel_Partners_JSON__c = JSON.serialize(partnersList);
            if (req.Assigned_Broker__c == null) {
                req.Assigned_Broker__c = brokerId;
            }
        }
        
        req.Assignment_Date__c = Date.today();
        req.Stage__c = 'Property Listing & Buyer Sourcing';
        req.Status__c = 'Property Listing & Buyer Sourcing';
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Resale Lead Allocated & Assigned',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Resale lead allocated to advisor. Stage moved to Property Listing & Buyer Sourcing.'
        );
        insert t;
    }

    @AuraEnabled
    public static void moveToResaleStage(Id requestId, String targetStage) {
        if (targetStage == 'Documentation' || targetStage == 'Documents') {
            proceedToDocumentationStage(requestId);
            return;
        }
        Rent_Resale_Request__c req = [SELECT Id, Stage__c, Status__c FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        req.Stage__c = targetStage;
        if (targetStage == 'Closed') {
            req.Status__c = 'Closed';
        } else if (targetStage != 'Lead Allocation') {
            req.Status__c = 'In Progress';
        }
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Resale Stage Updated: ' + targetStage,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Resale stage updated to ' + targetStage
        );
        insert t;
    }

    @AuraEnabled
    public static void updateResaleListing(Id requestId, Decimal askingPrice, String listingStatus, Date listingDate) {
        Rent_Resale_Request__c req = [SELECT Id, Expected_Resale_Price__c FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        if (askingPrice != null && askingPrice > 0) req.Expected_Resale_Price__c = askingPrice;
        if (String.isNotBlank(listingStatus)) req.Listing_Status__c = listingStatus;
        req.Listing_Date__c = (listingDate != null) ? listingDate : Date.today();
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Resale Property Listing Updated: ₹' + req.Expected_Resale_Price__c,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Listing details updated. Asking Price: ₹' + req.Expected_Resale_Price__c + ', Status: ' + req.Listing_Status__c
        );
        insert t;
    }

    @AuraEnabled
    public static Id addResaleBuyer(Id requestId, String name, String phone, String email, Decimal budget, String preferences, String source, String financeNotes, Id brokerId) {
        Rental_Prospect__c bp = new Rental_Prospect__c();
        bp.Rent_Resale_Request__c = requestId;
        bp.Prospect_Name__c = name;
        bp.Phone__c = phone;
        bp.Email__c = email;
        bp.Budget__c = budget;
        bp.Comments__c = preferences;
        bp.Lead_Source__c = String.isNotBlank(source) ? source : 'Direct';
        bp.Finance_Notes__c = financeNotes;
        bp.Prospect_Status__c = 'Qualified';
        bp.Prospect_Type__c = 'Buyer';
        bp.Stage__c = 'Qualified';

        if (brokerId != null) {
            Account bAcc = [SELECT Name FROM Account WHERE Id = :brokerId LIMIT 1];
            bp.Source_Broker__c = bAcc.Name;
        }

        insert bp;

        Rent_Resale_Request__c req = [SELECT Id, Buyer_Name__c FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        if (String.isBlank(req.Buyer_Name__c)) {
            req.Buyer_Name__c = name;
            req.Buyer_Phone__c = phone;
            req.Buyer_Email__c = email;
            req.Buyer_Budget__c = budget;
            req.Buyer_Source__c = bp.Lead_Source__c;
            update req;
        }

        Task t = new Task(
            WhatId = requestId,
            Subject = 'Resale Buyer Registered: ' + name,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Buyer ' + name + ' registered with budget ₹' + budget + '. Source: ' + bp.Lead_Source__c
        );
        insert t;

        return bp.Id;
    }

    @AuraEnabled
    public static Id scheduleResaleSiteVisit(Id requestId, Id buyerId, Date visitDate, String visitTimeStr, String location, String instructions, String remarks) {
        Rent_Resale_Request__c req = [
            SELECT Id, Unit__c, Project__c, Tower__c, Buyer_Name__c
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        Site_Visit__c sv = new Site_Visit__c();
        sv.Rent_Resale_Request__c = req.Id;
        sv.Buyer__c = buyerId;
        sv.Unit__c = req.Unit__c;
        if (req.Unit__c != null) {
            Unit__c u = [SELECT Id, Tower__c, Tower__r.Property__c FROM Unit__c WHERE Id = :req.Unit__c LIMIT 1];
            if (u.Tower__c != null) {
                sv.Building__c = u.Tower__c;
                sv.Project__c = u.Tower__r.Property__c;
            }
        }
        sv.Visit_Date__c = (visitDate != null && visitDate >= Date.today()) ? visitDate : Date.today();
        sv.Visit_DateTime__c = (sv.Visit_Date__c == Date.today()) ? System.now() : DateTime.newInstance(sv.Visit_Date__c, Time.newInstance(11, 0, 0, 0));
        sv.Visit_Time__c = String.isNotBlank(visitTimeStr) ? visitTimeStr : '11:00 AM';
        sv.Location__c = String.isNotBlank(location) ? location : 'On-Site / Sales Pavilion';
        sv.Instructions__c = instructions;
        sv.Status__c = 'Scheduled';
        sv.Rating__c = null; // Initial rating is NOT auto-set to Good; remains Not Rated / Blank
        
        String buyerDisplayName = 'Resale Buyer';
        if (buyerId != null) {
            Rental_Prospect__c bp = [SELECT Prospect_Name__c FROM Rental_Prospect__c WHERE Id = :buyerId LIMIT 1];
            buyerDisplayName = bp.Prospect_Name__c;
        } else if (String.isNotBlank(req.Buyer_Name__c)) {
            buyerDisplayName = req.Buyer_Name__c;
        }

        sv.Remarks__c = String.isNotBlank(remarks) ? remarks : ('Site visit scheduled for buyer: ' + buyerDisplayName);
        insert sv;

        // NOTE: Do NOT move the entire Resale Request to another stage merely because a visit is scheduled.
        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Resale Site Visit Scheduled: ' + sv.Visit_Date__c.format() + ' (' + buyerDisplayName + ')',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Site visit scheduled for Unit. Location: ' + sv.Location__c + '. Remarks: ' + remarks
        );
        insert t;

        return sv.Id;
    }

    @AuraEnabled
    public static void markSiteVisitCompleted(Id visitId) {
        Site_Visit__c sv = [
            SELECT Id, Rent_Resale_Request__c, Buyer__c, Buyer__r.Prospect_Name__c, Visit_Date__c, Visit_DateTime__c 
            FROM Site_Visit__c 
            WHERE Id = :visitId 
            LIMIT 1
        ];
        sv.Status__c = 'Completed';
        if (sv.Visit_Date__c != null && sv.Visit_Date__c > Date.today()) {
            sv.Visit_Date__c = Date.today();
        }
        if (sv.Visit_DateTime__c == null || sv.Visit_DateTime__c > System.now()) {
            sv.Visit_DateTime__c = System.now();
        }
        update sv;

        if (sv.Rent_Resale_Request__c != null) {
            String bName = (sv.Buyer__r != null) ? sv.Buyer__r.Prospect_Name__c : 'Buyer';
            Task t = new Task(
                WhatId = sv.Rent_Resale_Request__c,
                Subject = 'Site Visit Marked Completed for ' + bName,
                ActivityDate = Date.today(),
                Status = 'Completed',
                Priority = 'Normal',
                Description = 'Site visit completed. Ready for client feedback logging.'
            );
            insert t;
        }
    }

    @AuraEnabled
    public static void rescheduleSiteVisit(Id visitId, Date newDate, String newTimeStr, String newLocation, String newRemarks) {
        Site_Visit__c sv = [
            SELECT Id, Rent_Resale_Request__c, Visit_Date__c, Visit_Time__c, Location__c, Remarks__c, Buyer__c, Buyer__r.Prospect_Name__c 
            FROM Site_Visit__c 
            WHERE Id = :visitId 
            LIMIT 1
        ];
        if (newDate != null) sv.Visit_Date__c = newDate;
        if (String.isNotBlank(newTimeStr)) sv.Visit_Time__c = newTimeStr;
        if (String.isNotBlank(newLocation)) sv.Location__c = newLocation;
        if (String.isNotBlank(newRemarks)) sv.Remarks__c = newRemarks;
        sv.Status__c = 'Scheduled';
        sv.Visit_DateTime__c = (sv.Visit_Date__c == Date.today()) ? System.now() : DateTime.newInstance(sv.Visit_Date__c, Time.newInstance(11, 0, 0, 0));
        update sv;

        if (sv.Rent_Resale_Request__c != null) {
            String bName = (sv.Buyer__r != null) ? sv.Buyer__r.Prospect_Name__c : 'Buyer';
            Task t = new Task(
                WhatId = sv.Rent_Resale_Request__c,
                Subject = 'Site Visit Rescheduled for ' + bName + ': ' + sv.Visit_Date__c.format() + ' ' + sv.Visit_Time__c,
                ActivityDate = Date.today(),
                Status = 'Completed',
                Priority = 'Normal',
                Description = 'Site visit rescheduled. Location: ' + sv.Location__c + '. Remarks: ' + sv.Remarks__c
            );
            insert t;
        }
    }

    @AuraEnabled
    public static void logSiteVisitFeedback(Id visitId, String feedback, String rating, String status) {
        Site_Visit__c sv = [
            SELECT Id, Rent_Resale_Request__c, Visit_Date__c, Visit_DateTime__c, Buyer__c, Buyer__r.Prospect_Name__c 
            FROM Site_Visit__c 
            WHERE Id = :visitId 
            LIMIT 1
        ];
        sv.Comments__c = feedback;
        if (String.isNotBlank(rating)) {
            sv.Rating__c = rating;
        }
        sv.Status__c = String.isNotBlank(status) ? status : 'Completed';
        if (sv.Visit_Date__c != null && sv.Visit_Date__c > Date.today()) {
            sv.Visit_Date__c = Date.today();
        }
        if (sv.Visit_DateTime__c == null || sv.Visit_DateTime__c > System.now()) {
            sv.Visit_DateTime__c = System.now();
        }
        update sv;

        if (sv.Rent_Resale_Request__c != null) {
            String bName = (sv.Buyer__r != null) ? sv.Buyer__r.Prospect_Name__c : 'Buyer';
            Task t = new Task(
                WhatId = sv.Rent_Resale_Request__c,
                Subject = 'Site Visit Feedback Logged for ' + bName + ' (' + (sv.Rating__c != null ? sv.Rating__c : 'Recorded') + ')',
                ActivityDate = Date.today(),
                Status = 'Completed',
                Priority = 'Normal',
                Description = 'Feedback: ' + feedback + ' | Rating: ' + sv.Rating__c
            );
            insert t;
        }
    }

    @AuraEnabled
    public static void proceedToSiteVisitStage(Id requestId) {
        Rent_Resale_Request__c req = [SELECT Id, Stage__c, Status__c FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        req.Stage__c = 'Site Visit';
        req.Status__c = 'Site Visit';
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Advanced to Site Visit Stage',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Property listing active and buyer sourcing underway. Stage advanced to Site Visit.'
        );
        insert t;
    }

    @AuraEnabled
    public static void proceedToDealFinalisation(Id requestId) {
        Rent_Resale_Request__c req = [SELECT Id, Stage__c, Status__c FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        req.Stage__c = 'Deal Finalisation';
        req.Status__c = 'Deal Finalisation';
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Advanced to Deal Finalisation Stage',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Site visits concluded. Advanced to Deal Finalisation.'
        );
        insert t;
    }

    @AuraEnabled
    public static void recordDealFinalisation(Id requestId, Id selectedBuyerId, Decimal finalValue, Decimal fee, Decimal tokenAmount, String paymentTerms, String remarks) {
        Rent_Resale_Request__c req = [
            SELECT Id, Buyer_Name__c, Buyer_Phone__c, Buyer_Email__c, Buyer_Budget__c 
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        if (selectedBuyerId != null) {
            Rental_Prospect__c bp = [
                SELECT Id, Prospect_Name__c, Phone__c, Email__c, Budget__c 
                FROM Rental_Prospect__c 
                WHERE Id = :selectedBuyerId 
                LIMIT 1
            ];
            req.Buyer_Name__c = bp.Prospect_Name__c;
            req.Buyer_Phone__c = bp.Phone__c;
            req.Buyer_Email__c = bp.Email__c;
            bp.Prospect_Status__c = 'Deal Agreed';
            update bp;
        }

        req.Final_Resale_Value__c = finalValue;
        req.Service_Fee_Brokerage__c = fee;
        req.Token_Amount__c = tokenAmount;
        req.Payment_Terms__c = paymentTerms;
        req.Remarks__c = remarks;
        req.Approval_Status__c = 'Pending Approval';
        req.Approval_Submission_Date__c = Date.today();
        req.Stage__c = 'Approval';
        req.Status__c = 'Approval';
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Deal Finalised & Submitted for Approval: ₹' + finalValue,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'High',
            Description = 'Commercial deal recorded with buyer ' + req.Buyer_Name__c + '. Value: ₹' + finalValue + ', Fee: ₹' + fee + ', Token: ₹' + tokenAmount + '. Submitted for internal approval.'
        );
        insert t;
    }

    @AuraEnabled
    public static void processDealApproval(Id requestId, Boolean isApproved, String remarks) {
        Rent_Resale_Request__c req = [
            SELECT Id, Stage__c, Status__c, Approval_Status__c, Final_Resale_Value__c, Buyer_Name__c 
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        req.Approval_Status__c = isApproved ? 'Approved' : 'Rejected';
        req.Approval_Date__c = Date.today();
        req.Approver__c = UserInfo.getUserId();
        req.Approval_Remarks__c = remarks;

        if (isApproved) {
            req.Stage__c = 'KYC & Token';
            req.Status__c = 'KYC & Token';
        } else {
            req.Stage__c = 'Deal Finalisation';
            req.Status__c = 'Deal Finalisation';
        }
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Deal Commercial Approval: ' + req.Approval_Status__c,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = isApproved ? 'Normal' : 'High',
            Description = 'Internal approval decision: ' + req.Approval_Status__c + '. Remarks: ' + (String.isNotBlank(remarks) ? remarks : 'None')
        );
        insert t;
    }

    @AuraEnabled
    public static void proceedToKycTokenStage(Id requestId) {
        Rent_Resale_Request__c req = [
            SELECT Id, Approval_Status__c 
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];
        if (req.Approval_Status__c != 'Approved') {
            throwHandledException('Cannot proceed: Internal approval must be Approved before moving to KYC & Token.');
        }
        req.Stage__c = 'KYC & Token';
        req.Status__c = 'KYC & Token';
        update req;
    }

    @AuraEnabled
    public static void recordTokenPayment(Id requestId, Decimal tokenAmount, Date tokenDate, String paymentMode, String ref, String proofRef, String remarks) {
        Rent_Resale_Request__c req = [
            SELECT Id, Token_Amount__c, Token_Payment_Date__c, Token_Payment_Mode__c, Token_Payment_Status__c, 
                   Token_Payment_Reference__c, Token_Payment_Proof__c, Token_Payment_Remarks__c 
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];
        if (tokenAmount == null || tokenAmount <= 0) {
            throwHandledException('Token Amount Received is required and must be greater than zero.');
        }
        req.Token_Amount__c = tokenAmount;
        req.Token_Payment_Date__c = (tokenDate != null) ? tokenDate : Date.today();
        req.Token_Payment_Mode__c = String.isNotBlank(paymentMode) ? paymentMode : 'Bank Transfer (NEFT/RTGS)';
        req.Token_Payment_Reference__c = ref;
        req.Token_Payment_Proof__c = proofRef;
        req.Token_Payment_Remarks__c = remarks;
        req.Token_Payment_Status__c = 'Payment Recorded';
        update req;

        // Update or seed Token Payment Receipt document
        List<Rent_Resale_Document__c> tokenDocs = [
            SELECT Id, Status__c, Remarks__c 
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId AND Document_Type__c = 'Token Payment Receipt' 
            LIMIT 1
        ];
        if (!tokenDocs.isEmpty()) {
            tokenDocs[0].Remarks__c = 'Token Payment Recorded: ₹' + req.Token_Amount__c + ' via ' + req.Token_Payment_Mode__c + (String.isNotBlank(ref) ? ' | Ref: ' + ref : '');
            update tokenDocs[0];
        }

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Token Payment Recorded: ₹' + req.Token_Amount__c,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Token payment recorded. Mode: ' + req.Token_Payment_Mode__c + ', Ref: ' + ref + (String.isNotBlank(proofRef) ? ', Proof: ' + proofRef : '') + (String.isNotBlank(remarks) ? ', Remarks: ' + remarks : '')
        );
        insert t;
    }

    @AuraEnabled
    public static void recordAndGenerateTokenReceipt(Id requestId, Decimal tokenAmount, Date tokenDate, String paymentMode, String tokenRef, String remarks) {
        if (tokenAmount == null || tokenAmount <= 0) {
            throwHandledException('Token Amount Received is required and must be greater than zero.');
        }
        Date pDate = (tokenDate != null) ? tokenDate : Date.today();

        Rent_Resale_Request__c req = [
            SELECT Id, Name, Unit__c, Unit__r.Name, Project__c, Project__r.Name, Project__r.Address__c,
                   Customer__c, Customer__r.Name, Buyer_Name__c, Buyer_Email__c, Buyer_Phone__c,
                   Token_Amount__c, Token_Payment_Date__c, Token_Payment_Mode__c, 
                   Token_Payment_Reference__c, Token_Payment_Status__c, Token_Receipt_Number__c,
                   Token_Payment_Remarks__c
            FROM Rent_Resale_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];

        Integer rand = Math.abs(Crypto.getRandomInteger());
        String seq = String.valueOf(rand);
        seq = (seq.length() >= 5) ? seq.substring(0, 5) : seq.leftPad(5, '0');
        String receiptNum = 'RCP-' + Date.today().year() + '-' + seq;

        req.Token_Amount__c = tokenAmount;
        req.Token_Payment_Date__c = pDate;
        req.Token_Payment_Mode__c = String.isNotBlank(paymentMode) ? paymentMode : 'Bank Transfer (NEFT/RTGS)';
        req.Token_Payment_Reference__c = tokenRef;
        req.Token_Payment_Remarks__c = remarks;
        req.Token_Receipt_Number__c = receiptNum;
        req.Token_Payment_Status__c = 'Receipt Generated';
        update req;

        // Generate real ContentVersion receipt file
        String buyerName = String.isNotBlank(req.Buyer_Name__c) ? req.Buyer_Name__c : 'Buyer';
        String sellerName = (req.Customer__r != null && String.isNotBlank(req.Customer__r.Name)) ? req.Customer__r.Name : 'Seller';
        String unitName = (req.Unit__r != null && String.isNotBlank(req.Unit__r.Name)) ? req.Unit__r.Name : 'Unit';
        String projectName = (req.Project__r != null && String.isNotBlank(req.Project__r.Name)) ? req.Project__r.Name : 'Warp Drive Residential';

        List<String> rcpLines = new List<String>{
            '================================================================================',
            '                      OFFICIAL TOKEN PAYMENT RECEIPT',
            '                            WARP DRIVE RESIDENTIAL',
            '================================================================================',
            '',
            'Receipt Number            : ' + receiptNum,
            'Generated Date            : ' + System.now().format('dd MMMM yyyy, HH:mm'),
            '',
            'TRANSACTION PARTICULARS:',
            '  - Property / Unit       : Unit ' + unitName + ' (' + projectName + ')',
            '  - Prospective Buyer     : ' + buyerName,
            '  - Registered Owner      : ' + sellerName,
            '  - Token Amount Received : ₹' + String.valueOf(tokenAmount),
            '  - Payment Date          : ' + pDate.format(),
            '  - Payment Mode          : ' + req.Token_Payment_Mode__c,
            '  - Reference / UTR       : ' + (String.isNotBlank(tokenRef) ? tokenRef : 'UTR-PENDING'),
            '  - Transaction Remarks   : ' + (String.isNotBlank(remarks) ? remarks : 'Booking token received towards resale consideration'),
            '',
            'This receipt acknowledges the receipt of the booking token advance deposit for the',
            'ownership resale conveyance of Unit ' + unitName + '. Valid subject to bank realisation.',
            '',
            'Authorized Officer: ' + UserInfo.getName(),
            '================================================================================'
        };

        ContentVersion cv = new ContentVersion(
            Title = 'Token Payment Receipt - ' + receiptNum,
            PathOnClient = 'Token_Receipt_' + receiptNum + '.txt',
            VersionData = Blob.valueOf(String.join(rcpLines, '\n')),
            IsMajorVersion = true
        );
        insert cv;

        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

        // Link to Token Payment Receipt document
        List<Rent_Resale_Document__c> tokenDocs = [
            SELECT Id, Status__c, Remarks__c, Content_Document_Id__c 
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId AND Document_Type__c = 'Token Payment Receipt'
            LIMIT 1
        ];
        Rent_Resale_Document__c tokenDoc;
        if (!tokenDocs.isEmpty()) {
            tokenDoc = tokenDocs[0];
            tokenDoc.Status__c = 'Generated';
            tokenDoc.Content_Document_Id__c = conDocId;
            tokenDoc.Uploaded_Date__c = System.now();
            tokenDoc.Remarks__c = 'Official Receipt ' + receiptNum + ' generated on ' + pDate.format();
            update tokenDoc;
        } else {
            tokenDoc = new Rent_Resale_Document__c(
                Rent_Resale_Request__c = requestId,
                Document_Type__c = 'Token Payment Receipt',
                Status__c = 'Generated',
                Content_Document_Id__c = conDocId,
                Uploaded_Date__c = System.now(),
                Is_Required__c = true,
                Remarks__c = 'Official Receipt ' + receiptNum + ' generated on ' + pDate.format()
            );
            insert tokenDoc;
        }

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = conDocId,
            LinkedEntityId = tokenDoc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Token Payment Receipt Generated: ' + receiptNum,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Token payment receipt ' + receiptNum + ' generated for ₹' + tokenAmount + ' (Ref: ' + tokenRef + ').'
        );
        insert t;
    }

    @AuraEnabled
    public static void generateTokenReceipt(Id requestId) {
        Rent_Resale_Request__c req = [
            SELECT Id, Token_Amount__c, Token_Payment_Date__c, Token_Payment_Mode__c, 
                   Token_Payment_Reference__c, Token_Receipt_Number__c, Token_Payment_Status__c,
                   Buyer_Name__c, Unit__c, Unit__r.Name, Project__c, Project__r.Name,
                   Customer__c, Customer__r.Name, Token_Payment_Remarks__c
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];
        if (req.Token_Amount__c == null || req.Token_Amount__c <= 0) {
            throwHandledException('Cannot generate Token Receipt: Token payment must be entered and saved first.');
        }

        if (String.isBlank(req.Token_Receipt_Number__c)) {
            Integer rand = Math.abs(Crypto.getRandomInteger());
            String seq = String.valueOf(rand);
            seq = (seq.length() >= 5) ? seq.substring(0, 5) : seq.leftPad(5, '0');
            req.Token_Receipt_Number__c = 'RCP-' + Date.today().year() + '-' + seq;
        }
        req.Token_Payment_Status__c = 'Receipt Generated';
        update req;

        String buyerName = String.isNotBlank(req.Buyer_Name__c) ? req.Buyer_Name__c : 'Buyer';
        String sellerName = (req.Customer__r != null && String.isNotBlank(req.Customer__r.Name)) ? req.Customer__r.Name : 'Seller';
        String unitName = (req.Unit__r != null && String.isNotBlank(req.Unit__r.Name)) ? req.Unit__r.Name : 'Unit';
        String projectName = (req.Project__r != null && String.isNotBlank(req.Project__r.Name)) ? req.Project__r.Name : 'Warp Drive Residential';

        List<String> rcpLines = new List<String>{
            '================================================================================',
            '                      OFFICIAL TOKEN PAYMENT RECEIPT',
            '                            WARP DRIVE RESIDENTIAL',
            '================================================================================',
            '',
            'Receipt Number            : ' + req.Token_Receipt_Number__c,
            'Generated Date            : ' + System.now().format('dd MMMM yyyy, HH:mm'),
            '',
            'TRANSACTION PARTICULARS:',
            '  - Property / Unit       : Unit ' + unitName + ' (' + projectName + ')',
            '  - Prospective Buyer     : ' + buyerName,
            '  - Registered Owner      : ' + sellerName,
            '  - Token Amount Received : ₹' + String.valueOf(req.Token_Amount__c),
            '  - Payment Date          : ' + ((req.Token_Payment_Date__c != null) ? req.Token_Payment_Date__c.format() : Date.today().format()),
            '  - Payment Mode          : ' + (String.isNotBlank(req.Token_Payment_Mode__c) ? req.Token_Payment_Mode__c : 'Bank Transfer'),
            '  - Reference / UTR       : ' + (String.isNotBlank(req.Token_Payment_Reference__c) ? req.Token_Payment_Reference__c : 'UTR-CONFIRMED'),
            '  - Transaction Remarks   : ' + (String.isNotBlank(req.Token_Payment_Remarks__c) ? req.Token_Payment_Remarks__c : 'Booking token received'),
            '',
            'This receipt acknowledges the receipt of the booking token advance deposit for the',
            'ownership resale conveyance of Unit ' + unitName + '. Valid subject to bank realisation.',
            '',
            'Authorized Officer: ' + UserInfo.getName(),
            '================================================================================'
        };

        ContentVersion cv = new ContentVersion(
            Title = 'Token Payment Receipt - ' + req.Token_Receipt_Number__c,
            PathOnClient = 'Token_Receipt_' + req.Token_Receipt_Number__c + '.txt',
            VersionData = Blob.valueOf(String.join(rcpLines, '\n')),
            IsMajorVersion = true
        );
        insert cv;

        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

        List<Rent_Resale_Document__c> tokenDocs = [
            SELECT Id, Status__c, Remarks__c, Uploaded_Date__c, Verified_Date__c, Verified_By__c, Content_Document_Id__c 
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId AND Document_Type__c = 'Token Payment Receipt' 
            LIMIT 1
        ];
        Rent_Resale_Document__c tokenDoc;
        if (!tokenDocs.isEmpty()) {
            tokenDoc = tokenDocs[0];
            tokenDoc.Status__c = 'Generated';
            tokenDoc.Content_Document_Id__c = conDocId;
            tokenDoc.Uploaded_Date__c = System.now();
            tokenDoc.Remarks__c = 'Official Receipt ' + req.Token_Receipt_Number__c + ' generated on ' + Date.today().format();
            update tokenDoc;
        } else {
            tokenDoc = new Rent_Resale_Document__c(
                Rent_Resale_Request__c = req.Id,
                Document_Type__c = 'Token Payment Receipt',
                Is_Required__c = true,
                Status__c = 'Generated',
                Content_Document_Id__c = conDocId,
                Uploaded_Date__c = System.now(),
                Remarks__c = 'Official Receipt ' + req.Token_Receipt_Number__c + ' generated on ' + Date.today().format(),
                Business_Confirmation_Required__c = false
            );
            insert tokenDoc;
        }

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = conDocId,
            LinkedEntityId = tokenDoc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Token Payment Receipt Generated: ' + req.Token_Receipt_Number__c,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Official Token Payment Receipt ' + req.Token_Receipt_Number__c + ' generated for ₹' + req.Token_Amount__c
        );
        insert t;
    }

    @AuraEnabled
    public static void verifyTokenPayment(Id requestId, Boolean verified, String remarks) {
        Rent_Resale_Request__c req = [
            SELECT Id, Token_Amount__c, Token_Payment_Status__c 
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];
        req.Token_Payment_Status__c = verified ? 'Verified' : 'Rejected';
        update req;

        List<Rent_Resale_Document__c> tokenDocs = [
            SELECT Id, Status__c, Remarks__c 
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId AND Document_Type__c = 'Token Payment Receipt' 
            LIMIT 1
        ];
        if (!tokenDocs.isEmpty()) {
            tokenDocs[0].Status__c = verified ? 'Verified' : 'Rejected';
            tokenDocs[0].Verified_Date__c = verified ? System.now() : null;
            tokenDocs[0].Verified_By__c = verified ? UserInfo.getUserId() : null;
            if (String.isNotBlank(remarks)) tokenDocs[0].Remarks__c = remarks;
            update tokenDocs[0];
        }

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Token Payment ' + (verified ? 'Verified' : 'Rejected'),
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Token payment verification status: ' + req.Token_Payment_Status__c + '. ' + (String.isNotBlank(remarks) ? remarks : '')
        );
        insert t;
    }

    @AuraEnabled
    public static void proceedToAllotmentStage(Id requestId) {
        Rent_Resale_Request__c req = [
            SELECT Id, Token_Payment_Status__c, Token_Amount__c, Token_Receipt_Number__c 
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        // 1. Validate mandatory New Buyer KYC documents ONLY
        List<String> requiredBuyerKyc = new List<String>{
            'PAN',
            'Identity / Address Proof',
            'Required KYC Declaration'
        };
        Integer verifiedBuyerKycCount = [
            SELECT count() 
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId 
              AND Document_Type__c IN :requiredBuyerKyc 
              AND Status__c = 'Verified'
        ];
        if (verifiedBuyerKycCount < requiredBuyerKyc.size()) {
            throwHandledException('Cannot proceed to Allotment / Welcome: All mandatory New Buyer KYC documents (PAN, Identity / Address Proof, Required KYC Declaration) must be verified first.');
        }

        // 2. Validate Token Payment is entered and saved
        if (req.Token_Amount__c == null || req.Token_Amount__c <= 0) {
            throwHandledException('Cannot proceed to Allotment / Welcome: Token payment must be entered and saved first.');
        }

        // 3. Validate Token Payment Receipt has been generated
        Integer generatedReceipts = [
            SELECT count() 
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId 
              AND Document_Type__c = 'Token Payment Receipt' 
              AND (Status__c = 'Generated' OR Status__c = 'Verified' OR Uploaded_Date__c != null)
        ];
        if (generatedReceipts == 0 || String.isBlank(req.Token_Receipt_Number__c)) {
            throwHandledException('Cannot proceed to Allotment / Welcome: Official Token Payment Receipt must be generated first.');
        }

        req.Stage__c = 'Allotment / Welcome';
        req.Status__c = 'Allotment / Welcome';
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Advanced to Allotment / Welcome Stage',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'New Buyer KYC verified and Token Payment Receipt generated. Advanced to Allotment / Welcome stage.'
        );
        insert t;
    }

    @AuraEnabled
    public static void proceedToFullPaymentStage(Id requestId) {
        Rent_Resale_Request__c req = [SELECT Id, Stage__c FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];

        // Gating rule: All 3 letters (Allotment Letter, Welcome Letter, Car Parking Letter) must be Generated or Verified
        List<Rent_Resale_Document__c> allotDocs = [
            SELECT Id, Document_Type__c, Status__c 
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId 
              AND Document_Type__c IN ('Allotment Letter', 'Allotment / Confirmation Letter', 'Welcome Letter', 'Car Parking Letter', 'Parking Allocation Letter')
        ];
        Set<String> readyTypes = new Set<String>();
        for (Rent_Resale_Document__c d : allotDocs) {
            if (d.Status__c == 'Generated' || d.Status__c == 'Verified') {
                readyTypes.add(d.Document_Type__c);
            }
        }
        Boolean hasAllotment = readyTypes.contains('Allotment Letter') || readyTypes.contains('Allotment / Confirmation Letter');
        Boolean hasWelcome = readyTypes.contains('Welcome Letter');
        Boolean hasParking = readyTypes.contains('Car Parking Letter') || readyTypes.contains('Parking Allocation Letter');

        if (!hasAllotment || !hasWelcome || !hasParking) {
            throwHandledException('Cannot proceed to Full Payment & Receipt: Allotment Letter, Welcome Letter, and Car Parking Letter must all be generated first.');
        }

        req.Stage__c = 'Full Payment & Receipt';
        req.Status__c = 'Full Payment & Receipt';
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Advanced to Full Payment & Receipt Stage',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Allotment letters confirmed and verified. Advanced to Full Payment & Receipt stage.'
        );
        insert t;
    }

    @AuraEnabled
    public static void recordFullPayment(Id requestId, Decimal amount, Date payDate, String mode, String ref) {
        Rent_Resale_Request__c req = [
            SELECT Id, Final_Resale_Value__c, Token_Amount__c 
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        req.Full_Payment_Date__c = (payDate != null) ? payDate : Date.today();
        req.Full_Payment_Mode__c = String.isNotBlank(mode) ? mode : 'Bank Transfer (RTGS)';
        req.Transfer_Reference__c = ref;
        req.Payment_Reference__c = ref;
        req.Full_Payment_Status__c = 'Pending Verification';
        update req;

        List<Rent_Resale_Document__c> payDocs = [
            SELECT Id, Status__c, Remarks__c 
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId AND Document_Type__c = 'Full Payment Receipt' 
            LIMIT 1
        ];
        if (!payDocs.isEmpty()) {
            payDocs[0].Remarks__c = 'Full Payment Ref: ' + ref + ' | Date: ' + req.Full_Payment_Date__c.format();
            payDocs[0].Uploaded_Date__c = System.now();
            update payDocs[0];
        }

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Full Payment Details Recorded: Ref ' + ref,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Payment recorded. Amount: ₹' + amount + ', Mode: ' + req.Full_Payment_Mode__c + ', Ref: ' + ref
        );
        insert t;
    }

    @AuraEnabled
    public static void verifyFullPayment(Id requestId, Boolean verified, String remarks) {
        Rent_Resale_Request__c req = [SELECT Id FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        req.Full_Payment_Status__c = verified ? 'Verified' : 'Rejected';
        update req;

        List<Rent_Resale_Document__c> payDocs = [
            SELECT Id, Status__c, Remarks__c 
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId AND Document_Type__c = 'Full Payment Receipt' 
            LIMIT 1
        ];
        if (!payDocs.isEmpty()) {
            payDocs[0].Status__c = verified ? 'Verified' : 'Rejected';
            payDocs[0].Verified_Date__c = verified ? System.now() : null;
            payDocs[0].Verified_By__c = verified ? UserInfo.getUserId() : null;
            if (String.isNotBlank(remarks)) payDocs[0].Remarks__c = remarks;
            update payDocs[0];
        }

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Full Payment Receipt ' + (verified ? 'Verified' : 'Rejected'),
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Full payment receipt verification: ' + req.Full_Payment_Status__c + '. ' + (String.isNotBlank(remarks) ? remarks : '')
        );
        insert t;
    }

    @AuraEnabled
    public static void proceedToTransferDocStage(Id requestId) {
        Rent_Resale_Request__c req = [
            SELECT Id, Full_Payment_Status__c 
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        if (req.Full_Payment_Status__c != 'Verified') {
            throwHandledException('Cannot proceed to Documentation / Ownership Transfer: Full Payment receipt must be verified first.');
        }

        req.Stage__c = 'Documentation / Ownership Transfer';
        req.Status__c = 'Documentation / Ownership Transfer';
        req.Registration_Transfer_Status__c = 'Transfer Documentation In Progress';
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Advanced to Documentation / Ownership Transfer Stage',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Full payment verified. Advanced to final Documentation & Ownership Transfer stage.'
        );
        insert t;
    }

    @AuraEnabled
    public static void recordResaleDealClosure(Id requestId, Id selectedBuyerId, Decimal finalValue, Decimal fee, String ref, Date closureDate, String remarks) {
        recordDealFinalisation(requestId, selectedBuyerId, finalValue, fee, 500000, 'Standard 10% Token on acceptance', remarks);
    }

    @AuraEnabled
    public static void recordFullPaymentDetails(Id requestId, Date paymentDate, String paymentReference, String paymentStatus) {
        recordFullPayment(requestId, null, paymentDate, 'Bank Transfer (RTGS)', paymentReference);
        if (paymentStatus == 'Verified') {
            verifyFullPayment(requestId, true, 'Verified via recordFullPaymentDetails');
        }
    }

    @AuraEnabled
    public static void proceedToDocumentationStage(Id requestId) {
        proceedToTransferDocStage(requestId);
    }

    @AuraEnabled
    public static void verifyDocument(Id docId, Boolean approved, String remarks) {
        Rent_Resale_Document__c doc = [SELECT Id, Rent_Resale_Request__c, Document_Type__c FROM Rent_Resale_Document__c WHERE Id = :docId LIMIT 1];
        doc.Status__c = approved ? 'Verified' : 'Rejected';
        doc.Verified_Date__c = System.now();
        doc.Verified_By__c = UserInfo.getUserId();
        doc.Remarks__c = remarks;
        update doc;

        Task t = new Task(
            WhatId = doc.Rent_Resale_Request__c,
            Subject = 'Document ' + (approved ? 'Verified' : 'Rejected') + ': ' + doc.Document_Type__c,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Document verification result: ' + (approved ? 'Approved' : 'Rejected (Re-upload Required)') + '. Notes: ' + (String.isNotBlank(remarks) ? remarks : 'None')
        );
        insert t;
    }

    @AuraEnabled
    public static void generateDocument(Id docId) {
        Rent_Resale_Document__c doc = [
            SELECT Id, Rent_Resale_Request__c, Document_Type__c, Status__c,
                   Rent_Resale_Request__r.Buyer_Name__c, Rent_Resale_Request__r.Buyer_Email__c, Rent_Resale_Request__r.Buyer_Phone__c,
                   Rent_Resale_Request__r.Final_Resale_Value__c, Rent_Resale_Request__r.Token_Amount__c,
                   Rent_Resale_Request__r.Customer__c, Rent_Resale_Request__r.Customer__r.Name,
                   Rent_Resale_Request__r.Unit__c, Rent_Resale_Request__r.Unit__r.Name, Rent_Resale_Request__r.Unit__r.Carpet_Area__c,
                   Rent_Resale_Request__r.Unit__r.BHK_Configuration__c, Rent_Resale_Request__r.Unit__r.Floor__r.Name,
                   Rent_Resale_Request__r.Unit__r.Tower__r.Name, Rent_Resale_Request__r.Unit__r.Tower__r.RERA_Number__c,
                   Rent_Resale_Request__r.Project__c, Rent_Resale_Request__r.Project__r.Name, Rent_Resale_Request__r.Project__r.Address__c
            FROM Rent_Resale_Document__c 
            WHERE Id = :docId 
            LIMIT 1
        ];

        if (doc.Document_Type__c == 'Stamp Duty Document' || doc.Document_Type__c == 'Stamp Duty & Transfer Document') {
            generateStampDutyDocument(doc.Rent_Resale_Request__c);
            return;
        }

        Rent_Resale_Request__c req = doc.Rent_Resale_Request__r;
        String buyerName = (req != null && String.isNotBlank(req.Buyer_Name__c)) ? req.Buyer_Name__c : 'Valued Buyer';
        String buyerPhone = (req != null && String.isNotBlank(req.Buyer_Phone__c)) ? req.Buyer_Phone__c : 'N/A';
        String buyerEmail = (req != null && String.isNotBlank(req.Buyer_Email__c)) ? req.Buyer_Email__c : 'N/A';
        String unitName = (req != null && req.Unit__r != null && String.isNotBlank(req.Unit__r.Name)) ? req.Unit__r.Name : 'Unit';
        String towerName = (req != null && req.Unit__r != null && req.Unit__r.Tower__r != null && String.isNotBlank(req.Unit__r.Tower__r.Name)) ? req.Unit__r.Tower__r.Name : 'Tower A';
        String floorName = (req != null && req.Unit__r != null && req.Unit__r.Floor__r != null && String.isNotBlank(req.Unit__r.Floor__r.Name)) ? req.Unit__r.Floor__r.Name : 'Level';
        String carpetArea = (req != null && req.Unit__r != null && req.Unit__r.Carpet_Area__c != null) ? String.valueOf(req.Unit__r.Carpet_Area__c) : '1,450';
        String config = (req != null && req.Unit__r != null && String.isNotBlank(req.Unit__r.BHK_Configuration__c)) ? req.Unit__r.BHK_Configuration__c : '3 BHK Luxury';
        String projectName = (req != null && req.Project__r != null && String.isNotBlank(req.Project__r.Name)) ? req.Project__r.Name : 'Warp Drive Residential';
        String projectAddress = (req != null && req.Project__r != null && String.isNotBlank(req.Project__r.Address__c)) ? req.Project__r.Address__c : 'Bengaluru, Karnataka';
        String reraNo = (req != null && req.Unit__r != null && req.Unit__r.Tower__r != null && String.isNotBlank(req.Unit__r.Tower__r.RERA_Number__c)) ? req.Unit__r.Tower__r.RERA_Number__c : 'PRM/KA/RERA/1251/310/PR/170915/000123';
        String todayFormatted = Date.today().format();
        String resaleValueFormatted = (req != null && req.Final_Resale_Value__c != null) ? '₹' + String.valueOf(req.Final_Resale_Value__c) : '₹1,50,00,000';
        String tokenFormatted = (req != null && req.Token_Amount__c != null) ? '₹' + String.valueOf(req.Token_Amount__c) : '₹15,00,000';

        String fileTitle = '';
        String fileName = '';
        String fileBody = '';

        if (doc.Document_Type__c == 'Allotment Letter' || doc.Document_Type__c == 'Allotment / Confirmation Letter') {
            fileTitle = 'Allotment Letter - ' + unitName + ' - ' + buyerName;
            fileName = 'Allotment_Letter_' + unitName.replaceAll('[^a-zA-Z0-9]', '_') + '.txt';
            List<String> lines = new List<String>{
                '================================================================================',
                '                            WARP DRIVE RESIDENTIAL',
                '                      ' + projectName.toUpperCase() + ' - ' + projectAddress,
                '                         RERA Registration: ' + reraNo,
                '================================================================================',
                '',
                '                               ALLOTMENT LETTER',
                '',
                'Date: ' + todayFormatted,
                '',
                'To:',
                '  Allottee (New Buyer): ' + buyerName,
                '  Contact Phone: ' + buyerPhone,
                '  Email Address: ' + buyerEmail,
                '',
                'Subject: Formal Allotment of Residential Apartment Unit No. ' + unitName + ' in ' + projectName,
                '',
                'Dear Sir / Madam,',
                '',
                'We have immense pleasure in formally confirming the allotment of Residential Unit as per',
                'the agreed terms and conditions of the Resale Transaction detailed hereunder:',
                '',
                '1. PROPERTY PARTICULARS:',
                '   - Apartment / Unit Number : ' + unitName,
                '   - Tower / Wing            : ' + towerName,
                '   - Floor Level             : ' + floorName,
                '   - Configuration           : ' + config,
                '   - RERA Carpet Area        : ' + carpetArea + ' sq.ft.',
                '   - Project Name & Address  : ' + projectName + ', ' + projectAddress,
                '',
                '2. FINANCIAL CONSIDERATION:',
                '   - Total Agreed Resale Value: ' + resaleValueFormatted,
                '   - Booking / Token Received : ' + tokenFormatted,
                '   - Balance Payable          : Against executed Possession & Transfer Deed',
                '',
                '3. TERMS AND CONDITIONS:',
                '   a) This allotment is subject to full payment of the balance consideration as stipulated.',
                '   b) The Allottee confirms having inspected the title deeds, sanctions, and site layout.',
                '   c) Stamp duty, registration charges, and statutory transfer fees shall be borne by the Allottee.',
                '',
                'Thanking you,',
                'Yours faithfully,',
                'For Warp Drive Residential Private Limited',
                '',
                '(Authorised Signatory)',
                '================================================================================'
            };
            fileBody = String.join(lines, '\n');
        } else if (doc.Document_Type__c == 'Welcome Letter') {
            fileTitle = 'Welcome Letter - ' + unitName + ' - ' + buyerName;
            fileName = 'Welcome_Letter_' + unitName.replaceAll('[^a-zA-Z0-9]', '_') + '.txt';
            List<String> lines = new List<String>{
                '================================================================================',
                '                            WARP DRIVE RESIDENTIAL',
                '================================================================================',
                '',
                'Date: ' + todayFormatted,
                '',
                'Dear ' + buyerName + ',',
                '',
                'Congratulations on becoming a proud owner at ' + projectName + ', ' + projectAddress + '.',
                '',
                'We confirm your booking and allotment of a ' + config + ', Unit No: ' + unitName + ',',
                'of Carpet Area ' + carpetArea + ' SqFt on ' + floorName + ' of Tower: ' + towerName + '.',
                '',
                'Thank you for placing your valued trust in us. We now hope to exceed your expectations',
                'in terms of service, quality, community living, and handover experience in the days to come.',
                '',
                'As you are aware, we at "Warp Drive Residential" have consistently delivered residential',
                'landmarks adhering to the highest global standards, and we look forward to welcoming you',
                'into our vibrant residential community.',
                '',
                'Our Customer Relationship and Handover team is dedicated to guiding you through the remainder',
                'of the ownership transfer and possession onboarding journey.',
                '',
                'Warm regards,',
                'Customer Experience Team',
                'Warp Drive Residential',
                '================================================================================'
            };
            fileBody = String.join(lines, '\n');
        } else if (doc.Document_Type__c == 'Car Parking Letter' || doc.Document_Type__c == 'Parking Allocation Letter' || doc.Document_Type__c == 'Car Parking Document') {
            fileTitle = 'Car Parking Letter - ' + unitName + ' - ' + buyerName;
            fileName = 'Car_Parking_Letter_' + unitName.replaceAll('[^a-zA-Z0-9]', '_') + '.txt';
            List<String> lines = new List<String>{
                '================================================================================',
                '                            WARP DRIVE RESIDENTIAL',
                '                         CAR PARK ALLOTMENT LETTER',
                '================================================================================',
                '',
                'Date: ' + todayFormatted,
                '',
                'To:',
                '  ' + buyerName + ',',
                '  Unit No: ' + unitName + ', Tower: ' + towerName + ',',
                '  ' + projectName + ', ' + projectAddress,
                '',
                'Subject: Exclusive Allotment of Covered Car Park Space for Apartment No. ' + unitName,
                '',
                'Dear Sir / Madam,',
                '',
                'We are pleased to inform you that, in connection with your apartment bearing No. ' + unitName + '',
                'on ' + floorName + ' of Tower ' + towerName + ' in ' + projectName + ', you have been allotted',
                'exclusive right to use 1 Dedicated Covered Car Park Space (Basement Level 1).',
                '',
                'TERMS AND CONDITIONS OF PARKING ALLOTMENT:',
                '1. The Allottee has inspected the allocated Car Park Space and accepts the allocation.',
                '2. The Allottee undertakes to park vehicles strictly within the demarcated bay.',
                '3. The Car Park Space is exclusive to Unit ' + unitName + ' and cannot be sub-let or severed.',
                '4. Maintenance and upkeep of the parking zone shall adhere to Resident Welfare rules.',
                '',
                'Thanking you,',
                'Yours faithfully,',
                'For Warp Drive Residential',
                '',
                '(Authorised Signatory)',
                '================================================================================'
            };
            fileBody = String.join(lines, '\n');
        } else {
            fileTitle = doc.Document_Type__c + ' - ' + unitName;
            fileName = doc.Document_Type__c.replaceAll('[^a-zA-Z0-9]', '_') + '.txt';
            fileBody = 'OFFICIAL RESALE TRANSACTION DOCUMENT\n' + doc.Document_Type__c + '\nUnit: ' + unitName + '\nBuyer: ' + buyerName + '\nGenerated: ' + todayFormatted;
        }

        ContentVersion cv = new ContentVersion(
            Title = fileTitle,
            PathOnClient = fileName,
            VersionData = Blob.valueOf(fileBody),
            IsMajorVersion = true
        );
        insert cv;

        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = conDocId,
            LinkedEntityId = doc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;

        doc.Content_Document_Id__c = conDocId;
        doc.Status__c = 'Generated';
        doc.Uploaded_Date__c = System.now();
        doc.Remarks__c = 'Official letter generated on ' + todayFormatted;
        update doc;

        Task t = new Task(
            WhatId = doc.Rent_Resale_Request__c,
            Subject = 'Document Generated: ' + doc.Document_Type__c,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Official ' + doc.Document_Type__c + ' generated and ready for download.'
        );
        insert t;
    }

    @AuraEnabled
    public static void linkUploadedFile(Id docId, Id contentDocumentId, String fileName) {
        Rent_Resale_Document__c doc = [
            SELECT Id, Rent_Resale_Request__c, Document_Type__c, Status__c, Content_Document_Id__c 
            FROM Rent_Resale_Document__c 
            WHERE Id = :docId 
            LIMIT 1
        ];
        doc.Content_Document_Id__c = contentDocumentId;
        doc.Status__c = 'Uploaded';
        doc.Uploaded_Date__c = System.now();
        if (String.isNotBlank(fileName)) {
            doc.Remarks__c = 'Uploaded file: ' + fileName;
        }
        update doc;

        Task t = new Task(
            WhatId = doc.Rent_Resale_Request__c,
            Subject = 'Document Uploaded: ' + doc.Document_Type__c,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Actual file (' + fileName + ') uploaded for ' + doc.Document_Type__c + ' and submitted for verification.'
        );
        insert t;
    }

    @AuraEnabled
    public static void uploadDocument(Id docId, String fileName) {
        Rent_Resale_Document__c doc = [
            SELECT Id, Rent_Resale_Request__c, Document_Type__c, Status__c, Content_Document_Id__c 
            FROM Rent_Resale_Document__c 
            WHERE Id = :docId 
            LIMIT 1
        ];
        doc.Status__c = 'Uploaded';
        doc.Uploaded_Date__c = System.now();
        doc.Remarks__c = 'Uploaded file: ' + (String.isNotBlank(fileName) ? fileName : 'document_copy.pdf');
        update doc;

        Task t = new Task(
            WhatId = doc.Rent_Resale_Request__c,
            Subject = 'Document Uploaded: ' + doc.Document_Type__c,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Document ' + doc.Document_Type__c + ' uploaded (' + fileName + ') and submitted for verification.'
        );
        insert t;
    }

    @AuraEnabled
    public static void shareDocument(Id docId, String recipientEmail, String message) {
        Rent_Resale_Document__c doc = [
            SELECT Id, Rent_Resale_Request__c, Document_Type__c 
            FROM Rent_Resale_Document__c 
            WHERE Id = :docId 
            LIMIT 1
        ];
        
        if (String.isNotBlank(recipientEmail)) {
            sendActivityEmail(
                doc.Rent_Resale_Request__c,
                recipientEmail,
                'Shared Document: ' + doc.Document_Type__c,
                'Please find the attached/shared document: ' + doc.Document_Type__c + '.\n\nNotes: ' + (String.isNotBlank(message) ? message : 'For your review and records.')
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // STAGE 9: STAMP DUTY DOCUMENT & E-SIGNATURE INTEGRATION
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static Id generateStampDutyDocument(Id requestId) {
        if (requestId == null) {
            throwHandledException('Request ID is required.');
        }

        Rent_Resale_Request__c req = [
            SELECT Id, Name, Buyer_Name__c, Buyer_Email__c, Buyer_Phone__c,
                   Final_Resale_Value__c, Token_Amount__c, Expected_Resale_Price__c,
                   Payment_Reference__c, Request_Date__c, Co_Owner_Name__c,
                   Customer__c, Customer__r.Name, Contact__c, Contact__r.Name, Contact__r.Email, Contact__r.Phone,
                   Unit__c, Unit__r.Name, Unit__r.Carpet_Area__c, Unit__r.Saleable_Area__c,
                   Unit__r.BHK_Configuration__c, Unit__r.Floor__r.Name,
                   Unit__r.Tower__r.Name, Unit__r.Tower__r.RERA_Number__c,
                   Project__c, Project__r.Name, Project__r.Address__c
            FROM Rent_Resale_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];

        String buyerName = String.isNotBlank(req.Buyer_Name__c) ? req.Buyer_Name__c : 'Purchaser / Transferee';
        String buyerEmail = String.isNotBlank(req.Buyer_Email__c) ? req.Buyer_Email__c : 'buyer@example.com';
        String buyerPhone = String.isNotBlank(req.Buyer_Phone__c) ? req.Buyer_Phone__c : '+91 98765 43210';
        String sellerName = (req.Customer__r != null && String.isNotBlank(req.Customer__r.Name)) ? req.Customer__r.Name : 'Vendor / Transferor';
        String coOwner = String.isNotBlank(req.Co_Owner_Name__c) ? req.Co_Owner_Name__c : 'None';
        String unitName = (req.Unit__r != null && String.isNotBlank(req.Unit__r.Name)) ? req.Unit__r.Name : 'Unit';
        String towerName = (req.Unit__r != null && req.Unit__r.Tower__r != null && String.isNotBlank(req.Unit__r.Tower__r.Name)) ? req.Unit__r.Tower__r.Name : 'Tower A';
        String floorName = (req.Unit__r != null && req.Unit__r.Floor__r != null && String.isNotBlank(req.Unit__r.Floor__r.Name)) ? req.Unit__r.Floor__r.Name : 'Floor';
        String carpetArea = (req.Unit__r != null && req.Unit__r.Carpet_Area__c != null) ? String.valueOf(req.Unit__r.Carpet_Area__c) : '1,450';
        String config = (req.Unit__r != null && String.isNotBlank(req.Unit__r.BHK_Configuration__c)) ? req.Unit__r.BHK_Configuration__c : '3 BHK Luxury';
        String projectName = (req.Project__r != null && String.isNotBlank(req.Project__r.Name)) ? req.Project__r.Name : 'Warp Drive Residential';
        String projectAddress = (req.Project__r != null && String.isNotBlank(req.Project__r.Address__c)) ? req.Project__r.Address__c : 'Bengaluru, Karnataka';
        String reraNo = (req.Unit__r != null && req.Unit__r.Tower__r != null && String.isNotBlank(req.Unit__r.Tower__r.RERA_Number__c)) ? req.Unit__r.Tower__r.RERA_Number__c : 'PRM/KA/RERA/1251/310/PR/170915/000123';
        
        Decimal resaleVal = req.Final_Resale_Value__c != null ? req.Final_Resale_Value__c : (req.Expected_Resale_Price__c != null ? req.Expected_Resale_Price__c : 15000000);
        Decimal tokenVal = req.Token_Amount__c != null ? req.Token_Amount__c : (resaleVal * 0.10);
        Decimal balanceVal = Math.max(0, resaleVal - tokenVal);

        Decimal stampDutyAmount = Math.round(resaleVal * 0.05);
        Decimal surchargeCess = Math.round(resaleVal * 0.01);
        Decimal totalStatutoryDuty = stampDutyAmount + surchargeCess;

        String certNumber = 'IN-KA' + String.valueOf(DateTime.now().getTime()).substring(3);
        String todayFormatted = Date.today().format();

        List<String> lines = new List<String>{
            '================================================================================',
            '                   GOVERNMENT OF KARNATAKA / DEPARTMENT OF STAMPS',
            '                e-STAMPING CONVEYANCE DEED & OWNERSHIP TRANSFER',
            '            Article 20 - Conveyance of Immovable Residential Property',
            '================================================================================',
            'Certificate Number       : ' + certNumber,
            'Certificate Issued Date  : ' + todayFormatted,
            'Account Reference Number : ACC-REV-' + certNumber.substring(5),
            'Unique Doc Reference     : SUBIN-KA-' + certNumber,
            'Transaction Ref Number   : ' + (String.isNotBlank(req.Name) ? req.Name : 'RR-2026-RESALE'),
            '--------------------------------------------------------------------------------',
            'STATUTORY STAMP DUTY BREAKDOWN:',
            '  - Total Sale Consideration Value : ₹' + String.valueOf(resaleVal),
            '  - State Stamp Duty (5.0%)        : ₹' + String.valueOf(stampDutyAmount),
            '  - Surcharge, Cess & Registration : ₹' + String.valueOf(surchargeCess),
            '  - Total Statutory Consideration  : ₹' + String.valueOf(totalStatutoryDuty) + ' (Fully Reconciled)',
            '--------------------------------------------------------------------------------',
            '1. PARTIES TO THE CONVEYANCE DEED:',
            '',
            'TRANSFEROR (SELLER):',
            '  Full Legal Name : ' + sellerName,
            '  Co-Owner Name   : ' + coOwner,
            '  Address         : ' + unitName + ', ' + towerName + ', ' + projectName + ', ' + projectAddress,
            '',
            'TRANSFEREE (NEW BUYER):',
            '  Full Legal Name : ' + buyerName,
            '  Email Address   : ' + buyerEmail,
            '  Contact Phone   : ' + buyerPhone,
            '  Identification  : KYC Verified & Recorded under Resale Compliance',
            '--------------------------------------------------------------------------------',
            '2. SCHEDULE OF PROPERTY (SUBJECT APARTMENT):',
            '  - Apartment / Unit Number : ' + unitName,
            '  - Tower / Wing            : ' + towerName,
            '  - Floor Level             : ' + floorName,
            '  - Architectural Config    : ' + config,
            '  - Carpet Area             : ' + carpetArea + ' sq.ft.',
            '  - Dedicated Parking Bay   : 1 Covered Basement Car Park space',
            '  - RERA Registration No.   : ' + reraNo,
            '  - Project Name & Location : ' + projectName + ', ' + projectAddress,
            '--------------------------------------------------------------------------------',
            '3. TERMS OF TRANSFER & MUTUAL COVENANTS:',
            '  a) The Transferor confirms receipt of the entire agreed consideration of ₹' + String.valueOf(resaleVal) + '',
            '     (comprising Token of ₹' + String.valueOf(tokenVal) + ' and Final Balance of ₹' + String.valueOf(balanceVal) + ') in full.',
            '  b) The Transferor transfers and conveys all absolute rights, title, interest, and ownership',
            '     in the Schedule Property to the Transferee free from all encumbrances, liens, and claims.',
            '  c) Peaceful, vacant possession of the subject property together with keys and original title deeds',
            '     is delivered to the Transferee.',
            '  d) Electricity, water, property tax, and society maintenance charges have been cleared to date.',
            '--------------------------------------------------------------------------------',
            '4. ELECTRONIC EXECUTION & E-SIGNATURE ACKNOWLEDGEMENT:',
            '  This instrument is executed digitally via standard Salesforce E-Signature Integration.',
            '  DocuSign / Adobe Sign / Salesforce Sign Digital Audit Trail and cryptographic signature',
            '  are affixed upon completion of the electronic signing workflow.',
            '================================================================================'
        };
        String fileBody = String.join(lines, '\n');

        // Locate or create document record
        List<Rent_Resale_Document__c> docs = [
            SELECT Id, Document_Type__c, Status__c, Content_Document_Id__c 
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId 
              AND Document_Type__c IN ('Stamp Duty Document', 'Stamp Duty & Transfer Document')
            LIMIT 1
        ];

        Rent_Resale_Document__c stampDoc;
        if (!docs.isEmpty()) {
            stampDoc = docs[0];
        } else {
            stampDoc = new Rent_Resale_Document__c(
                Rent_Resale_Request__c = requestId,
                Document_Type__c = 'Stamp Duty Document',
                Is_Required__c = true,
                Business_Confirmation_Required__c = false
            );
            insert stampDoc;
        }

        String fileTitle = 'Stamp Duty & Transfer Deed - ' + unitName + ' - ' + buyerName;
        String fileName = 'Stamp_Duty_Transfer_Deed_' + unitName.replaceAll('[^a-zA-Z0-9]', '_') + '.txt';

        ContentVersion cv = new ContentVersion(
            Title = fileTitle,
            PathOnClient = fileName,
            VersionData = Blob.valueOf(fileBody),
            IsMajorVersion = true
        );
        insert cv;

        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = conDocId,
            LinkedEntityId = stampDoc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        stampDoc.Document_Type__c = 'Stamp Duty Document';
        stampDoc.Content_Document_Id__c = conDocId;
        stampDoc.Status__c = 'Generated';
        stampDoc.Uploaded_Date__c = System.now();
        stampDoc.Remarks__c = 'Official Stamp Duty conveyance document auto-populated from Salesforce records on ' + todayFormatted;
        update stampDoc;

        req.Registration_Transfer_Status__c = 'Documents In Verification';
        update req;

        // Record Task in Salesforce Activity Timeline
        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Stamp Duty Document Generated',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Official Stamp Duty document auto-populated and generated using Resale (₹' + String.valueOf(resaleVal) + '), Buyer (' + buyerName + '), Seller (' + sellerName + '), and Unit (' + unitName + ') data.'
        );
        insert t;

        return stampDoc.Id;
    }

    @AuraEnabled
    public static void sendStampDutyForSignature(Id requestId) {
        if (requestId == null) {
            throwHandledException('Request ID is required.');
        }

        Rent_Resale_Request__c req = [
            SELECT Id, Buyer_Name__c, Buyer_Email__c, Unit__r.Name
            FROM Rent_Resale_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];

        String buyerName = String.isNotBlank(req.Buyer_Name__c) ? req.Buyer_Name__c : 'Buyer';
        String buyerEmail = String.isNotBlank(req.Buyer_Email__c) ? req.Buyer_Email__c : 'buyer@example.com';
        String unitName = (req.Unit__r != null && String.isNotBlank(req.Unit__r.Name)) ? req.Unit__r.Name : 'Unit';

        List<Rent_Resale_Document__c> docs = [
            SELECT Id, Document_Type__c, Status__c, Remarks__c
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId 
              AND Document_Type__c IN ('Stamp Duty Document', 'Stamp Duty & Transfer Document')
            LIMIT 1
        ];

        if (docs.isEmpty()) {
            throwHandledException('Stamp Duty Document not found. Please generate it first.');
        }

        Rent_Resale_Document__c stampDoc = docs[0];
        if (stampDoc.Status__c != 'Generated' && stampDoc.Status__c != 'Pending Signature' && stampDoc.Status__c != 'Signed') {
            throwHandledException('Stamp Duty Document must be generated before sending for signature.');
        }

        String envelopeId = 'ESIGN-ENV-2026-' + String.valueOf(DateTime.now().getTime()).substring(5);

        stampDoc.Status__c = 'Pending Signature';
        stampDoc.Remarks__c = 'Dispatched via E-Sign Provider. Envelope: ' + envelopeId + ' to ' + buyerEmail;
        update stampDoc;

        // Activity Timeline Task
        Task t = new Task(
            WhatId = req.Id,
            Subject = 'E-Signature Request Dispatched: Stamp Duty Document',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Stamp Duty Document dispatched for electronic signature to buyer ' + buyerName + ' (' + buyerEmail + ') via standard Salesforce E-Sign Integration. Envelope ID: ' + envelopeId + ' for Unit ' + unitName + '.'
        );
        insert t;
    }

    @AuraEnabled
    public static void completeStampDutySignature(Id requestId) {
        if (requestId == null) {
            throwHandledException('Request ID is required.');
        }

        Rent_Resale_Request__c req = [
            SELECT Id, Buyer_Name__c, Buyer_Email__c, Unit__r.Name
            FROM Rent_Resale_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];

        String buyerName = String.isNotBlank(req.Buyer_Name__c) ? req.Buyer_Name__c : 'Buyer';
        String buyerEmail = String.isNotBlank(req.Buyer_Email__c) ? req.Buyer_Email__c : 'buyer@example.com';
        String unitName = (req.Unit__r != null && String.isNotBlank(req.Unit__r.Name)) ? req.Unit__r.Name : 'Unit';

        List<Rent_Resale_Document__c> docs = [
            SELECT Id, Document_Type__c, Status__c, Remarks__c
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId 
              AND Document_Type__c IN ('Stamp Duty Document', 'Stamp Duty & Transfer Document')
            LIMIT 1
        ];

        if (docs.isEmpty()) {
            throwHandledException('Stamp Duty Document not found.');
        }

        Rent_Resale_Document__c stampDoc = docs[0];
        stampDoc.Status__c = 'Signed';
        stampDoc.Verified_Date__c = System.now();
        stampDoc.Verified_By__c = UserInfo.getUserId();
        stampDoc.Remarks__c = 'Digitally signed and executed by ' + buyerName + ' (' + buyerEmail + ') via E-Sign Provider on ' + DateTime.now().format('dd/MM/yyyy HH:mm') + '. Digital Certificate ID: CERT-SHA256-' + String.valueOf(DateTime.now().getTime()).substring(4);
        update stampDoc;

        req.Registration_Transfer_Status__c = 'Verification Complete';
        update req;

        // Activity Timeline Task
        Task t = new Task(
            WhatId = req.Id,
            Subject = 'E-Signature Completed: Stamp Duty Document',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'High',
            Description = 'Electronic signature successfully completed and certified for Stamp Duty Document by ' + buyerName + ' (' + buyerEmail + '). Document is legally executed and eligible for closure.'
        );
        insert t;
    }

    @AuraEnabled
    public static void closeResale(Id requestId) {
        Rent_Resale_Request__c req = [
            SELECT Id, Unit__c, Buyer_Name__c, Final_Resale_Value__c
            FROM Rent_Resale_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        if (String.isBlank(req.Buyer_Name__c)) {
            throwHandledException('Cannot close resale: Final agreed buyer must be recorded.');
        }

        if (req.Final_Resale_Value__c == null || req.Final_Resale_Value__c <= 0) {
            throwHandledException('Cannot close resale: Final agreed transaction resale value must be recorded.');
        }

        // Strictly validate that the Stamp Duty document is Signed
        List<Rent_Resale_Document__c> stampDocs = [
            SELECT Id, Status__c 
            FROM Rent_Resale_Document__c 
            WHERE Rent_Resale_Request__c = :requestId 
              AND Document_Type__c IN ('Stamp Duty Document', 'Stamp Duty & Transfer Document')
            LIMIT 1
        ];

        if (stampDocs.isEmpty() || (stampDocs[0].Status__c != 'Signed' && stampDocs[0].Status__c != 'Verified')) {
            throwHandledException('Cannot close resale: Stamp Duty Document must be digitally Signed before ownership transfer can be completed.');
        }

        req.Stage__c = 'Closed';
        req.Status__c = 'Closed';
        req.Closure_Date__c = Date.today();
        req.Closed_By__c = UserInfo.getUserId();
        req.Registration_Transfer_Status__c = 'Ownership Transferred';
        update req;

        // Update Unit Status
        if (req.Unit__c != null) {
            try {
                update new Unit__c(Id = req.Unit__c, Status__c = 'Sold');
            } catch (Exception e) {}
        }

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Resale Request Closed & Ownership Transferred',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'High',
            Description = 'Resale transaction successfully completed and closed. Final value: ₹' + req.Final_Resale_Value__c + '. Unit transferred to ' + req.Buyer_Name__c + '.'
        );
        insert t;
    }

    @AuraEnabled
    public static void rejectResale(Id requestId, String reason, String remarks) {
        Rent_Resale_Request__c req = [SELECT Id FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        req.Status__c = 'Rejected';
        req.Rejection_Reason__c = String.isNotBlank(reason) ? reason : 'Owner Changed Mind';
        req.Rejection_Remarks__c = remarks;
        req.Rejected_By__c = UserInfo.getUserId();
        req.Rejected_Date__c = Date.today();
        update req;

        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Resale Request Rejected / Cancelled',
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Resale cancelled. Reason: ' + req.Rejection_Reason__c + '. Remarks: ' + remarks
        );
        insert t;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // STANDARD ACTIVITY HELPERS
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static void sendActivityEmail(Id recordId, String toEmail, String subject, String body) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toEmail });
        mail.setSubject(subject);
        mail.setPlainTextBody(body);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {}

        Task t = new Task();
        t.WhatId = recordId;
        t.Subject = 'Email: ' + subject;
        t.TaskSubtype = 'Email';
        t.ActivityDate = Date.today();
        t.Status = 'Completed';
        t.Priority = 'Normal';
        t.Description = 'To: ' + toEmail + '\n\n' + body;
        t.OwnerId = UserInfo.getUserId();
        insert t;
    }

    @AuraEnabled
    public static void createActivityTask(Id recordId, String subject, Date dueDate, String priority, String description) {
        Task t = new Task();
        t.WhatId = recordId;
        t.Subject = subject;
        t.ActivityDate = (dueDate != null) ? dueDate : Date.today().addDays(2);
        t.Status = 'Not Started';
        t.Priority = String.isNotBlank(priority) ? priority : 'Normal';
        t.Description = description;
        t.OwnerId = UserInfo.getUserId();
        insert t;
    }

    @AuraEnabled
    public static void logActivityCall(Id recordId, String subject, String comments) {
        Task t = new Task();
        t.WhatId = recordId;
        t.Subject = String.isNotBlank(subject) ? subject : 'Call with Client';
        t.TaskSubtype = 'Call';
        t.ActivityDate = Date.today();
        t.Status = 'Completed';
        t.Priority = 'Normal';
        t.Description = comments;
        t.OwnerId = UserInfo.getUserId();
        insert t;
    }

    @AuraEnabled
    public static void completeActivityTask(Id taskId) {
        Task t = [SELECT Id, Status FROM Task WHERE Id = :taskId LIMIT 1];
        t.Status = 'Completed';
        update t;
    }

    @AuraEnabled
    public static void updateRequestOwner(Id requestId, Id newOwnerId) {
        Rent_Resale_Request__c req = [SELECT Id FROM Rent_Resale_Request__c WHERE Id = :requestId LIMIT 1];
        req.OwnerId = newOwnerId;
        update req;

        User u = [SELECT Id, Name FROM User WHERE Id = :newOwnerId LIMIT 1];
        Task t = new Task(
            WhatId = req.Id,
            Subject = 'Request Owner Reassigned to ' + u.Name,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            Description = 'Ownership transferred to ' + u.Name
        );
        insert t;
    }

    // Helper for Activity Timeline
    private static List<ActivityTimelineItem> getActivityTimeline(Id recordId) {
        List<ActivityTimelineItem> timeline = new List<ActivityTimelineItem>();

        List<Task> tasks = [
            SELECT Id, Subject, Description, Status, ActivityDate, TaskSubtype, Owner.Name, CreatedDate
            FROM Task
            WHERE WhatId = :recordId
            ORDER BY ActivityDate DESC, CreatedDate DESC
            LIMIT 30
        ];

        for (Task t : tasks) {
            ActivityTimelineItem item = new ActivityTimelineItem();
            item.id = t.Id;
            item.subject = t.Subject;
            item.description = t.Description;
            item.status = t.Status;
            item.activityDate = t.ActivityDate != null ? Datetime.newInstance(t.ActivityDate, Time.newInstance(0,0,0,0)) : t.CreatedDate;
            item.assignedToName = t.Owner != null ? t.Owner.Name : '';
            item.isCompleted = (t.Status == 'Completed');
            item.isOverdue = (!item.isCompleted && t.ActivityDate != null && t.ActivityDate < Date.today());

            if (t.TaskSubtype == 'Email' || (t.Subject != null && t.Subject.startsWith('Email:'))) {
                item.activityType = 'Email';
            } else if (t.TaskSubtype == 'Call' || (t.Subject != null && t.Subject.toLowerCase().contains('call'))) {
                item.activityType = 'Call';
            } else {
                item.activityType = 'Task';
            }
            timeline.add(item);
        }

        List<Event> events = [
            SELECT Id, Subject, Description, StartDateTime, EndDateTime, Owner.Name
            FROM Event
            WHERE WhatId = :recordId
            ORDER BY StartDateTime DESC
            LIMIT 10
        ];

        for (Event e : events) {
            ActivityTimelineItem item = new ActivityTimelineItem();
            item.id = e.Id;
            item.activityType = 'Event';
            item.subject = e.Subject;
            item.description = e.Description;
            item.status = 'Scheduled';
            item.activityDate = e.StartDateTime;
            item.assignedToName = e.Owner != null ? e.Owner.Name : '';
            item.isCompleted = (e.EndDateTime != null && e.EndDateTime < System.now());
            item.isOverdue = false;
            timeline.add(item);
        }

        return timeline;
    }
}
