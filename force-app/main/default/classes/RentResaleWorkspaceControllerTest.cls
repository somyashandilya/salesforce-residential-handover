@IsTest
private class RentResaleWorkspaceControllerTest {

    @TestSetup
    static void setupTestData() {
        HandoverTestDataFactory.createHandoverTestData();
    }

    @IsTest
    static void testRentalCompleteLifecycle() {
        Handover__c ho = [SELECT Id FROM Handover__c LIMIT 1];

        Test.startTest();

        // 1. Create Rental Request from Handover
        Id rentalReqId = RentResaleWorkspaceController.createRequestFromHandover(ho.Id, 'Rental');
        System.assertNotEquals(null, rentalReqId, 'Rental request should be created');

        // 2. Get Context
        RentResaleWorkspaceController.RequestContextWrapper ctx = RentResaleWorkspaceController.getRequestContext(rentalReqId);
        System.assertEquals('Rental', ctx.recordTypeName);
        System.assertEquals('Validation', ctx.request.Stage__c);
        System.assert(!ctx.eligibilityChecks.isEmpty());
        System.assert(!ctx.documents.isEmpty());

        // 3. Update Preferences
        RentResaleWorkspaceController.updateOwnerPreferences(rentalReqId, 48000, 280000, Date.today().addDays(10), 'Fully Furnished', 'Family', 'Allowed');

        // 4. Mark Eligible -> Listing
        RentResaleWorkspaceController.markRentalEligible(rentalReqId);
        Rent_Resale_Request__c reqAfterElig = [SELECT Stage__c, Status__c FROM Rent_Resale_Request__c WHERE Id = :rentalReqId];
        System.assertEquals('Listing', reqAfterElig.Stage__c);

        // 5. Assign Handling
        RentResaleWorkspaceController.assignRentalHandling(rentalReqId, 'In-house Rental Desk', null, 'Standard 1 month brokerage');

        // 6. Add Prospect & Submit Offer
        Id prospId = RentResaleWorkspaceController.addRentalProspect(
            rentalReqId, 'Siddharth Roy', '+91 91234 56789', 'siddharth@example.com', 'Rental Desk', 47000, 280000, Date.today().addDays(15), 'Family'
        );
        RentResaleWorkspaceController.updateRentalProspectStage(prospId, 'Visited');
        RentResaleWorkspaceController.submitRentalOffer(prospId, 47500, 280000, Date.today().addDays(12));
        RentResaleWorkspaceController.sendOfferToOwner(prospId);

        // 7. Owner Decision -> Accept -> Stage becomes Tenant & Lease
        RentResaleWorkspaceController.recordOwnerOfferDecision(prospId, 'Accepted', 'Agreed to terms');
        Rent_Resale_Request__c reqAfterAccept = [SELECT Stage__c, Selected_Tenant_Name__c, Monthly_Rent__c FROM Rent_Resale_Request__c WHERE Id = :rentalReqId];
        System.assertEquals('Tenant & Lease', reqAfterAccept.Stage__c);
        System.assertEquals('Siddharth Roy', reqAfterAccept.Selected_Tenant_Name__c);

        // 8. Update Lease Terms
        RentResaleWorkspaceController.updateLeaseTerms(rentalReqId, 47500, 280000, Date.today().addDays(12), Date.today().addYears(1), 11, 5.0, 30, 'Tenant');

        // 9. Activate Lease -> Active Lease & Tenancy 1 History
        RentResaleWorkspaceController.activateLease(rentalReqId);
        Rent_Resale_Request__c reqActive = [SELECT Stage__c, Status__c, Active_Tenancy_Number__c FROM Rent_Resale_Request__c WHERE Id = :rentalReqId];
        System.assertEquals('Active Lease', reqActive.Stage__c);
        List<Tenancy_History__c> thList = [SELECT Id, Tenancy_Number__c, Status__c FROM Tenancy_History__c WHERE Rent_Resale_Request__c = :rentalReqId];
        System.assert(!thList.isEmpty());
        System.assertEquals('Active', thList[0].Status__c);

        // 10. Start Renewal & Record Decision (Renew Current Tenant)
        RentResaleWorkspaceController.startRenewalStage(rentalReqId);
        RentResaleWorkspaceController.recordRenewalDecision(rentalReqId, 'Renew Current Tenant', 'Renewed for another year at 5% escalation', Date.today().addYears(1), Date.today().addYears(2), 50000);
        Rent_Resale_Request__c reqRenewed = [SELECT Stage__c, Monthly_Rent__c FROM Rent_Resale_Request__c WHERE Id = :rentalReqId];
        System.assertEquals('Active Lease', reqRenewed.Stage__c);
        System.assertEquals(50000, reqRenewed.Monthly_Rent__c);

        // 11. Test Re-rent to New Tenant Decision
        RentResaleWorkspaceController.recordRenewalDecision(rentalReqId, 'Re-rent to New Tenant', 'Tenant moving cities, listing again', null, null, null);
        Rent_Resale_Request__c reqReRent = [SELECT Stage__c, Active_Tenancy_Number__c FROM Rent_Resale_Request__c WHERE Id = :rentalReqId];
        System.assertEquals('Listing', reqReRent.Stage__c);
        System.assertEquals(2, reqReRent.Active_Tenancy_Number__c);

        // 12. Test Stop Renting Decision
        RentResaleWorkspaceController.recordRenewalDecision(rentalReqId, 'Stop Renting', 'Owner moving back into flat', null, null, null);
        Rent_Resale_Request__c reqStopped = [SELECT Stage__c, Status__c, Closure_Date__c FROM Rent_Resale_Request__c WHERE Id = :rentalReqId];
        System.assertEquals('Closed', reqStopped.Stage__c);
        System.assertNotEquals(null, reqStopped.Closure_Date__c);

        Test.stopTest();
    }

    @IsTest
    static void testResaleCompleteLifecycle() {
        Handover__c ho = [SELECT Id FROM Handover__c LIMIT 1];

        Test.startTest();

        // 1. Create Resale Request
        Id resaleReqId = RentResaleWorkspaceController.createRequestFromHandover(ho.Id, 'Resale');
        System.assertNotEquals(null, resaleReqId);

        // 2. Assign Request -> Property Listing & Buyer Sourcing
        RentResaleWorkspaceController.assignResaleRequest(resaleReqId, UserInfo.getUserId(), null);
        Rent_Resale_Request__c reqAssigned = [SELECT Stage__c, Status__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Property Listing & Buyer Sourcing', reqAssigned.Stage__c);

        // 3. Update Listing
        RentResaleWorkspaceController.updateResaleListing(resaleReqId, 12500000, 'Active', Date.today());

        // 4. Add Multiple Buyers (Testing no-overwrite)
        Id buyer1Id = RentResaleWorkspaceController.addResaleBuyer(resaleReqId, 'Anil Kapoor', '+91 98989 89898', 'anil@example.com', 12500000, 'Top floor 3BHK', 'Portal', 'Pre-approved loan 1 Cr', null);
        Id buyer2Id = RentResaleWorkspaceController.addResaleBuyer(resaleReqId, 'Pooja Verma', '+91 97777 77777', 'pooja@example.com', 12800000, 'East facing', 'Channel Partner', 'Self-funded', null);
        List<Rental_Prospect__c> buyers = [SELECT Id, Prospect_Name__c, Budget__c, Prospect_Type__c FROM Rental_Prospect__c WHERE Rent_Resale_Request__c = :resaleReqId];
        System.assertEquals(2, buyers.size(), 'Both buyers should exist independently without overwrite');

        // 5. Schedule Site Visit for Buyer 1 & Verify initial rating is NOT 'Good' (null/unrated)
        Id svId = RentResaleWorkspaceController.scheduleResaleSiteVisit(resaleReqId, buyer1Id, Date.today(), '11:00 AM', 'On-Site Pavilion', 'Show balcony view', 'Family visit confirmed');
        System.assertNotEquals(null, svId);
        Site_Visit__c svCreated = [SELECT Id, Status__c, Rating__c, Buyer__c FROM Site_Visit__c WHERE Id = :svId];
        System.assertEquals('Scheduled', svCreated.Status__c);
        System.assertEquals(null, svCreated.Rating__c, 'Initial rating must NOT be auto-populated to Good');
        System.assertEquals(buyer1Id, svCreated.Buyer__c, 'Site visit should link to Buyer');

        // 5b. Reschedule Site Visit
        RentResaleWorkspaceController.rescheduleSiteVisit(svId, Date.today(), '02:00 PM', 'On-Site Clubhouse', 'Client requested afternoon slot');
        Site_Visit__c svRescheduled = [SELECT Id, Visit_Time__c, Location__c FROM Site_Visit__c WHERE Id = :svId];
        System.assertEquals('02:00 PM', svRescheduled.Visit_Time__c);

        // 5c. Mark Site Visit Completed
        RentResaleWorkspaceController.markSiteVisitCompleted(svId);
        Site_Visit__c svCompleted = [SELECT Id, Status__c FROM Site_Visit__c WHERE Id = :svId];
        System.assertEquals('Completed', svCompleted.Status__c);

        // 6. Explicitly Log Feedback
        RentResaleWorkspaceController.logSiteVisitFeedback(svId, 'Buyer liked the layout and view', 'Good', 'Completed');
        Site_Visit__c svFeedback = [SELECT Id, Rating__c, Comments__c FROM Site_Visit__c WHERE Id = :svId];
        System.assertEquals('Good', svFeedback.Rating__c);

        // 6b. Test moveToResaleStage
        RentResaleWorkspaceController.moveToResaleStage(resaleReqId, 'Site Visit');
        Rent_Resale_Request__c reqStageCheck = [SELECT Stage__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Site Visit', reqStageCheck.Stage__c);

        // 7. Verify Context has financialSummary, buyers, and documents
        RentResaleWorkspaceController.RequestContextWrapper ctx = RentResaleWorkspaceController.getRequestContext(resaleReqId);
        System.assertNotEquals(null, ctx.financialSummary);
        System.assertEquals(2, ctx.buyers.size());

        // 8. Commercial Deal Agreement -> Advances to Approval, then KYC & Token
        RentResaleWorkspaceController.recordResaleDealClosure(resaleReqId, buyer1Id, 12200000, 244000, 'CHQ-897654', Date.today(), 'Agreed resale price 1.22 Cr');
        Rent_Resale_Request__c reqDeal = [SELECT Stage__c, Final_Resale_Value__c, Buyer_Name__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Approval', reqDeal.Stage__c);
        System.assertEquals(12200000, reqDeal.Final_Resale_Value__c);
        System.assertEquals('Anil Kapoor', reqDeal.Buyer_Name__c);

        RentResaleWorkspaceController.processDealApproval(resaleReqId, true, 'Approved terms');
        Rent_Resale_Request__c reqApproved = [SELECT Stage__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('KYC & Token', reqApproved.Stage__c);

        // 8b. Record Full Payment Details (Pending)
        RentResaleWorkspaceController.recordTokenPayment(resaleReqId, 500000, Date.today(), 'Bank Transfer (RTGS)', 'TOK-897654', 'PROOF-TOK', 'Token payment received');
        RentResaleWorkspaceController.verifyTokenPayment(resaleReqId, true, 'Token verified');
        RentResaleWorkspaceController.recordFullPaymentDetails(resaleReqId, Date.today(), 'PAY-897654', 'Pending');

        // 8c. Test gated transition to Documentation (should fail if Full Payment is unverified)
        Boolean caughtPaymentException = false;
        try {
            RentResaleWorkspaceController.proceedToTransferDocStage(resaleReqId);
        } catch (Exception e) {
            caughtPaymentException = true;
        }
        System.assert(caughtPaymentException, 'Should prevent proceeding to Documentation until Full Payment is verified');

        // Verify full payment
        RentResaleWorkspaceController.verifyFullPayment(resaleReqId, true, 'Full payment cleared');

        // 9. Document Actions: Generate, Upload, Share, Verify
        List<Rent_Resale_Document__c> docs = [SELECT Id, Document_Type__c FROM Rent_Resale_Document__c WHERE Rent_Resale_Request__c = :resaleReqId];
        if (!docs.isEmpty()) {
            RentResaleWorkspaceController.generateDocument(docs[0].Id);
            RentResaleWorkspaceController.uploadDocument(docs[0].Id, 'agreement_scan.pdf');
            RentResaleWorkspaceController.shareDocument(docs[0].Id, 'buyer@example.com', 'Please review');
        }
        for (Rent_Resale_Document__c d : docs) {
            RentResaleWorkspaceController.verifyDocument(d.Id, true, 'Verified original copy');
        }

        // 9b. Now proceed to Documentation stage succeeds
        RentResaleWorkspaceController.proceedToTransferDocStage(resaleReqId);
        Rent_Resale_Request__c reqDocStage = [SELECT Stage__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Documentation / Ownership Transfer', reqDocStage.Stage__c);

        // 10. Close Resale
        RentResaleWorkspaceController.closeResale(resaleReqId);
        Rent_Resale_Request__c reqClosed = [SELECT Stage__c, Status__c, Closure_Date__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Closed', reqClosed.Stage__c);
        System.assertNotEquals(null, reqClosed.Closure_Date__c);

        // 11. Rejection test
        Id reqToReject = RentResaleWorkspaceController.createRequestFromHandover(ho.Id, 'Resale');
        RentResaleWorkspaceController.rejectResale(reqToReject, 'Price Unrealistic', 'Owner quoted above market');
        Rent_Resale_Request__c reqRejected = [SELECT Status__c, Rejection_Reason__c FROM Rent_Resale_Request__c WHERE Id = :reqToReject];
        System.assertEquals('Rejected', reqRejected.Status__c);

        Test.stopTest();
    }

    @IsTest
    static void testTenStageResaleSequentialLifecycle() {
        Handover__c ho = [SELECT Id FROM Handover__c LIMIT 1];

        Test.startTest();

        // Stage 1: Lead Allocation
        Id resaleReqId = RentResaleWorkspaceController.createRequestFromHandover(ho.Id, 'Resale');
        RentResaleWorkspaceController.assignResaleRequest(resaleReqId, UserInfo.getUserId(), null);
        Rent_Resale_Request__c req1 = [SELECT Stage__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Property Listing & Buyer Sourcing', req1.Stage__c);

        // Stage 2: Property Listing & Buyer Sourcing
        RentResaleWorkspaceController.updateResaleListing(resaleReqId, 15000000, 'Active', Date.today());
        Id bId = RentResaleWorkspaceController.addResaleBuyer(resaleReqId, 'Ravi Verma', '+91 99999 11111', 'ravi@example.com', 15000000, 'High rise', 'Direct', 'All cash', null);
        RentResaleWorkspaceController.proceedToSiteVisitStage(resaleReqId);
        Rent_Resale_Request__c req2 = [SELECT Stage__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Site Visit', req2.Stage__c);

        // Stage 3: Site Visit
        Id svId = RentResaleWorkspaceController.scheduleResaleSiteVisit(resaleReqId, bId, Date.today(), '10:00 AM', 'On-Site Sales Lounge', 'Show 3BHK layout', 'Client confirmed');
        Site_Visit__c sv1 = [SELECT Status__c, Rating__c FROM Site_Visit__c WHERE Id = :svId];
        System.assertEquals('Scheduled', sv1.Status__c);
        System.assertEquals(null, sv1.Rating__c);
        RentResaleWorkspaceController.markSiteVisitCompleted(svId);
        RentResaleWorkspaceController.logSiteVisitFeedback(svId, 'Buyer satisfied', 'Good', 'Completed');
        RentResaleWorkspaceController.proceedToDealFinalisation(resaleReqId);
        Rent_Resale_Request__c req3 = [SELECT Stage__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Deal Finalisation', req3.Stage__c);

        // Stage 4: Deal Finalisation
        RentResaleWorkspaceController.recordDealFinalisation(resaleReqId, bId, 14800000, 296000, 1000000, '10% Token, balance within 30 days', 'Final price agreed');
        Rent_Resale_Request__c req4 = [SELECT Stage__c, Approval_Status__c, Token_Amount__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Approval', req4.Stage__c);
        System.assertEquals('Pending Approval', req4.Approval_Status__c);
        System.assertEquals(1000000, req4.Token_Amount__c);

        // Stage 5: Approval (Approval gate)
        Boolean earlyKycBlocked = false;
        try {
            RentResaleWorkspaceController.proceedToKycTokenStage(resaleReqId);
        } catch (Exception e) {
            earlyKycBlocked = true;
        }
        System.assertEquals(true, earlyKycBlocked, 'Proceeding to KYC before approval must be blocked');
        RentResaleWorkspaceController.processDealApproval(resaleReqId, true, 'Commercial terms approved by Sales Director');
        Rent_Resale_Request__c req5 = [SELECT Stage__c, Approval_Status__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('KYC & Token', req5.Stage__c);
        System.assertEquals('Approved', req5.Approval_Status__c);

        // Stage 6: KYC & Token
        // Test linkUploadedFile for KYC doc
        ContentVersion testCv = new ContentVersion(
            Title = 'Test_Buyer_PAN',
            PathOnClient = 'test_pan.pdf',
            VersionData = Blob.valueOf('PDF-CONTENT-SAMPLE'),
            IsMajorVersion = true
        );
        insert testCv;
        Id testConDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testCv.Id LIMIT 1].ContentDocumentId;

        List<Rent_Resale_Document__c> kycDocs = [SELECT Id FROM Rent_Resale_Document__c WHERE Rent_Resale_Request__c = :resaleReqId AND Document_Type__c IN ('PAN', 'Identity / Address Proof', 'Required KYC Declaration')];
        RentResaleWorkspaceController.linkUploadedFile(kycDocs[0].Id, testConDocId, 'test_pan.pdf');
        for (Rent_Resale_Document__c d : kycDocs) {
            RentResaleWorkspaceController.verifyDocument(d.Id, true, 'Buyer KYC verified');
        }

        // Test recordAndGenerateTokenReceipt
        RentResaleWorkspaceController.recordAndGenerateTokenReceipt(resaleReqId, 1000000, Date.today(), 'Bank Transfer (RTGS)', 'RTGS-998877', 'Token payment verified');
        RentResaleWorkspaceController.verifyTokenPayment(resaleReqId, true, 'Receipt verified');

        RentResaleWorkspaceController.proceedToAllotmentStage(resaleReqId);
        Rent_Resale_Request__c req6 = [SELECT Stage__c, Token_Receipt_Number__c, Token_Payment_Status__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Allotment / Welcome', req6.Stage__c);
        System.assertNotEquals(null, req6.Token_Receipt_Number__c);
        System.assertEquals('Verified', req6.Token_Payment_Status__c);

        // Stage 7: Allotment / Welcome (Only 3 Letters: Allotment Letter, Welcome Letter, Car Parking Letter, Generate -> Download only)
        List<Rent_Resale_Document__c> allotDocs = [SELECT Id, Document_Type__c FROM Rent_Resale_Document__c WHERE Rent_Resale_Request__c = :resaleReqId AND Document_Type__c IN ('Allotment Letter', 'Welcome Letter', 'Car Parking Letter')];
        for (Rent_Resale_Document__c d : allotDocs) {
            RentResaleWorkspaceController.generateDocument(d.Id);
        }
        RentResaleWorkspaceController.proceedToFullPaymentStage(resaleReqId);
        Rent_Resale_Request__c req7 = [SELECT Stage__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Full Payment & Receipt', req7.Stage__c);

        // Stage 8: Full Payment & Receipt
        RentResaleWorkspaceController.recordFullPayment(resaleReqId, 13800000, Date.today(), 'Bank Transfer (RTGS)', 'RTGS-FULL-554433');
        RentResaleWorkspaceController.verifyFullPayment(resaleReqId, true, 'Balance receipt cleared and verified');
        RentResaleWorkspaceController.proceedToTransferDocStage(resaleReqId);
        Rent_Resale_Request__c req8 = [SELECT Stage__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Documentation / Ownership Transfer', req8.Stage__c);

        // Stage 9: Ownership Transfer / Stamp Duty E-Sign Flow
        Id stampDocId = RentResaleWorkspaceController.generateStampDutyDocument(resaleReqId);
        System.assertNotEquals(null, stampDocId, 'Stamp Duty Document must be generated');
        Rent_Resale_Document__c docGen = [SELECT Status__c, Content_Document_Id__c FROM Rent_Resale_Document__c WHERE Id = :stampDocId];
        System.assertEquals('Generated', docGen.Status__c);
        System.assertNotEquals(null, docGen.Content_Document_Id__c);

        // Send for signature
        RentResaleWorkspaceController.sendStampDutyForSignature(resaleReqId);
        Rent_Resale_Document__c docSent = [SELECT Status__c FROM Rent_Resale_Document__c WHERE Id = :stampDocId];
        System.assertEquals('Pending Signature', docSent.Status__c);

        // Verification of closure gating: closeResale must fail before signature
        Boolean gateBlocked = false;
        try {
            RentResaleWorkspaceController.closeResale(resaleReqId);
        } catch (Exception ex) {
            gateBlocked = true;
        }
        System.assert(gateBlocked, 'Resale closure must be strictly blocked until Stamp Duty document is signed');

        // Complete e-signature
        RentResaleWorkspaceController.completeStampDutySignature(resaleReqId);
        Rent_Resale_Document__c docSigned = [SELECT Status__c FROM Rent_Resale_Document__c WHERE Id = :stampDocId];
        System.assertEquals('Signed', docSigned.Status__c);

        // Stage 10: Closed
        RentResaleWorkspaceController.closeResale(resaleReqId);
        Rent_Resale_Request__c req10 = [SELECT Stage__c, Status__c, Closure_Date__c FROM Rent_Resale_Request__c WHERE Id = :resaleReqId];
        System.assertEquals('Closed', req10.Stage__c);
        System.assertEquals('Closed', req10.Status__c);
        System.assertNotEquals(null, req10.Closure_Date__c);

        Test.stopTest();
    }

    @IsTest
    static void testLandingPageAndActivityHelpers() {
        Handover__c ho = [SELECT Id FROM Handover__c LIMIT 1];
        Id reqId = RentResaleWorkspaceController.createRequestFromHandover(ho.Id, 'Rental');

        Test.startTest();

        // Landing page queries
        List<Map<String, Object>> allList = RentResaleWorkspaceController.getPostSaleRequests('All');
        System.assert(!allList.isEmpty());
        List<Map<String, Object>> rentalList = RentResaleWorkspaceController.getPostSaleRequests('Rental');
        System.assert(!rentalList.isEmpty());
        List<Map<String, Object>> resaleList = RentResaleWorkspaceController.getPostSaleRequests('Resale');
        List<Map<String, Object>> openList = RentResaleWorkspaceController.getPostSaleRequests('Open');
        System.assert(!openList.isEmpty());

        // Standard activities
        RentResaleWorkspaceController.sendActivityEmail(reqId, 'client@example.com', 'Rental Update', 'Email body');
        RentResaleWorkspaceController.createActivityTask(reqId, 'Follow-up with Tenant', Date.today().addDays(1), 'High', 'Call for KYC');
        RentResaleWorkspaceController.logActivityCall(reqId, 'Discussion with Owner', 'Confirmed rent');

        Task openTask = [SELECT Id FROM Task WHERE WhatId = :reqId AND Status != 'Completed' LIMIT 1];
        RentResaleWorkspaceController.completeActivityTask(openTask.Id);

        RentResaleWorkspaceController.updateRequestOwner(reqId, UserInfo.getUserId());

        Test.stopTest();
    }
}
