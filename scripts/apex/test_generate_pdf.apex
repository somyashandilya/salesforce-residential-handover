Inspection__c insp = [SELECT Id FROM Inspection__c WHERE Handover__r.Name = 'HO-0002' LIMIT 1];
Map<String, Object> res = HandoverWorkspaceController.generateInspectionReport(insp.Id);
System.debug('generateInspectionReport result: ' + res);
