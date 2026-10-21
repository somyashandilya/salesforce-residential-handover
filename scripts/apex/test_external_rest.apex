Inspection__c insp = [SELECT Id, External_Token__c FROM Inspection__c ORDER BY CreatedDate DESC LIMIT 1];

// Test POST with token in JSON body
RestRequest reqPost = new RestRequest();
reqPost.requestURI = '/services/apexrest/externalInspection';
reqPost.httpMethod = 'POST';

Inspection_Checklist_Item__c itm = [SELECT Id FROM Inspection_Checklist_Item__c WHERE Inspection__c = :insp.Id LIMIT 1];
String bodyJson = '{"token":"' + insp.External_Token__c + '",'
    + '"items":[{"itemId":"' + itm.Id + '","result":"Pass","notes":"Verified on site"}],'
    + '"snags":[{"category":"Electrical","description":"Balcony light switch loose","severity":"Minor","locationPin":"Balcony","pinX":42,"pinY":65}],'
    + '"finalize":false}';
reqPost.requestBody = Blob.valueOf(bodyJson);

RestResponse resPost = new RestResponse();
RestContext.request = reqPost;
RestContext.response = resPost;

ExternalInspectionService.doPost();
System.debug('REST POST RESPONSE CODE: ' + resPost.statusCode);
System.debug('REST POST RESPONSE BODY: ' + resPost.responseBody.toString());
