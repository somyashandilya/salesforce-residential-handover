/**
 * @description Comprehensive unit test suite for InspectionReportPDFController.
 */
@isTest
private class InspectionReportPDFControllerTest {

    @isTest
    static void testInspectionReportWithInspectionId() {
        Handover__c ho = HandoverTestDataFactory.createHandoverTestData();
        HandoverWorkspaceController.startInspection(ho.Id, 'Internal', 'John Inspector', 'Quality Corp', 'inspector@example.com');
        Inspection__c insp = [SELECT Id FROM Inspection__c WHERE Handover__c = :ho.Id LIMIT 1];

        // Seed an issue item and snag
        List<Inspection_Checklist_Item__c> items = [SELECT Id FROM Inspection_Checklist_Item__c WHERE Inspection__c = :insp.Id];
        if (!items.isEmpty()) {
            HandoverWorkspaceController.updateChecklistItem(items[0].Id, 'Issue Found', 'Living & Dining', 'Wall plaster crack');
        }

        Test.setCurrentPage(Page.InspectionReportPDF);
        ApexPages.currentPage().getParameters().put('id', insp.Id);

        Test.startTest();
        InspectionReportPDFController ctrl = new InspectionReportPDFController();
        Test.stopTest();

        System.assertEquals(true, ctrl.hasInspection);
        System.assertNotEquals(null, ctrl.inspection);
        System.assertNotEquals(null, ctrl.categoryGroups);
        System.assert(!ctrl.categoryGroups.isEmpty());
        System.assert(ctrl.totalItemsCount > 0);
        System.assertNotEquals(null, ctrl.generatedDateFormatted);
        System.assertNotEquals(null, ctrl.certifiedByName);
    }

    @isTest
    static void testInspectionReportWithHandoverId() {
        Handover__c ho = HandoverTestDataFactory.createHandoverTestData();
        HandoverWorkspaceController.startInspection(ho.Id, 'Internal', 'John Inspector', 'Quality Corp', 'inspector@example.com');

        Test.setCurrentPage(Page.InspectionReportPDF);
        ApexPages.currentPage().getParameters().put('id', ho.Id);

        Test.startTest();
        InspectionReportPDFController ctrl = new InspectionReportPDFController();
        Test.stopTest();

        System.assertEquals(true, ctrl.hasInspection);
        System.assertNotEquals(null, ctrl.inspection);
    }

    @isTest
    static void testInspectionReportWithNullId() {
        Test.setCurrentPage(Page.InspectionReportPDF);
        ApexPages.currentPage().getParameters().put('id', null);

        Test.startTest();
        InspectionReportPDFController ctrl = new InspectionReportPDFController();
        Test.stopTest();

        System.assertEquals(false, ctrl.hasInspection);
    }
}
