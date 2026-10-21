/**
 * @description Comprehensive test suite for Handover Module rebuild.
 */
@isTest
private class HandoverWorkspaceControllerTest {

    @isTest
    static void testBookingTriggerAndHandoverInitialization() {
        Handover__c ho = HandoverTestDataFactory.createHandoverTestData();
        System.assertNotEquals(null, ho.Id, 'Handover record should be created');

        // Test Booking Handover Handler directly
        Set<Id> bIds = new Set<Id>{ ho.Booking__c };
        BookingHandoverHandler.initializeHandovers(bIds);
        // Should not duplicate since ho already exists for booking
        List<Handover__c> hoList = [SELECT Id FROM Handover__c WHERE Booking__c = :ho.Booking__c];
        System.assertEquals(1, hoList.size());
    }

    @isTest
    static void testHandoverWorkspaceLifecycle() {
        Handover__c ho = HandoverTestDataFactory.createHandoverTestData();

        // 1. Get Context
        HandoverWorkspaceController.HandoverContextWrapper ctx = HandoverWorkspaceController.getHandoverContext(ho.Id);
        System.assertNotEquals(null, ctx);
        System.assertEquals('1204', ctx.unitSummary.unitName);
        System.assertNotEquals(null, ctx.contactSummary);
        System.assertEquals(true, ctx.readiness.bookingClosedWon);
        System.assertEquals(true, ctx.readiness.paymentCleared);
        System.assertEquals(true, ctx.readiness.ocReceived);
        System.assertEquals(true, ctx.readiness.unitReady);
        System.assertEquals(true, ctx.readiness.canStartInspection);
        System.assertNotEquals(null, ctx.readiness.approvalStatus);
        System.assertNotEquals(null, ctx.readiness.paymentDetails);
        System.assertNotEquals(null, ctx.readiness.ocDetails);
        System.assertNotEquals(null, ctx.readiness.possessionReadyDate);
        System.assertNotEquals(null, ctx.stageSummary);
        System.assertEquals('Completed', ctx.stageSummary.readinessStatus);

        // 2. Update Target Date
        HandoverWorkspaceController.updateTargetDate(ho.Id, Date.today().addDays(45));
        Handover__c hoUpdated = [SELECT Target_Handover_Date__c FROM Handover__c WHERE Id = :ho.Id];
        System.assertEquals(Date.today().addDays(45), hoUpdated.Target_Handover_Date__c);

        // 2b. Test Handover Owner Update & Search Users
        List<User> foundUsers = HandoverWorkspaceController.searchUsers(UserInfo.getLastName());
        System.assert(!foundUsers.isEmpty(), 'Active user should be found');
        HandoverWorkspaceController.updateHandoverOwner(ho.Id, UserInfo.getUserId());
        Handover__c hoOwnerCheck = [SELECT Handover_Owner__c FROM Handover__c WHERE Id = :ho.Id];
        System.assertEquals(UserInfo.getUserId(), hoOwnerCheck.Handover_Owner__c);

        // 3. Start Inspection (Internal)
        HandoverWorkspaceController.startInspection(ho.Id, 'Internal', 'John Inspector', 'Quality Corp', 'inspector@example.com');
        Inspection__c insp = [SELECT Id, External_Token__c FROM Inspection__c WHERE Handover__c = :ho.Id LIMIT 1];
        System.assertNotEquals(null, insp);

        // 3b. Test Add & Delete Checklist Item
        Id newItemId = HandoverWorkspaceController.addChecklistItem(insp.Id, 'Custom Inspection Check', 'Plumbing', 'Kitchen');
        System.assertNotEquals(null, newItemId);
        HandoverWorkspaceController.deleteChecklistItem(newItemId);

        // 4. Update Checklist Item & Raise Snag
        List<Inspection_Checklist_Item__c> items = [SELECT Id, Name FROM Inspection_Checklist_Item__c WHERE Inspection__c = :insp.Id];
        System.assert(!items.isEmpty(), 'Checklist items should be seeded');
        HandoverWorkspaceController.updateChecklistItem(items[0].Id, 'Issue Found', 'Living & Dining', 'Crack on wall plaster');

        // Verify Snag was raised
        List<Snag__c> snags = [SELECT Id, Name, Status__c, Location__c FROM Snag__c WHERE Handover__c = :ho.Id];
        System.assert(!snags.isEmpty());

        // 5. Raise Manual Snag
        HandoverWorkspaceController.raiseManualSnag(ho.Id, 'Balcony door handle loose', 'Doors & Windows', 'Balcony', 'Minor', 'SafeBuild', Date.today().addDays(5), null);
        if (items.size() > 2) {
            HandoverWorkspaceController.updateChecklistItemStatus(items[1].Id, 'Pass', '');
            HandoverWorkspaceController.updateChecklistItemStatus(items[2].Id, 'N/A', '');
            HandoverWorkspaceController.raiseManualSnag(ho.Id, 'Item defect', 'Finishes', 'Master Bedroom', 'Major', 'SafeBuild', Date.today().addDays(3), items[0].Id);
        }

        // 5b. Verify Inspection Report is gated while In Progress
        HandoverWorkspaceController.FormalReportWrapper reportSummProg = HandoverWorkspaceController.getHandoverInspectionReportSummary(ho.Id);
        System.assertEquals(null, reportSummProg, 'Report summary should be null while In Progress');

        // 6. Update Snag Status & Test Verification
        Id snagId = snags[0].Id;
        HandoverWorkspaceController.assignSnagOwner(snagId, UserInfo.getUserId(), 'John Owner', 'Assigned for repairs');
        Snag__c sAssigned = [SELECT Status__c, Assigned_Contractor_Name__c FROM Snag__c WHERE Id = :snagId];
        System.assertEquals('Assigned', sAssigned.Status__c);
        HandoverWorkspaceController.updateSnagStatus(snagId, 'In Progress', 'Working on snag');
        HandoverWorkspaceController.submitSnagForVerification(snagId, 'https://example.com/evidence.jpg', 'Repairs completed');
        Snag__c sSubmitted = [SELECT Status__c, Evidence_URL__c FROM Snag__c WHERE Id = :snagId];
        System.assertEquals('Verification', sSubmitted.Status__c);
        HandoverWorkspaceController.verifySnag(snagId, false, 'Reject - rework required');
        Snag__c sReopened = [SELECT Status__c, Reopen_Count__c, Rejection_Reason__c FROM Snag__c WHERE Id = :snagId];
        System.assertEquals('In Progress', sReopened.Status__c);
        System.assert(sReopened.Reopen_Count__c >= 1);
        System.assertEquals('Reject - rework required', sReopened.Rejection_Reason__c);
        HandoverWorkspaceController.verifySnag(snagId, true, 'Approved & closed');
        Snag__c sClosed = [SELECT Status__c FROM Snag__c WHERE Id = :snagId];
        System.assertEquals('Closed', sClosed.Status__c);

        // Verify completing inspection with unresolved items throws exception
        Boolean threwUnresolved = false;
        try {
            HandoverWorkspaceController.completeInspection(insp.Id);
        } catch (AuraHandledException ahe) {
            threwUnresolved = true;
        }
        System.assertEquals(true, threwUnresolved, 'Should throw error when checklist items are pending');

        // Resolve all remaining checklist items in bulk
        List<Inspection_Checklist_Item__c> toResolve = new List<Inspection_Checklist_Item__c>();
        for (Integer i = 3; i < items.size(); i++) {
            toResolve.add(new Inspection_Checklist_Item__c(Id = items[i].Id, Result__c = 'Pass'));
        }
        update toResolve;

        // Close any remaining snags so appointment gate passes
        List<Snag__c> remainingSnags = [SELECT Id FROM Snag__c WHERE Handover__c = :ho.Id AND Status__c != 'Closed'];
        for (Snag__c rs : remainingSnags) {
            HandoverWorkspaceController.verifySnag(rs.Id, true, 'Auto approved in test');
        }

        Test.startTest();

        // 7. Complete Inspection
        HandoverWorkspaceController.completeInspection(insp.Id);

        // 7b. Generate Inspection Report (Allowed now that inspection is Completed)
        Map<String, Object> reportResult = HandoverWorkspaceController.generateInspectionReport(insp.Id);
        System.assertNotEquals(null, reportResult.get('contentVersionId'));
        System.assertNotEquals(null, reportResult.get('downloadUrl'));
        HandoverWorkspaceController.FormalReportWrapper reportSumm = HandoverWorkspaceController.getHandoverInspectionReportSummary(ho.Id);
        System.assertNotEquals(null, reportSumm);

        // 8. Schedule Appointment
        HandoverWorkspaceController.scheduleAppointment(ho.Id, Date.today().addDays(7), '10:30 AM', '12:00 PM', 'Tower B Lobby', 'Bring ID');
        Handover__c hoSched = [SELECT Customer_Notification_Sent__c, Status__c FROM Handover__c WHERE Id = :ho.Id];
        System.assertEquals(true, hoSched.Customer_Notification_Sent__c);
        System.assertEquals('Appointment Scheduled', hoSched.Status__c);

        // 9. Reschedule Appointment
        HandoverWorkspaceController.rescheduleAppointment(ho.Id, Date.today().addDays(10), '11:00 AM', '12:30 PM', 'Tower B Reception');
        Handover__c hoResched = [SELECT Customer_Notification_Sent__c, Rescheduled_Count__c, Appointment_Location__c FROM Handover__c WHERE Id = :ho.Id];
        System.assertEquals(true, hoResched.Customer_Notification_Sent__c);
        System.assertEquals(1, hoResched.Rescheduled_Count__c);
        System.assertEquals('Tower B Reception', hoResched.Appointment_Location__c);

        // 10. Complete Physical Handover
        HandoverWorkspaceController.completePhysicalHandover(
            ho.Id, 3, 2, true,
            'EL-1204', 'WM-1204', 'GP-1204',
            true, 5, 'Exceptional experience'
        );

        Handover__c hoCompleted = [SELECT Stage__c, Status__c, Keys_Sets_Count__c, Feedback_Rating__c, Unit__c FROM Handover__c WHERE Id = :ho.Id];
        System.assertEquals('Completed', hoCompleted.Stage__c);
        System.assertEquals(3, hoCompleted.Keys_Sets_Count__c);
        System.assertEquals(5, hoCompleted.Feedback_Rating__c);

        // Verify Unit status was updated to Sold and Handed Over
        Unit__c unitCheck = [SELECT Status__c, Possession_Readiness_Status__c FROM Unit__c WHERE Id = :hoCompleted.Unit__c];
        System.assertEquals('Sold', unitCheck.Status__c);
        System.assertEquals('Handed Over', unitCheck.Possession_Readiness_Status__c);

        // 11. Test Standard Activity Logging
        HandoverWorkspaceController.logActivityTask(ho.Id, 'Follow-up Call', Date.today().addDays(1), 'Normal', 'Customer outreach');
        HandoverWorkspaceController.createActivityTask(ho.Id, 'Schedule Key Handover', Date.today().addDays(2), 'High', 'Key preparation');
        HandoverWorkspaceController.logActivityCall(ho.Id, 'Spoke with customer', 'Customer confirmed arrival time.');
        HandoverWorkspaceController.sendActivityEmail(ho.Id, 'test@example.com', 'Welcome Home Update', 'We are preparing your unit.');
        
        List<Task> loggedTasks = [SELECT Id, Subject, TaskSubtype FROM Task WHERE WhatId = :ho.Id];
        System.assert(loggedTasks.size() >= 4, 'Multiple tasks should be logged');
        HandoverWorkspaceController.completeActivityTask(loggedTasks[0].Id);

        // 12. Test Compact Handover Completion & Post Sale Requests
        HandoverWorkspaceController.completeHandoverCompact(ho.Id, true, true, true, 'All keys and docs signed.');
        HandoverWorkspaceController.createPostSaleRequest(ho.Id, 'Rental');
        HandoverWorkspaceController.createPostSaleRequest(ho.Id, 'Resale');

        // 13. Test submitExternalInspection method
        List<Map<String, String>> testItems = new List<Map<String, String>>();
        for (Inspection_Checklist_Item__c itm : [SELECT Id, Name, Category__c FROM Inspection_Checklist_Item__c WHERE Inspection__c = :insp.Id LIMIT 2]) {
            testItems.add(new Map<String, String>{
                'itemId' => itm.Id,
                'result' => 'Pass',
                'comments' => 'Verified ok',
                'locationPin' => 'Living',
                'category' => itm.Category__c,
                'name' => itm.Name
            });
        }
        // Unlock insp for test call
        insp.Is_Locked__c = false;
        update insp;
        Map<String, Object> extRes = HandoverWorkspaceController.submitExternalInspection(
            insp.External_Token__c, 'Auditor Test', 'QA Corp', 'All fine', JSON.serialize(testItems)
        );
        System.assertEquals(true, extRes.get('success'));

        Test.stopTest();
    }

    @isTest
    static void testExternalInspectionService() {
        Handover__c ho = HandoverTestDataFactory.createHandoverTestData();
        HandoverWorkspaceController.startInspection(ho.Id, 'Third Party', 'Inspector Alex', 'Audit Pvt Ltd', 'alex@auditor.com');
        Inspection__c insp = [SELECT Id, External_Token__c FROM Inspection__c WHERE Handover__c = :ho.Id LIMIT 1];

        Test.startTest();

        // 1. GET
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/externalInspection';
        req.httpMethod = 'GET';
        req.params.put('token', insp.External_Token__c);
        RestContext.request = req;
        RestContext.response = res;

        ExternalInspectionService.doGet();
        System.assertEquals(200, res.statusCode);
        System.assert(res.responseBody.toString().contains('1204'));

        HandoverWorkspaceController.HandoverContextWrapper extCtx = HandoverWorkspaceController.getExternalInspectionContext(insp.External_Token__c);
        System.assertNotEquals(null, extCtx);
        System.assert(!extCtx.checklistGroups.isEmpty());

        // 2. POST Submission
        req.httpMethod = 'POST';
        List<Inspection_Checklist_Item__c> items = [SELECT Id, Name, Category__c FROM Inspection_Checklist_Item__c WHERE Inspection__c = :insp.Id];
        List<ExternalInspectionService.ChecklistUpdateDTO> updates = new List<ExternalInspectionService.ChecklistUpdateDTO>();
        for (Inspection_Checklist_Item__c itm : items) {
            ExternalInspectionService.ChecklistUpdateDTO dto = new ExternalInspectionService.ChecklistUpdateDTO();
            dto.itemId = itm.Id;
            dto.result = 'Pass';
            dto.comments = 'Verified ok';
            updates.add(dto);
        }

        ExternalInspectionService.SubmissionPayload payload = new ExternalInspectionService.SubmissionPayload();
        payload.token = insp.External_Token__c;
        payload.inspectorName = 'Inspector Alex';
        payload.inspectorCompany = 'Audit Pvt Ltd';
        payload.overallComments = 'All items verified';
        payload.items = updates;
        req.requestBody = Blob.valueOf(JSON.serialize(payload));

        ExternalInspectionService.doPost();
        System.assertEquals(200, res.statusCode);

        // 3. POST again to verify submission lock
        RestResponse resLocked = new RestResponse();
        RestContext.response = resLocked;
        ExternalInspectionService.doPost();
        System.assertEquals(403, resLocked.statusCode);

        Test.stopTest();
    }

    @isTest
    static void testTargetedFunctionalCorrections() {
        Handover__c ho = HandoverTestDataFactory.createHandoverTestData();

        Test.startTest();

        // 1. Start Inspection
        HandoverWorkspaceController.startInspection(ho.Id, 'Internal', 'Lead Auditor', 'Quality Audits', 'auditor@example.com');
        Inspection__c insp = [SELECT Id FROM Inspection__c WHERE Handover__c = :ho.Id LIMIT 1];
        System.assertNotEquals(null, insp.Id);

        // 2. Verify all checklist items start unanswered (Result__c == null)
        List<Inspection_Checklist_Item__c> items = [
            SELECT Id, Name, Result__c, Category__c, Location__c 
            FROM Inspection_Checklist_Item__c 
            WHERE Inspection__c = :insp.Id
        ];
        System.assert(!items.isEmpty(), 'Items should be seeded');
        for (Inspection_Checklist_Item__c it : items) {
            System.assertEquals(null, it.Result__c, 'Item ' + it.Name + ' should start unanswered with null Result__c');
        }

        // 3. Add Line Item and Remove Line Item
        Id customItemId = HandoverWorkspaceController.addChecklistItem(insp.Id, 'Custom Balcony Check', 'Civil & Finishes', 'Balcony');
        System.assertNotEquals(null, customItemId);
        Inspection_Checklist_Item__c addedItem = [SELECT Id, Name, Result__c FROM Inspection_Checklist_Item__c WHERE Id = :customItemId];
        System.assertEquals('Custom Balcony Check', addedItem.Name);
        System.assertEquals(null, addedItem.Result__c);

        HandoverWorkspaceController.deleteChecklistItem(customItemId);
        List<Inspection_Checklist_Item__c> deletedList = [SELECT Id FROM Inspection_Checklist_Item__c WHERE Id = :customItemId];
        System.assertEquals(0, deletedList.size(), 'Checklist item should be removed');

        // 4. Update checklist item status to Pass and N/A
        HandoverWorkspaceController.updateChecklistItemStatus(items[0].Id, 'Pass', '');
        Inspection_Checklist_Item__c itPass = [SELECT Result__c FROM Inspection_Checklist_Item__c WHERE Id = :items[0].Id];
        System.assertEquals('Pass', itPass.Result__c);

        HandoverWorkspaceController.updateChecklistItemStatus(items[1].Id, 'N/A', '');
        Inspection_Checklist_Item__c itNA = [SELECT Result__c FROM Inspection_Checklist_Item__c WHERE Id = :items[1].Id];
        System.assertEquals('N/A', itNA.Result__c);

        // 5. Issue flow: directly raises snag from item
        HandoverWorkspaceController.raiseManualSnag(
            ho.Id,
            'Tile hollow behind washbasin',
            items[2].Category__c,
            items[2].Location__c,
            'Major',
            'SafeBuild Contractors',
            Date.today().addDays(3),
            items[2].Id
        );
        Inspection_Checklist_Item__c itIssue = [SELECT Result__c, Has_Snag_Raised__c FROM Inspection_Checklist_Item__c WHERE Id = :items[2].Id];
        System.assertEquals('Issue Found', itIssue.Result__c);
        System.assertEquals(true, itIssue.Has_Snag_Raised__c);

        // Verify dynamic inspection counters
        Inspection__c inspCounters = [SELECT Passed_Items_Count__c, Issue_Items_Count__c, NA_Items_Count__c FROM Inspection__c WHERE Id = :insp.Id];
        System.assertEquals(1, inspCounters.Passed_Items_Count__c);
        System.assertEquals(1, inspCounters.NA_Items_Count__c);
        System.assertEquals(1, inspCounters.Issue_Items_Count__c);

        Test.stopTest();
    }

    @isTest
    static void testTargetedSnagLifecycleAndAppointment() {
        Handover__c ho = HandoverTestDataFactory.createHandoverTestData();
        HandoverWorkspaceController.startInspection(ho.Id, 'Internal', 'Lead Auditor', 'Quality Audits', 'auditor@example.com');
        Inspection__c insp = [SELECT Id FROM Inspection__c WHERE Handover__c = :ho.Id LIMIT 1];
        List<Inspection_Checklist_Item__c> items = [
            SELECT Id, Name, Result__c, Category__c, Location__c 
            FROM Inspection_Checklist_Item__c 
            WHERE Inspection__c = :insp.Id
        ];
        HandoverWorkspaceController.raiseManualSnag(
            ho.Id,
            'Tile hollow behind washbasin',
            items[2].Category__c,
            items[2].Location__c,
            'Major',
            'SafeBuild Contractors',
            Date.today().addDays(3),
            items[2].Id
        );

        Test.startTest();

        // 6. Snag Lifecycle: Raised -> Assigned -> In Progress -> Verification -> Reopened -> Closed
        Snag__c s = [SELECT Id, Name, Status__c FROM Snag__c WHERE Handover__c = :ho.Id AND Checklist_Item__c = :items[2].Id LIMIT 1];
        System.assertEquals('Raised', s.Status__c);

        // Assign Owner
        HandoverWorkspaceController.assignSnagOwner(s.Id, UserInfo.getUserId(), 'Ceramic Specialist', 'Assigned for tile replacement');
        s = [SELECT Status__c, Assigned_Contractor_Name__c, Assigned_To__c FROM Snag__c WHERE Id = :s.Id];
        System.assertEquals('Assigned', s.Status__c);
        System.assertEquals('Ceramic Specialist', s.Assigned_Contractor_Name__c);

        // Verify Snag Board routes Assigned to inProgressSnags
        HandoverWorkspaceController.HandoverContextWrapper ctx = HandoverWorkspaceController.getHandoverContext(ho.Id);
        Boolean inProgFound = false;
        for (Snag__c ps : ctx.snagBoard.inProgressSnags) {
            if (ps.Id == s.Id) inProgFound = true;
        }
        System.assertEquals(true, inProgFound, 'Assigned snag should be in In Progress board column');

        // Submit for Verification with Evidence URL + Remarks
        HandoverWorkspaceController.submitSnagForVerification(s.Id, 'https://drive.google.com/rectified_tile.jpg', 'Replaced hollow tiles and grouted.');
        s = [SELECT Status__c, Evidence_URL__c, Resolution_Comments__c FROM Snag__c WHERE Id = :s.Id];
        System.assertEquals('Verification', s.Status__c);
        System.assertEquals('https://drive.google.com/rectified_tile.jpg', s.Evidence_URL__c);

        // Verify Snag Board routes Verification to verificationSnags
        ctx = HandoverWorkspaceController.getHandoverContext(ho.Id);
        Boolean verifFound = false;
        for (Snag__c vs : ctx.snagBoard.verificationSnags) {
            if (vs.Id == s.Id) verifFound = true;
        }
        System.assertEquals(true, verifFound, 'Verification snag should be in Verification board column');

        // Reject Verification with rejection reason
        HandoverWorkspaceController.verifySnag(s.Id, false, 'Grout color uneven, needs rework');
        s = [SELECT Status__c, Reopen_Count__c, Rejection_Reason__c FROM Snag__c WHERE Id = :s.Id];
        System.assertEquals('In Progress', s.Status__c);
        System.assertEquals(1, s.Reopen_Count__c);
        System.assertEquals('Grout color uneven, needs rework', s.Rejection_Reason__c);

        // Block Appointment while snag is unclosed
        Boolean blockedAppointment = false;
        try {
            HandoverWorkspaceController.scheduleAppointment(ho.Id, Date.today().addDays(5), '10:00 AM', '11:30 AM', 'Tower Desk', 'Bring ID');
        } catch (Exception ex) {
            blockedAppointment = true;
        }
        System.assertEquals(true, blockedAppointment, 'Appointment must be blocked with unclosed snags');

        // Re-submit and Approve
        HandoverWorkspaceController.submitSnagForVerification(s.Id, 'https://drive.google.com/rectified_tile_v2.jpg', 'Regrouted and color matched.');
        HandoverWorkspaceController.verifySnag(s.Id, true, 'Rectification approved');
        s = [SELECT Status__c, Closed_Date__c FROM Snag__c WHERE Id = :s.Id];
        System.assertEquals('Closed', s.Status__c);
        System.assertNotEquals(null, s.Closed_Date__c);

        // Complete all checklist items in bulk and complete inspection
        List<Inspection_Checklist_Item__c> toResolveItems = new List<Inspection_Checklist_Item__c>();
        for (Inspection_Checklist_Item__c ci : [SELECT Id FROM Inspection_Checklist_Item__c WHERE Inspection__c = :insp.Id]) {
            toResolveItems.add(new Inspection_Checklist_Item__c(Id = ci.Id, Result__c = 'Pass'));
        }
        update toResolveItems;
        HandoverWorkspaceController.completeInspection(insp.Id);

        // Verify Handover status is Handover Ready and Inspection_Status is Completed without auto-jumping stage
        Handover__c hoAdv = [SELECT Stage__c, Status__c, Inspection_Status__c FROM Handover__c WHERE Id = :ho.Id];
        System.assertEquals('Completed', hoAdv.Inspection_Status__c);
        System.assertEquals('Handover Ready', hoAdv.Status__c);

        // Advance to Appointment via Continue to Appointment
        HandoverWorkspaceController.proceedToAppointment(ho.Id);
        hoAdv = [SELECT Stage__c, Status__c FROM Handover__c WHERE Id = :ho.Id];
        System.assertEquals('Appointment', hoAdv.Stage__c);
        System.assertEquals('Handover Ready', hoAdv.Status__c);

        // Now Appointment scheduling succeeds
        HandoverWorkspaceController.scheduleAppointment(ho.Id, Date.today().addDays(5), '10:00 AM', '11:30 AM', 'Tower Desk', 'Bring ID');
        Handover__c hoApt = [SELECT Status__c, Appointment_Date__c FROM Handover__c WHERE Id = :ho.Id];
        System.assertEquals('Appointment Scheduled', hoApt.Status__c);

        Test.stopTest();
    }

    @isTest
    static void testTargetedEnhancementsAndRelatedLists() {
        Handover__c ho = HandoverTestDataFactory.createHandoverTestData();

        Test.startTest();

        // 1. Start Inspection
        HandoverWorkspaceController.startInspection(ho.Id, 'Internal', 'Site Supervisor', 'Audit Team', 'supervisor@example.com');
        Inspection__c insp = [SELECT Id FROM Inspection__c WHERE Handover__c = :ho.Id LIMIT 1];
        List<Inspection_Checklist_Item__c> items = [
            SELECT Id, Name, Category__c, Location__c 
            FROM Inspection_Checklist_Item__c 
            WHERE Inspection__c = :insp.Id
        ];
        System.assert(!items.isEmpty());

        // 2. Mark item as Issue and raise snag with Responsible Team
        HandoverWorkspaceController.raiseManualSnagWithTeam(
            ho.Id,
            'Damaged electrical switchboard',
            'Electrical',
            'Master Bedroom',
            'Major',
            'ElectroPro Services',
            'Electrical',
            Date.today().addDays(3),
            items[0].Id
        );

        Snag__c snag = [
            SELECT Id, Responsible_Team__c, External_Token__c, Checklist_Item__c, Status__c 
            FROM Snag__c 
            WHERE Handover__c = :ho.Id AND Checklist_Item__c = :items[0].Id 
            LIMIT 1
        ];
        System.assertEquals('Electrical', snag.Responsible_Team__c);
        System.assertNotEquals(null, snag.External_Token__c);

        // 3. Assign owner with team
        HandoverWorkspaceController.assignSnagOwnerWithTeam(
            snag.Id,
            UserInfo.getUserId(),
            'Master Electrician',
            'Electrical',
            'Assigned to fix switchboard wiring'
        );
        Snag__c assignedSnag = [SELECT Status__c, Responsible_Team__c, Assigned_Contractor_Name__c FROM Snag__c WHERE Id = :snag.Id];
        System.assertEquals('Assigned', assignedSnag.Status__c);
        System.assertEquals('Electrical', assignedSnag.Responsible_Team__c);

        // 4. Attach photo/video evidence file to Snag via ContentVersion / ContentDocumentLink
        ContentVersion cvSnag = new ContentVersion(
            Title = 'Snag_Defect_Photo',
            PathOnClient = 'Snag_Defect_Photo.jpg',
            VersionData = Blob.valueOf('Snag Photo Evidence Data'),
            IsMajorVersion = true
        );
        insert cvSnag;
        Id docIdSnag = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvSnag.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docIdSnag,
            LinkedEntityId = snag.Id,
            ShareType = 'V'
        );

        // 5. Submit for verification & approve
        HandoverWorkspaceController.submitSnagForVerification(snag.Id, 'Evidence attached via Files', 'Switchboard replaced and tested');
        HandoverWorkspaceController.verifySnag(snag.Id, true, 'Approved by Inspector');

        Snag__c closedSnag = [SELECT Status__c FROM Snag__c WHERE Id = :snag.Id];
        System.assertEquals('Closed', closedSnag.Status__c);

        // 6. Assert checklist item automatically updated to Pass
        Inspection_Checklist_Item__c resolvedItem = [SELECT Result__c FROM Inspection_Checklist_Item__c WHERE Id = :items[0].Id];
        System.assertEquals('Pass', resolvedItem.Result__c);

        // Mark remaining items Pass
        List<Inspection_Checklist_Item__c> remaining = new List<Inspection_Checklist_Item__c>();
        for (Integer i = 1; i < items.size(); i++) {
            remaining.add(new Inspection_Checklist_Item__c(Id = items[i].Id, Result__c = 'Pass'));
        }
        update remaining;

        // 7. Complete Inspection
        HandoverWorkspaceController.completeInspection(insp.Id);

        // 8. Schedule Appointment & Reschedule (verify update instead of duplicate Event)
        HandoverWorkspaceController.scheduleAppointment(ho.Id, Date.today().addDays(5), '10:00 AM', '11:00 AM', 'Clubhouse Lounge', 'Bring Aadhaar/ID');
        List<Event> eventsAfterSchedule = [SELECT Id, Subject, StartDateTime, EndDateTime FROM Event WHERE WhatId = :ho.Id];
        System.assertEquals(1, eventsAfterSchedule.size());

        HandoverWorkspaceController.rescheduleAppointment(ho.Id, Date.today().addDays(8), '02:00 PM', '03:30 PM', 'Tower Reception');
        List<Event> eventsAfterReschedule = [SELECT Id, Location, Description FROM Event WHERE WhatId = :ho.Id];
        System.assertEquals(1, eventsAfterReschedule.size(), 'Rescheduling should update the existing Event, not create duplicates');
        System.assertEquals('Tower Reception', eventsAfterReschedule[0].Location);

        // 9. Attach Handover Document to Handover record
        ContentVersion cvHo = new ContentVersion(
            Title = 'Possession_Signed_Acknowledgement',
            PathOnClient = 'Possession_Signed_Acknowledgement.pdf',
            VersionData = Blob.valueOf('Handover Document Data'),
            IsMajorVersion = true
        );
        insert cvHo;
        Id docIdHo = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvHo.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docIdHo,
            LinkedEntityId = ho.Id,
            ShareType = 'V'
        );

        // 10. Complete Physical Handover with Details (Sections A, B, C)
        HandoverWorkspaceController.completePhysicalHandoverWithDetails(
            ho.Id,
            3,
            2,
            'Key sets in pouch, access cards registered, parking fob #102',
            true,
            'EL-501',
            'WM-501',
            'GP-501',
            true,
            5,
            'Flawless delivery experience'
        );

        Handover__c hoCompleted = [
            SELECT Stage__c, Status__c, Access_Details__c, Customer_Acknowledgement_Status__c, Unit__c 
            FROM Handover__c 
            WHERE Id = :ho.Id
        ];
        System.assertEquals('Completed', hoCompleted.Stage__c);
        System.assertEquals('Key sets in pouch, access cards registered, parking fob #102', hoCompleted.Access_Details__c);
        System.assertEquals('Acknowledged', hoCompleted.Customer_Acknowledgement_Status__c);

        // 11. Test getHandoverContext verifies relatedLists and snagEvidenceFiles
        HandoverWorkspaceController.HandoverContextWrapper ctx = HandoverWorkspaceController.getHandoverContext(ho.Id);
        System.assertNotEquals(null, ctx.relatedLists);
        System.assertNotEquals(null, ctx.relatedLists.booking);
        System.assertNotEquals(null, ctx.relatedLists.customer);
        System.assertNotEquals(null, ctx.relatedLists.unit);
        System.assertNotEquals(null, ctx.relatedLists.inspections);
        System.assertNotEquals(null, ctx.relatedLists.checklistItems);
        System.assertNotEquals(null, ctx.relatedLists.snags);
        System.assertNotEquals(null, ctx.relatedLists.events);
        System.assertNotEquals(null, ctx.relatedLists.documents);
        System.assertNotEquals(null, ctx.relatedLists.handoverActivities);
        System.assertNotEquals(null, ctx.snagBoard.snagEvidenceFiles);
        System.assert(ctx.snagBoard.snagEvidenceFiles.containsKey(snag.Id), 'Evidence files must include uploaded photo');

        // 13. Test Formal Inspection Report and Sharing
        HandoverWorkspaceController.FormalReportWrapper repData = HandoverWorkspaceController.getFormalInspectionReportData(insp.Id);
        System.assertNotEquals(null, repData);
        System.assertNotEquals(null, repData.checklistItems);
        System.assertNotEquals(null, repData.snags);

        Map<String, Object> shareRep = HandoverWorkspaceController.shareInspectionReport(insp.Id, 'supervisor@example.com', 'Review defect report');
        System.assertEquals(true, shareRep.get('success'));

        Map<String, Object> shareSnag = HandoverWorkspaceController.shareSnagWithExternalUser(snag.Id, 'contractor@example.com', 'Please resolve immediately');
        System.assertEquals(true, shareSnag.get('emailSent'));

        Test.stopTest();
    }

    @isTest
    static void testStartInspectionGatingAndNoDuplicates() {
        Handover__c ho = HandoverTestDataFactory.createHandoverTestData();

        // 0. Test updateTargetInspectionDate before inspection is started
        Date targetDate = Date.today().addDays(7);
        HandoverWorkspaceController.updateTargetInspectionDate(ho.Id, targetDate);

        // 1. Valid Start Inspection with Date
        HandoverWorkspaceController.startInspection(ho.Id, 'Internal', 'Auditor 1', 'Audit Co', 'auditor@example.com', targetDate);
        List<Inspection__c> inspList1 = [SELECT Id, Inspection_Date__c FROM Inspection__c WHERE Handover__c = :ho.Id];
        System.assertEquals(1, inspList1.size());
        System.assertEquals(targetDate, inspList1[0].Inspection_Date__c);

        // 2. Starting inspection again should reuse existing inspection without creating duplicates
        HandoverWorkspaceController.startInspection(ho.Id, 'Internal', 'Auditor 2', 'Audit Co', 'auditor2@example.com', targetDate);
        List<Inspection__c> inspList2 = [SELECT Id FROM Inspection__c WHERE Handover__c = :ho.Id];
        System.assertEquals(1, inspList2.size());
        System.assertEquals(inspList1[0].Id, inspList2[0].Id);

        // 3. Test Readiness Gating Failure when Booking is Cancelled
        Booking__c b = [SELECT Id, Status__c, Rejection_Reason__c FROM Booking__c WHERE Id = :ho.Booking__c];
        b.Status__c = 'Cancelled';
        b.Rejection_Reason__c = 'Unit cancellation';
        update b;

        // Create new Handover with cancelled booking
        Handover__c hoBlocked = new Handover__c(
            Booking__c = b.Id,
            Stage__c = 'Readiness',
            Status__c = 'Readiness Pending'
        );
        insert hoBlocked;

        Boolean threwGatingError = false;
        try {
            HandoverWorkspaceController.startInspection(hoBlocked.Id, 'Internal', 'Auditor', 'Audit Co', 'auditor@example.com');
        } catch (AuraHandledException e) {
            threwGatingError = true;
        }
        System.assertEquals(true, threwGatingError, 'Should block startInspection when Booking is Cancelled');
    }

    @isTest
    static void testInspectionCompletionAndProceedToAppointment() {
        Handover__c ho = HandoverTestDataFactory.createHandoverTestData();
        HandoverWorkspaceController.startInspection(ho.Id, 'Internal', 'Auditor', 'Audit Co', 'auditor@example.com');
        Inspection__c insp = [SELECT Id FROM Inspection__c WHERE Handover__c = :ho.Id LIMIT 1];
        List<Inspection_Checklist_Item__c> items = [SELECT Id FROM Inspection_Checklist_Item__c WHERE Inspection__c = :insp.Id];

        // 1. Initial check - items pending
        Map<String, Object> stat1 = HandoverWorkspaceController.getInspectionCompletionStatus(ho.Id);
        System.assertEquals(false, (Boolean) stat1.get('canComplete'));

        // 2. Mark one item Issue Found and raise snag
        HandoverWorkspaceController.updateChecklistItem(items[0].Id, 'Issue Found', 'Living & Dining', 'Wall defect');
        List<Snag__c> snags = [SELECT Id FROM Snag__c WHERE Handover__c = :ho.Id];
        System.assert(!snags.isEmpty());

        // 3. Mark rest as Pass
        List<Inspection_Checklist_Item__c> toPass = new List<Inspection_Checklist_Item__c>();
        for (Integer i = 1; i < items.size(); i++) {
            toPass.add(new Inspection_Checklist_Item__c(Id = items[i].Id, Result__c = 'Pass'));
        }
        update toPass;

        // 4. Cannot complete yet because items[0] has issue and snag is open
        Map<String, Object> stat2 = HandoverWorkspaceController.getInspectionCompletionStatus(ho.Id);
        System.assertEquals(false, (Boolean) stat2.get('canComplete'));

        // 5. Verify snag -> closes snag and updates items[0] to Pass
        HandoverWorkspaceController.verifySnag(snags[0].Id, true, 'Approved fix');
        Inspection_Checklist_Item__c itm0Updated = [SELECT Result__c FROM Inspection_Checklist_Item__c WHERE Id = :items[0].Id];
        System.assertEquals('Pass', itm0Updated.Result__c);

        // 6. Completion status allows completion
        Map<String, Object> stat3 = HandoverWorkspaceController.getInspectionCompletionStatus(ho.Id);
        System.assertEquals(true, (Boolean) stat3.get('canComplete'));

        // 7. Complete inspection
        HandoverWorkspaceController.completeInspection(insp.Id);
        Handover__c hoAfterInsp = [SELECT Inspection_Status__c, Status__c, Stage__c FROM Handover__c WHERE Id = :ho.Id];
        System.assertEquals('Completed', hoAfterInsp.Inspection_Status__c);
        System.assertEquals('Handover Ready', hoAfterInsp.Status__c);

        // 8. Proceed to appointment
        HandoverWorkspaceController.proceedToAppointment(ho.Id);
        Handover__c hoAfterAppt = [SELECT Stage__c, Status__c FROM Handover__c WHERE Id = :ho.Id];
        System.assertEquals('Appointment', hoAfterAppt.Stage__c);
        System.assertEquals('Handover Ready', hoAfterAppt.Status__c);
    }
}
