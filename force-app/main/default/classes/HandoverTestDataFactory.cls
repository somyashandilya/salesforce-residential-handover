/**
 * @description Test Data Factory for the Residential Handover Module.
 * Provisions Project, Tower, Floor, Unit, Customer, Booking, and Handover record matching real metadata.
 */
@isTest
public without sharing class HandoverTestDataFactory {

    public static Handover__c createHandoverTestData() {
        // 1. Project
        Property__c proj;
        List<Property__c> existingProj = [SELECT Id, Name FROM Property__c WHERE Name = 'Varthur Vista' LIMIT 1];
        if (!existingProj.isEmpty()) {
            proj = existingProj[0];
        } else {
            proj = new Property__c(Name = 'Varthur Vista', OC_Received__c = true);
            insert proj;
        }

        // 2. Tower
        Tower__c tower;
        List<Tower__c> existingTower = [SELECT Id, Name FROM Tower__c WHERE Name = 'Tower B' AND Property__c = :proj.Id LIMIT 1];
        if (!existingTower.isEmpty()) {
            tower = existingTower[0];
            tower.OC_Received__c = true;
            update tower;
        } else {
            tower = new Tower__c(Name = 'Tower B', Property__c = proj.Id, OC_Received__c = true);
            insert tower;
        }

        // 3. Floor
        Floor__c floor;
        List<Floor__c> existingFloor = [SELECT Id, Name FROM Floor__c WHERE Name = '12th' AND Property__c = :proj.Id LIMIT 1];
        if (!existingFloor.isEmpty()) {
            floor = existingFloor[0];
        } else {
            floor = new Floor__c(Name = '12th', Tower__c = tower.Id, Property__c = proj.Id);
            insert floor;
        }

        // 4. Unit 1204
        Unit__c unit;
        List<Unit__c> existingUnit = [SELECT Id, Name FROM Unit__c WHERE Name = '1204' AND Tower__c = :tower.Id LIMIT 1];
        if (!existingUnit.isEmpty()) {
            unit = existingUnit[0];
            unit.Possession_Readiness_Status__c = 'Ready';
            update unit;
        } else {
            unit = new Unit__c(
                Name = '1204',
                Property__c = proj.Id,
                Tower__c = tower.Id,
                Floor__c = floor.Id,
                Carpet_Area__c = 1450,
                BHK_Configuration__c = '3 BHK Canopy',
                Status__c = 'Booked',
                Possession_Readiness_Status__c = 'Ready'
            );
            insert unit;
        }

        // 5. Customer (Person Account)
        Id accRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().containsKey('PersonAccount')
            ? Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId()
            : null;
        
        Account cust = new Account(
            RecordTypeId = accRtId,
            LastName = 'Test Customer ' + Crypto.getRandomInteger(),
            PersonEmail = 'customer@testresidential.com',
            Phone = '+91 98765 43210'
        );
        insert cust;

        // Query person contact id
        cust = [SELECT Id, Name, PersonEmail, Phone, PersonContactId FROM Account WHERE Id = :cust.Id];

        // 5b. Opportunity (Required by Booking)
        Opportunity opp = new Opportunity(
            Name = 'Handover Test Opportunity',
            AccountId = cust.Id,
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(30)
        );
        insert opp;

        // 6. Booking
        Booking__c booking = new Booking__c(
            Project__c = proj.Id,
            Unit_Id__c = unit.Id,
            Account_Id__c = cust.Id,
            Opportunity_Id__c = opp.Id,
            Status__c = 'Confirmed',
            Is_Token_Recieved__c = true,
            Allotment_Shared__c = true,
            Token_Amount__c = 100000
        );
        insert booking;

        // 7. Master Handover (check if created by BookingHandoverTrigger)
        List<Handover__c> hoList = [SELECT Id, Booking__c FROM Handover__c WHERE Booking__c = :booking.Id LIMIT 1];
        Handover__c ho;
        if (!hoList.isEmpty()) {
            ho = hoList[0];
            ho.Target_Handover_Date__c = Date.newInstance(2026, 10, 20);
            ho.Customer_Instructions__c = 'Please bring photo ID for all owners, the allotment letter, and Bank NOC. Handover lead will meet you on arrival.';
            ho.Appointment_Location__c = 'Tower B Lobby';
            update ho;
        } else {
            ho = new Handover__c(
                Property__c = proj.Id,
                Tower__c = tower.Id,
                Floor__c = floor.Id,
                Unit__c = unit.Id,
                Customer__c = cust.Id,
                Contact__c = cust.PersonContactId,
                Booking__c = booking.Id,
                Handover_Owner__c = UserInfo.getUserId(),
                Stage__c = 'Readiness',
                Status__c = 'Readiness In Progress',
                Target_Handover_Date__c = Date.newInstance(2026, 10, 20),
                Customer_Instructions__c = 'Please bring photo ID for all owners, the allotment letter, and Bank NOC. Handover lead will meet you on arrival.',
                Appointment_Location__c = 'Tower B Lobby'
            );
            insert ho;
        }

        unit.Current_Handover__c = ho.Id;
        update unit;

        return ho;
    }
}
