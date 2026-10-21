/**
 * @description Generates Possession Documents and Handover Packs for the Residential Handover Module.
 * Saves generated documents as Salesforce Files (ContentVersion / ContentDocumentLink).
 */
public without sharing class HandoverDocumentGenerator {

    public static void generateHandoverPack(Id handoverId) {
        Handover__c ho = [
            SELECT Id, Name, Completed_Date_Time__c, Completed_By__r.Name,
                   Customer__r.Name, Customer__r.PersonEmail,
                   Property__r.Name, Tower__r.Name, Unit__r.Name,
                   Keys_Sets_Count__c, Access_Cards_Count__c, Documents_List__c,
                   Electricity_Meter_Reading__c, Water_Meter_Reading__c,
                   Customer_Signee_Name__c, Feedback_Rating__c, Final_Remarks__c
            FROM Handover__c
            WHERE Id = :handoverId
            LIMIT 1
        ];

        List<String> letterLines = new List<String>{
            'OFFICIAL POSSESSION CERTIFICATE & LETTER',
            '',
            'Handover Reference: ' + ho.Name,
            'Date of Possession: ' + (ho.Completed_Date_Time__c != null ? ho.Completed_Date_Time__c.format('dd MMMM yyyy, HH:mm') : System.now().format('dd MMMM yyyy')),
            '',
            'Customer Name: ' + ho.Customer__r.Name,
            'Project: ' + ho.Property__r.Name,
            'Tower: ' + ho.Tower__r.Name,
            'Unit: ' + ho.Unit__r.Name,
            '',
            'This is to certify that vacant, peaceful, and physical possession of the above referenced apartment unit has been formally handed over to the rightful purchaser(s).',
            '',
            'Keys Handed Over: ' + ho.Keys_Sets_Count__c + ' complete physical set(s)',
            'Access Cards Issued: ' + ho.Access_Cards_Count__c + ' RFID access cards',
            'Meter Readings at Possession:',
            '  - Electricity Meter: ' + ho.Electricity_Meter_Reading__c,
            '  - Water Meter: ' + ho.Water_Meter_Reading__c,
            '',
            'Customer Acknowledgement Signee: ' + ho.Customer_Signee_Name__c,
            'Handover Executed By: ' + (ho.Completed_By__r != null ? ho.Completed_By__r.Name : UserInfo.getName())
        };
        createFile(ho.Id, 'Possession_Letter_' + ho.Unit__r.Name + '.txt', String.join(letterLines, '\n'));

        List<String> keyLines = new List<String>{
            'KEY ACKNOWLEDGEMENT RECEIPT',
            '',
            'Unit: ' + ho.Unit__r.Name + ' (' + ho.Property__r.Name + ', ' + ho.Tower__r.Name + ')',
            'Received By: ' + ho.Customer_Signee_Name__c,
            'Date: ' + System.now().format('dd MMM yyyy'),
            '',
            'Keys Handed Over: ' + ho.Keys_Sets_Count__c + ' Sets',
            'Access Cards: ' + ho.Access_Cards_Count__c + ' Cards',
            'Possession Documentation: Handed Over',
            '',
            'Signature / Acknowledged By: ' + ho.Customer_Signee_Name__c
        };
        createFile(ho.Id, 'Key_Receipt_' + ho.Unit__r.Name + '.txt', String.join(keyLines, '\n'));

        List<Snag__c> snags = [
            SELECT Name, Category__c, Severity__c, Status__c, Snag_Description__c, Location_Pin__c, Resolution_Comments__c
            FROM Snag__c
            WHERE Handover__c = :ho.Id
        ];
        List<String> snagLines = new List<String>{
            'FINAL SNAG & DEFECT REPORT',
            '',
            'Unit: ' + ho.Unit__r.Name + ' - ' + ho.Property__r.Name,
            'Total Defects Recorded: ' + snags.size(),
            ''
        };
        for (Snag__c s : snags) {
            snagLines.add('- [' + s.Status__c + '] ' + s.Name + ' (' + s.Category__c + ' - ' + s.Severity__c + ')');
            snagLines.add('  Location: ' + s.Location_Pin__c);
            snagLines.add('  Description: ' + s.Snag_Description__c);
            snagLines.add('  Resolution: ' + (String.isNotBlank(s.Resolution_Comments__c) ? s.Resolution_Comments__c : 'N/A'));
            snagLines.add('');
        }
        createFile(ho.Id, 'Final_Snag_Report_' + ho.Unit__r.Name + '.txt', String.join(snagLines, '\n'));
    }

    public static void createFile(Id parentId, String fileName, String content) {
        ContentVersion cv = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName,
            VersionData = Blob.valueOf(content),
            IsMajorVersion = true
        );
        insert cv;

        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = conDocId,
            LinkedEntityId = parentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
    }
}
