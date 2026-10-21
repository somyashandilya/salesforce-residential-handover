public without sharing class BookingHandoverHandler {
    public static Boolean isExecuting = false;

    public static void initializeHandovers(Set<Id> bookingIds) {
        if (isExecuting || bookingIds == null || bookingIds.isEmpty()) return;
        isExecuting = true;
        try {

        // Check which bookings already have a Handover record and ensure they are linked
        Set<Id> existingBookingIds = new Set<Id>();
        List<Booking__c> bookingsToUpdate = new List<Booking__c>();
        for (Handover__c ho : [SELECT Id, Booking__c FROM Handover__c WHERE Booking__c IN :bookingIds]) {
            existingBookingIds.add(ho.Booking__c);
            bookingsToUpdate.add(new Booking__c(
                Id = ho.Booking__c,
                Handover__c = ho.Id
            ));
        }

        List<Booking__c> eligibleBookings = [
            SELECT Id, Name, Status__c, Account_Id__c, Account_Id__r.PersonContactId,
                   Unit_Id__c, Unit_Id__r.Tower__c, Unit_Id__r.Floor__c, Project__c
            FROM Booking__c
            WHERE Id IN :bookingIds
        ];

        List<Handover__c> handoversToInsert = new List<Handover__c>();
        for (Booking__c b : eligibleBookings) {
            if (!existingBookingIds.contains(b.Id)) {
                Handover__c ho = new Handover__c();
                ho.Booking__c = b.Id;
                ho.Customer__c = b.Account_Id__c;
                ho.Contact__c = (b.Account_Id__r != null && b.Account_Id__r.PersonContactId != null) 
                    ? b.Account_Id__r.PersonContactId 
                    : null;
                ho.Unit__c = b.Unit_Id__c;
                ho.Property__c = b.Project__c;
                ho.Tower__c = b.Unit_Id__r != null ? b.Unit_Id__r.Tower__c : null;
                ho.Floor__c = b.Unit_Id__r != null ? b.Unit_Id__r.Floor__c : null;
                ho.Stage__c = 'Readiness';
                ho.Status__c = 'Readiness In Progress';
                ho.Target_Handover_Date__c = Date.today().addDays(30);
                ho.Handover_Owner__c = UserInfo.getUserId();
                handoversToInsert.add(ho);
            }
        }

        if (!handoversToInsert.isEmpty()) {
            insert handoversToInsert;

            for (Handover__c ho : handoversToInsert) {
                if (ho.Booking__c != null) {
                    bookingsToUpdate.add(new Booking__c(
                        Id = ho.Booking__c,
                        Handover__c = ho.Id
                    ));
                }
            }

            // Create initial standard Salesforce Task for Handover Owner
            List<Task> initialTasks = new List<Task>();
            for (Handover__c ho : handoversToInsert) {
                Task t = new Task();
                t.WhatId = ho.Id;
                if (ho.Contact__c != null) {
                    t.WhoId = ho.Contact__c;
                }
                t.Subject = 'Initiate Handover Readiness Assessment';
                t.ActivityDate = Date.today().addDays(2);
                t.Status = 'Not Started';
                t.Priority = 'Normal';
                t.Description = 'Booking has reached Closed Won / Confirmed. Verify Financial clearance, OC status, and Unit readiness before starting inspection.';
                t.OwnerId = ho.Handover_Owner__c != null ? ho.Handover_Owner__c : UserInfo.getUserId();
                initialTasks.add(t);
            }
            insert initialTasks;
        }

        if (!bookingsToUpdate.isEmpty()) {
            // Deduplicate booking updates
            Map<Id, Booking__c> bMap = new Map<Id, Booking__c>();
            for (Booking__c b : bookingsToUpdate) {
                bMap.put(b.Id, b);
            }
            update bMap.values();
        }
        } finally {
            isExecuting = false;
        }
    }
}
