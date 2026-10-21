Handover__c ho = [SELECT Id, Name, Stage__c, Status__c FROM Handover__c WHERE Name = 'HO-0002' LIMIT 1];
System.debug('HO-0002 ID: ' + ho.Id + ' Stage: ' + ho.Stage__c + ' Status: ' + ho.Status__c);
HandoverWorkspaceController.FormalReportWrapper w = HandoverWorkspaceController.getHandoverInspectionReportSummary(ho.Id);
if (w != null) {
    System.debug('Inspection Report found! Inspection: ' + w.inspection.Name + ', Total Items: ' + w.totalCount + ', Passed: ' + w.passedCount + ', Issues: ' + w.issuesCount);
} else {
    System.debug('No inspection report found for HO-0002');
}
