Handover__c ho = [SELECT Id, Name, Stage__c, Status__c FROM Handover__c WHERE Name = 'HO-0004' LIMIT 1];
System.debug('STAGE 1 CURRENT: ' + ho.Stage__c + ' Status: ' + ho.Status__c);

// 1. Move to Stage 2: Start Inspection
Id inspId = HandoverWorkspaceController.startInspection(ho.Id, 'SafeHome Inspections Pvt Ltd', 'Third Party', 'lead@safehomeinspections.com');
Inspection__c insp = [SELECT Id, Name, Status__c, External_Token__c, Total_Items_Count__c FROM Inspection__c WHERE Id = :inspId];
System.debug('STAGE 2 INSPECTION CREATED: ' + insp.Name + ' Token: ' + insp.External_Token__c + ' Total Items: ' + insp.Total_Items_Count__c);

// Query Checklist items
List<Inspection_Checklist_Item__c> items = [SELECT Id, Name, Category__c, Result__c FROM Inspection_Checklist_Item__c WHERE Inspection__c = :inspId];
System.debug('CHECKLIST ITEMS GENERATED: ' + items.size());

// 2. Mark items Pass / Issue Found
Inspection_Checklist_Item__c item1 = items[0];
HandoverWorkspaceController.saveChecklistItem(item1.Id, 'Issue Found', 'Tile hairline crack in living room floor', 'Living Room (30%, 40%)');

// 3. Move to Stage 3: Raise Snag
Id snagId = HandoverWorkspaceController.raiseSnagWithCoords(
    ho.Id,
    inspId,
    item1.Id,
    'Civil & Finishes',
    'Living & Dining',
    'Living Room (30%, 40%)',
    'Tile hairline crack in living room floor',
    'Critical',
    true,
    30.5,
    40.2,
    'Apex Construction Services'
);
Snag__c snag = [SELECT Id, Name, Severity__c, Blocks_Handover__c, Status__c FROM Snag__c WHERE Id = :snagId];
System.debug('STAGE 3 SNAG CREATED: ' + snag.Name + ' Severity: ' + snag.Severity__c + ' Blocker: ' + snag.Blocks_Handover__c);

// Complete Inspection
HandoverWorkspaceController.completeInspection(inspId);

// 4. Test Rectification Lifecycle: Assign -> In Progress -> Resolved -> Closed
HandoverWorkspaceController.assignContractor(snagId, 'Apex Construction Services');
HandoverWorkspaceController.updateSnagStatus(snagId, 'Resolved', 'Tiles replaced and regrouted');
HandoverWorkspaceController.updateSnagStatus(snagId, 'Closed', 'Verified by handover lead');

// 5. Mark Handover Ready
HandoverWorkspaceController.markHandoverReady(ho.Id);
ho = [SELECT Id, Stage__c, Status__c FROM Handover__c WHERE Id = :ho.Id];
System.debug('STAGE 4 HANDOVER READY: ' + ho.Stage__c + ' Status: ' + ho.Status__c);

// 6. Schedule Appointment
HandoverWorkspaceController.scheduleAppointment(
    ho.Id,
    Date.newInstance(2026, 10, 20),
    '10:00 AM - 12:00 PM',
    'Tower B Lobby',
    'Please bring photo ID and Bank NOC',
    'Photo ID, Allotment Letter, Bank NOC',
    true
);
ho = [SELECT Id, Stage__c, Status__c, Appointment_Date__c FROM Handover__c WHERE Id = :ho.Id];
System.debug('APPOINTMENT SCHEDULED: ' + ho.Appointment_Date__c + ' Status: ' + ho.Status__c);

// 7. Complete Physical Handover Completion
HandoverWorkspaceController.completePhysicalHandover(
    ho.Id,
    11,
    4,
    'Original Possession Letter, Bank NOC, Keys, Manuals',
    'EL-904231 · 1,420 kWh',
    'WM-81204 · 84.5 kL',
    'GP-1204 · 12.0 m³',
    'Aditya Sharma',
    'Outstanding experience from inspection to key handover.',
    5
);

// 8. Verify Stage 5 Completed & Documents
ho = [SELECT Id, Stage__c, Status__c, Handover_Pack_Generated__c, Warranty_Start_Date__c, Warranty_End_Date__c FROM Handover__c WHERE Id = :ho.Id];
System.debug('STAGE 5 COMPLETED: ' + ho.Stage__c + ' Status: ' + ho.Status__c + ' Warranty End: ' + ho.Warranty_End_Date__c);

List<ContentDocumentLink> cdls = [SELECT Id, ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :ho.Id];
System.debug('DOCUMENTS ISSUED COUNT: ' + cdls.size());
for (ContentDocumentLink cdl : cdls) {
    System.debug('  - Document: ' + cdl.ContentDocument.Title);
}

// 9. Verify 22-Event Audit Trail
List<Handover_Event_Log__c> logs = [SELECT Id, Name, Event_Type__c, Channel__c, Timestamp__c FROM Handover_Event_Log__c WHERE Handover__c = :ho.Id ORDER BY Timestamp__c ASC];
System.debug('TOTAL AUDIT EVENT LOGS: ' + logs.size());
for (Handover_Event_Log__c l : logs) {
    System.debug('  * Log: [' + l.Channel__c + '] ' + l.Event_Type__c);
}
