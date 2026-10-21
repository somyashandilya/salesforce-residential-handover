trigger InspectionTrigger on Inspection__c (after insert, after update, after delete, after undelete) {
    Set<Id> handoverIds = new Set<Id>();

    if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
        for (Inspection__c insp : Trigger.new) {
            if (Trigger.isUpdate && Trigger.oldMap != null) {
                Inspection__c oldInsp = Trigger.oldMap.get(insp.Id);
                if (oldInsp != null && oldInsp.Status__c == insp.Status__c && oldInsp.Handover__c == insp.Handover__c) {
                    continue; // Skip if neither Status__c nor Handover__c changed
                }
                if (oldInsp != null && oldInsp.Handover__c != null && oldInsp.Handover__c != insp.Handover__c) {
                    handoverIds.add(oldInsp.Handover__c);
                }
            }
            if (insp.Handover__c != null) {
                handoverIds.add(insp.Handover__c);
            }
        }
    }

    if (Trigger.isDelete) {
        for (Inspection__c insp : Trigger.old) {
            if (insp.Handover__c != null) {
                handoverIds.add(insp.Handover__c);
            }
        }
    }

    if (!handoverIds.isEmpty()) {
        List<Handover__c> handoversToUpdate = new List<Handover__c>();
        Map<Id, List<Inspection__c>> inspsByHandover = new Map<Id, List<Inspection__c>>();
        for (Id hId : handoverIds) {
            inspsByHandover.put(hId, new List<Inspection__c>());
        }

        for (Inspection__c insp : [
            SELECT Id, Handover__c, Status__c 
            FROM Inspection__c 
            WHERE Handover__c IN :handoverIds
        ]) {
            inspsByHandover.get(insp.Handover__c).add(insp);
        }

        for (Handover__c ho : [
            SELECT Id, Inspection_Status__c 
            FROM Handover__c 
            WHERE Id IN :handoverIds
        ]) {
            List<Inspection__c> inspList = inspsByHandover.get(ho.Id);
            String derivedStatus = 'Not Started';
            Boolean hasCompleted = false;
            Boolean hasInProgress = false;

            if (inspList != null && !inspList.isEmpty()) {
                for (Inspection__c insp : inspList) {
                    if (insp.Status__c == 'Completed') {
                        hasCompleted = true;
                    } else if (insp.Status__c == 'In Progress' || insp.Status__c == 'Submitted') {
                        hasInProgress = true;
                    }
                }
                if (hasCompleted) {
                    derivedStatus = 'Completed';
                } else if (hasInProgress) {
                    derivedStatus = 'In Progress';
                }
            }

            if (ho.Inspection_Status__c != derivedStatus) {
                ho.Inspection_Status__c = derivedStatus;
                handoversToUpdate.add(ho);
            }
        }

        if (!handoversToUpdate.isEmpty()) {
            update handoversToUpdate;
        }
    }
}
