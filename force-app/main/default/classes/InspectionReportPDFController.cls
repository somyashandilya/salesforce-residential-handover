/**
 * @description Controller for InspectionReportPDF Visualforce page.
 *              Generates a formal, executive-ready Residential Property Inspection Audit Report PDF.
 *              Supports lookup by Inspection__c ID or Handover__c ID.
 */
public with sharing class InspectionReportPDFController {
    public Inspection__c inspection { get; set; }
    public List<CategoryGroup> categoryGroups { get; set; }
    public List<Snag__c> snags { get; set; }
    public Integer totalItemsCount { get; set; }
    public Integer passedItemsCount { get; set; }
    public Integer issueItemsCount { get; set; }
    public Integer naItemsCount { get; set; }
    public Integer passPercentage { get; set; }
    public String generatedDateFormatted { get; set; }
    public String certifiedByName { get; set; }
    public Boolean hasInspection { get; set; }
    public Boolean hasSnags { get; set; }

    public class CategoryGroup {
        public String categoryName { get; set; }
        public List<ChecklistWrapper> items { get; set; }
        public Integer itemCount { get; set; }
        public Integer passCount { get; set; }
        public Integer issueCount { get; set; }
    }

    public class ChecklistWrapper {
        public String name { get; set; }
        public String location { get; set; }
        public String result { get; set; }
        public String comments { get; set; }
        public String resultBadgeClass { get; set; }
        public List<String> linkedSnagNames { get; set; }
        public Boolean hasLinkedSnags { get; set; }
    }

    public InspectionReportPDFController() {
        init();
    }

    private void init() {
        Id recordId = null;
        try {
            recordId = (Id) ApexPages.currentPage().getParameters().get('id');
        } catch (Exception e) {
            recordId = null;
        }

        if (recordId == null) {
            hasInspection = false;
            return;
        }

        String sobjectName = recordId.getSObjectType().getDescribe().getName();
        Id inspectionId = null;

        if (sobjectName == 'Inspection__c') {
            inspectionId = recordId;
        } else if (sobjectName == 'Handover__c') {
            List<Inspection__c> insps = [
                SELECT Id FROM Inspection__c
                WHERE Handover__c = :recordId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!insps.isEmpty()) {
                inspectionId = insps[0].Id;
            }
        }

        if (inspectionId == null) {
            hasInspection = false;
            return;
        }

        hasInspection = true;
        loadInspectionData(inspectionId);
    }

    private void loadInspectionData(Id inspectionId) {
        inspection = [
            SELECT Id, Name, Inspection_Date__c, Inspection_Type__c, Inspection_Round__c,
                   Inspector_Name__c, Inspector_Company__c, Inspector_Email__c,
                   Status__c, Overall_Result__c, Passed_Items_Count__c, Issue_Items_Count__c,
                   NA_Items_Count__c, Total_Items_Count__c, CreatedDate,
                   Handover__c, Handover__r.Name, Handover__r.Stage__c, Handover__r.Status__c,
                   Handover__r.Unit__r.Name, Handover__r.Property__r.Name, Handover__r.Tower__r.Name,
                   Handover__r.Customer__r.Name, Handover__r.Customer__r.Phone,
                   Handover__r.Booking__r.Name, Handover__r.Handover_Owner__r.Name,
                   Handover__r.Target_Handover_Date__c, Handover__r.Completed_Date_Time__c
            FROM Inspection__c
            WHERE Id = :inspectionId
            LIMIT 1
        ];

        List<Inspection_Checklist_Item__c> items = [
            SELECT Id, Name, Category__c, Location__c, Result__c, Comments__c,
                   (SELECT Id, Name, Severity__c, Status__c, Snag_Description__c FROM Snag_Checklist_Item__r)
            FROM Inspection_Checklist_Item__c
            WHERE Inspection__c = :inspectionId
            ORDER BY Category__c ASC, Name ASC
        ];

        snags = [
            SELECT Id, Name, Category__c, Location__c, Severity__c, Status__c,
                   Assigned_Contractor_Name__c, Responsible_Team__c, Snag_Description__c,
                   Resolution_Comments__c, Verification_Comments__c, Due_Date__c, Closed_Date__c
            FROM Snag__c
            WHERE Inspection__c = :inspectionId OR Handover__c = :inspection.Handover__c
            ORDER BY CreatedDate ASC
        ];
        hasSnags = !snags.isEmpty();

        // Count metrics
        totalItemsCount = items.size();
        passedItemsCount = 0;
        issueItemsCount = 0;
        naItemsCount = 0;

        Map<String, List<ChecklistWrapper>> groupMap = new Map<String, List<ChecklistWrapper>>();

        for (Inspection_Checklist_Item__c itm : items) {
            String res = String.isNotBlank(itm.Result__c) ? itm.Result__c : 'Pending';
            if (res == 'Pass') {
                passedItemsCount++;
            } else if (res == 'Issue Found' || res == 'Issue') {
                issueItemsCount++;
            } else if (res == 'N/A') {
                naItemsCount++;
            }

            String cat = String.isNotBlank(itm.Category__c) ? itm.Category__c : 'General';
            if (!groupMap.containsKey(cat)) {
                groupMap.put(cat, new List<ChecklistWrapper>());
            }

            ChecklistWrapper cw = new ChecklistWrapper();
            cw.name = itm.Name;
            cw.location = String.isNotBlank(itm.Location__c) ? itm.Location__c : 'General';
            cw.result = res;
            cw.comments = itm.Comments__c;
            cw.resultBadgeClass = res == 'Pass' ? 'badge-pass' : (res == 'Issue Found' || res == 'Issue') ? 'badge-issue' : 'badge-na';
            cw.linkedSnagNames = new List<String>();
            if (itm.Snag_Checklist_Item__r != null && !itm.Snag_Checklist_Item__r.isEmpty()) {
                for (Snag__c sn : itm.Snag_Checklist_Item__r) {
                    cw.linkedSnagNames.add(sn.Name + ' [' + sn.Severity__c + ']');
                }
            }
            cw.hasLinkedSnags = !cw.linkedSnagNames.isEmpty();
            groupMap.get(cat).add(cw);
        }

        categoryGroups = new List<CategoryGroup>();
        for (String cat : groupMap.keySet()) {
            CategoryGroup cg = new CategoryGroup();
            cg.categoryName = cat;
            cg.items = groupMap.get(cat);
            cg.itemCount = cg.items.size();
            cg.passCount = 0;
            cg.issueCount = 0;
            for (ChecklistWrapper w : cg.items) {
                if (w.result == 'Pass') cg.passCount++;
                else if (w.result == 'Issue Found' || w.result == 'Issue') cg.issueCount++;
            }
            categoryGroups.add(cg);
        }

        passPercentage = totalItemsCount > 0 ? Math.round(((Double) passedItemsCount / totalItemsCount) * 100) : 0;
        generatedDateFormatted = System.now().format('dd MMM yyyy, HH:mm');
        certifiedByName = UserInfo.getName();
    }
}
