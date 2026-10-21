/**
 * @description Secure External Inspection REST API.
 * Allows external third-party inspectors to access checklist and submit findings via secure token
 * without requiring any internal Salesforce login.
 */
@RestResource(urlMapping='/externalInspection/*')
global without sharing class ExternalInspectionService {

    global class InspectionViewDTO {
        public Boolean success;
        public String message;
        public String inspectionId;
        public String inspectionReference;
        public String projectName;
        public String towerName;
        public String unitName;
        public Date inspectionDate;
        public String inspectorName;
        public String inspectorCompany;
        public Boolean isLocked;
        public Boolean isExpired;
        public List<ChecklistItemDTO> checklistItems;
    }

    global class ChecklistItemDTO {
        public String itemId;
        public String name;
        public String category;
        public String result;
        public String locationPin;
        public String comments;
    }

    global class SubmissionPayload {
        public String token;
        public String inspectorName;
        public String inspectorCompany;
        public String overallComments;
        public List<ChecklistUpdateDTO> items;
    }

    global class ChecklistUpdateDTO {
        public String itemId;
        public String result;
        public String comments;
        public String locationPin;
        public String category;
        public String name;
    }

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String token = req.params.get('token');
        if (String.isBlank(token)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'success' => false,
                'message' => 'Token parameter is required'
            }));
            return;
        }

        List<Inspection__c> inspections = [
            SELECT Id, Name, Property__r.Name, Tower__r.Name, Unit__r.Name,
                   Inspection_Date__c, Inspector_Name__c, Inspector_Company__c,
                   Is_Locked__c, Token_Expiry__c, External_Token__c
            FROM Inspection__c
            WHERE External_Token__c = :token
            LIMIT 1
        ];

        if (inspections.isEmpty()) {
            res.statusCode = 404;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'success' => false,
                'message' => 'Invalid or expired inspection link'
            }));
            return;
        }

        Inspection__c insp = inspections[0];
        Boolean isExpired = (insp.Token_Expiry__c != null && insp.Token_Expiry__c < System.now());

        InspectionViewDTO dto = new InspectionViewDTO();
        dto.success = true;
        dto.inspectionId = insp.Id;
        dto.inspectionReference = insp.Name;
        dto.projectName = insp.Property__r.Name;
        dto.towerName = insp.Tower__r.Name;
        dto.unitName = insp.Unit__r.Name;
        dto.inspectionDate = insp.Inspection_Date__c;
        dto.inspectorName = insp.Inspector_Name__c;
        dto.inspectorCompany = insp.Inspector_Company__c;
        dto.isLocked = insp.Is_Locked__c;
        dto.isExpired = isExpired;
        dto.checklistItems = new List<ChecklistItemDTO>();

        List<Inspection_Checklist_Item__c> items = [
            SELECT Id, Name, Category__c, Result__c, Location_Pin__c, Comments__c
            FROM Inspection_Checklist_Item__c
            WHERE Inspection__c = :insp.Id
            ORDER BY Category__c, Name
        ];

        for (Inspection_Checklist_Item__c itm : items) {
            ChecklistItemDTO ci = new ChecklistItemDTO();
            ci.itemId = itm.Id;
            ci.name = itm.Name;
            ci.category = itm.Category__c;
            ci.result = itm.Result__c;
            ci.locationPin = itm.Location_Pin__c;
            ci.comments = itm.Comments__c;
            dto.checklistItems.add(ci);
        }

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(dto));
    }

    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String body = req.requestBody.toString();
        SubmissionPayload payload = (SubmissionPayload)JSON.deserialize(body, SubmissionPayload.class);

        if (payload == null || String.isBlank(payload.token)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'success' => false,
                'message' => 'Token and submission data are required'
            }));
            return;
        }

        List<Inspection__c> inspections = [
            SELECT Id, Name, Handover__c, Handover__r.Handover_Owner__c, Handover__r.Unit__r.Name,
                   Is_Locked__c, Token_Expiry__c, External_Token__c,
                   Inspector_Name__c, Inspector_Company__c,
                   Passed_Items_Count__c, Issue_Items_Count__c, NA_Items_Count__c
            FROM Inspection__c
            WHERE External_Token__c = :payload.token
            LIMIT 1
        ];

        if (inspections.isEmpty()) {
            res.statusCode = 404;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'success' => false, 'message' => 'Inspection record not found' }));
            return;
        }

        Inspection__c insp = inspections[0];
        if (insp.Is_Locked__c) {
            res.statusCode = 403;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'success' => false, 'message' => 'This inspection form has already been submitted and is locked.' }));
            return;
        }
        if (insp.Token_Expiry__c != null && insp.Token_Expiry__c < System.now()) {
            res.statusCode = 403;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'success' => false, 'message' => 'This inspection link has expired.' }));
            return;
        }

        Integer passCount = 0;
        Integer issueCount = 0;
        Integer naCount = 0;

        List<Inspection_Checklist_Item__c> updates = new List<Inspection_Checklist_Item__c>();
        List<Snag__c> snagsToCreate = new List<Snag__c>();

        if (payload.items != null) {
            for (ChecklistUpdateDTO ci : payload.items) {
                Inspection_Checklist_Item__c itm = new Inspection_Checklist_Item__c(
                    Id = ci.itemId,
                    Result__c = ci.result,
                    Comments__c = ci.comments,
                    Location_Pin__c = ci.locationPin
                );

                if (ci.result == 'Pass') {
                    passCount++;
                } else if (ci.result == 'Issue Found') {
                    issueCount++;
                    itm.Has_Snag_Raised__c = true;
                    // Auto-raise snag
                    snagsToCreate.add(new Snag__c(
                        Handover__c = insp.Handover__c,
                        Inspection__c = insp.Id,
                        Checklist_Item__c = ci.itemId,
                        Category__c = ci.category,
                        Snag_Description__c = String.isNotBlank(ci.comments) ? ci.comments : (ci.name + ' - Defect identified in external inspection'),
                        Severity__c = 'Major',
                        Status__c = 'Assigned',
                        Due_Date__c = System.today().addDays(4),
                        Assigned_Contractor_Name__c = 'External Findings Resolution Team',
                        Location_Pin__c = ci.locationPin,
                        Blocks_Handover__c = true
                    ));
                } else if (ci.result == 'N/A') {
                    naCount++;
                }
                updates.add(itm);
            }
            update updates;
        }

        if (!snagsToCreate.isEmpty()) {
            insert snagsToCreate;
        }

        // Lock inspection & update stats
        insp.Status__c = 'Completed';
        insp.Overall_Result__c = (issueCount > 0) ? 'Issues Found' : 'Passed';
        insp.Is_Locked__c = true;
        insp.Submitted_Date_Time__c = System.now();
        insp.Customer_Comments__c = payload.overallComments;
        insp.Passed_Items_Count__c = passCount;
        insp.Issue_Items_Count__c = issueCount;
        insp.NA_Items_Count__c = naCount;
        if (String.isNotBlank(payload.inspectorName)) insp.Inspector_Name__c = payload.inspectorName;
        if (String.isNotBlank(payload.inspectorCompany)) insp.Inspector_Company__c = payload.inspectorCompany;
        update insp;

        // Move Handover to Resolution
        Handover__c ho = new Handover__c(
            Id = insp.Handover__c,
            Stage__c = 'Resolution',
            Status__c = 'Snags In Resolution'
        );
        update ho;

        // Fire Event 6 notification
        HandoverNotificationEngine.event6_ExternalInspectionSubmitted(
            [SELECT Id, Unit__r.Name, Handover_Owner__c FROM Handover__c WHERE Id = :insp.Handover__c LIMIT 1],
            insp
        );

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => true,
            'message' => 'Inspection successfully submitted and locked.',
            'passedCount' => passCount,
            'issuesFound' => issueCount,
            'naCount' => naCount
        }));
    }
}
