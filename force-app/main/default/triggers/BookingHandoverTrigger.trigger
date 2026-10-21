trigger BookingHandoverTrigger on Booking__c (after insert, after update) {
    Set<Id> candidateBookingIds = new Set<Id>();
    for (Booking__c b : Trigger.new) {
        Boolean isClosedOrConfirmed = (b.Status__c == 'Closed Won' || b.Status__c == 'Confirmed');
        if (Trigger.isInsert) {
            if (isClosedOrConfirmed) {
                candidateBookingIds.add(b.Id);
            }
        } else {
            Booking__c oldB = Trigger.oldMap.get(b.Id);
            if (isClosedOrConfirmed && (oldB.Status__c != b.Status__c || b.Handover__c == null)) {
                candidateBookingIds.add(b.Id);
            }
        }
    }
    if (!candidateBookingIds.isEmpty()) {
        BookingHandoverHandler.initializeHandovers(candidateBookingIds);
    }
}
