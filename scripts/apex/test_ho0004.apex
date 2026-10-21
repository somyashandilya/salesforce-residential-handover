Handover__c ho = [
    SELECT Id, Name, Stage__c, Status__c, Unit__c, Property__c, Tower__c, Floor__c, Customer__c, Contact__c, Handover_Owner__c, Booking__c
    FROM Handover__c
    WHERE Name = 'HO-0004'
    LIMIT 1
];
HandoverWorkspaceController.HandoverContextWrapper ctx = HandoverWorkspaceController.getHandoverContext(ho.Id);
System.debug('HO-0004 Stage: ' + ctx.handover.Stage__c + ' Status: ' + ctx.handover.Status__c);
System.debug('Readiness canStartInspection: ' + ctx.readiness.canStartInspection);
System.debug('Readiness blockingReason: ' + ctx.readiness.blockingReason);
System.debug('Current Inspection: ' + (ctx.currentInspection != null ? ctx.currentInspection.Name + ' status: ' + ctx.currentInspection.Status__c : 'NULL'));
