// 1. Project
Property__c proj;
List<Property__c> existingProj = [SELECT Id, Name FROM Property__c WHERE Name = 'Varthur Vista' LIMIT 1];
if (!existingProj.isEmpty()) {
    proj = existingProj[0];
} else {
    proj = new Property__c(Name = 'Varthur Vista');
    insert proj;
}

// 2. Tower
Tower__c tower;
List<Tower__c> existingTower = [SELECT Id, Name FROM Tower__c WHERE Name = 'Tower B' AND Property__c = :proj.Id LIMIT 1];
if (!existingTower.isEmpty()) {
    tower = existingTower[0];
} else {
    tower = new Tower__c(Name = 'Tower B', Property__c = proj.Id);
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
} else {
    unit = new Unit__c(
        Name = '1204',
        Property__c = proj.Id,
        Tower__c = tower.Id,
        Floor__c = floor.Id,
        Carpet_Area__c = 1450,
        BHK_Configuration__c = '3 BHK Canopy',
        Status__c = 'Booked'
    );
    insert unit;
}

// 5. Customer (Person Account)
Account cust;
List<Account> existingCust = [SELECT Id, Name, PersonEmail FROM Account WHERE LastName = 'Sharma' AND FirstName = 'Aditya' LIMIT 1];
if (!existingCust.isEmpty()) {
    cust = existingCust[0];
} else {
    Id accRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().containsKey('PersonAccount')
        ? Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId()
        : null;
    
    cust = new Account(
        RecordTypeId = accRtId,
        FirstName = 'Aditya',
        LastName = 'Sharma',
        PersonEmail = 'aditya.sharma@example.com',
        Phone = '+91 98765 43210'
    );
    insert cust;
}

// 5b. Opportunity
Opportunity opp;
List<Opportunity> existingOpp = [SELECT Id FROM Opportunity WHERE Name = 'Aditya Sharma - Tower B 1204' LIMIT 1];
if (!existingOpp.isEmpty()) {
    opp = existingOpp[0];
} else {
    opp = new Opportunity(
        Name = 'Aditya Sharma - Tower B 1204',
        AccountId = cust.Id,
        StageName = 'Prospecting',
        CloseDate = System.today()
    );
    insert opp;
}

// 6. Booking
Booking__c booking;
List<Booking__c> existingBooking = [SELECT Id FROM Booking__c WHERE Unit_Id__c = :unit.Id LIMIT 1];
if (!existingBooking.isEmpty()) {
    booking = existingBooking[0];
} else {
    booking = new Booking__c(
        Project__c = proj.Id,
        Unit_Id__c = unit.Id,
        Account_Id__c = cust.Id,
        Opportunity_Id__c = opp.Id,
        Status__c = 'Confirmed',
        Is_Token_Recieved__c = true,
        Allotment_Shared__c = true,
        Token_Amount__c = 500000,
        Total_Principal_Outstanding__c = 0
    );
    insert booking;
}

// 7. Master Handover HO-1204
Handover__c ho;
List<Handover__c> existingHo = [SELECT Id, Name FROM Handover__c WHERE Unit__c = :unit.Id LIMIT 1];
if (!existingHo.isEmpty()) {
    ho = existingHo[0];
    System.debug('EXISTING_HANDOVER_FOUND: ' + ho.Id + ' Name: ' + ho.Name);
} else {
    ho = new Handover__c(
        Property__c = proj.Id,
        Tower__c = tower.Id,
        Floor__c = floor.Id,
        Unit__c = unit.Id,
        Customer__c = cust.Id,
        Booking__c = booking.Id,
        Handover_Owner__c = UserInfo.getUserId(),
        Stage__c = 'Readiness',
        Status__c = 'Possession Ready',
        Target_Handover_Date__c = Date.newInstance(2026, 10, 20),
        Possession_Readiness__c = 'Ready',
        Project_Readiness__c = 'Ready',
        Unit_Readiness__c = 'Ready',
        OC_Clearance__c = 'Received',
        Common_Area_Blocker__c = 'Lift certification pending for Tower B · does not stop inspection',
        Finance_Status__c = 'Finance Cleared',
        Registration_Status__c = 'Sale Deed Registered',
        Customer_Instructions__c = 'Please bring photo ID for all owners, the allotment letter, and Bank NOC. Handover lead will meet you at the Tower B lobby on arrival.',
        Required_Documents__c = 'Photo ID, Allotment Letter, Key Receipt copy, Bank NOC',
        Appointment_Location__c = 'Tower B Lobby'
    );
    insert ho;

    unit.Current_Handover__c = ho.Id;
    unit.Possession_Readiness_Status__c = 'Ready';
    unit.Possession_Ready_Date__c = System.today();
    update unit;

    // Fire Initial Event Logs
    HandoverNotificationEngine.event1_UnitPossessionReady(ho, 'Construction Completion Audit');
    HandoverNotificationEngine.event2_OwnerAssigned(ho, [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1]);

    System.debug('NEW_HANDOVER_CREATED: ' + ho.Id);
}
