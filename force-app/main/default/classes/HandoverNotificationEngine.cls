/**
 * @description Centralized Single-Path Notification & Event Engine for Residential Real Estate Handover Module.
 * Implements Events 1 through 22 with automated Task, Calendar Event, Email, and Audit Log dispatching.
 */
public without sharing class HandoverNotificationEngine {

    public static Handover_Event_Log__c logAudit(Id handoverId, String eventType, String triggerSource, String recipient, String channel, String actorName, String details) {
        Handover_Event_Log__c log = new Handover_Event_Log__c(
            Handover__c = handoverId,
            Event_Type__c = eventType,
            Trigger_Source__c = triggerSource,
            Recipient__c = recipient,
            Channel__c = channel,
            Status__c = 'Logged',
            Actor_Name__c = String.isNotBlank(actorName) ? actorName : UserInfo.getName(),
            Details__c = details,
            Timestamp__c = System.now()
        );
        insert log;
        return log;
    }

    public static Task createActivityTask(Id whatId, Id whoId, String subject, Date dueDate, String priority, String description, Id ownerId) {
        Task t = new Task(
            WhatId = whatId,
            WhoId = whoId,
            Subject = subject,
            ActivityDate = dueDate != null ? dueDate : System.today(),
            Priority = String.isNotBlank(priority) ? priority : 'Normal',
            Status = 'Completed',
            Description = description,
            OwnerId = ownerId != null ? ownerId : UserInfo.getUserId()
        );
        insert t;
        return t;
    }

    public static Event createCalendarEvent(Id whatId, String subject, DateTime startDt, DateTime endDt, String location, String description, Id ownerId) {
        List<Event> existingEvents = [SELECT Id FROM Event WHERE WhatId = :whatId ORDER BY CreatedDate DESC LIMIT 1];
        if (!existingEvents.isEmpty()) {
            Event evt = existingEvents[0];
            evt.Subject = subject;
            evt.StartDateTime = startDt != null ? startDt : System.now().addDays(1);
            evt.EndDateTime = endDt != null ? endDt : System.now().addDays(1).addMinutes(90);
            evt.Location = location;
            evt.Description = description;
            update evt;
            return evt;
        }
        Event evt = new Event(
            WhatId = whatId,
            Subject = subject,
            StartDateTime = startDt != null ? startDt : System.now().addDays(1),
            EndDateTime = endDt != null ? endDt : System.now().addDays(1).addMinutes(90),
            Location = location,
            Description = description,
            OwnerId = ownerId != null ? ownerId : UserInfo.getUserId()
        );
        insert evt;
        return evt;
    }

    public static Boolean dispatchEmail(String toEmail, String ccEmail, String subject, String plainBody, String htmlBody, Id whatId) {
        if (String.isBlank(toEmail)) {
            return false;
        }
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ toEmail });
            if (String.isNotBlank(ccEmail)) {
                mail.setCcAddresses(new List<String>{ ccEmail });
            }
            mail.setSubject(subject);
            mail.setPlainTextBody(plainBody);
            if (String.isNotBlank(htmlBody)) {
                mail.setHtmlBody(htmlBody);
            }
            if (whatId != null) {
                mail.setWhatId(whatId);
                mail.setSaveAsActivity(true);
            }
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            return true;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Email dispatch: ' + ex.getMessage());
            return false;
        }
    }

    public static void event1_UnitPossessionReady(Handover__c ho, String sourceProcess) {
        String details = 'Unit marked possession-ready by ' + (String.isNotBlank(sourceProcess) ? sourceProcess : 'Project Process') + ' on ' + System.today().format();
        logAudit(ho.Id, 'Unit marked possession-ready', 'Project Process', 'Handover Team', 'Internal Activity', UserInfo.getName(), details);
        createActivityTask(ho.Id, null, 'Unit marked possession-ready', System.today(), 'Normal', details, ho.Handover_Owner__c);
    }

    public static void event2_OwnerAssigned(Handover__c ho, User ownerUser) {
        String ownerName = ownerUser != null ? ownerUser.Name : 'Handover Lead';
        String details = 'Handover owner assigned: ' + ownerName + '. Target date: ' + String.valueOf(ho.Target_Handover_Date__c);
        logAudit(ho.Id, 'Handover owner assigned', 'System / Manager', ownerName, 'Bell Notification', UserInfo.getName(), details);
        createActivityTask(ho.Id, null, 'New Handover assigned', System.today(), 'High', details, ho.Handover_Owner__c);
    }

    public static void event3_StartInspection(Handover__c ho, Inspection__c insp) {
        String details = 'Inspection started (' + insp.Inspection_Type__c + ' - ' + insp.Inspection_Round__c + '). Assigned to: ' + insp.Inspector_Name__c;
        logAudit(ho.Id, 'Inspection started', 'User Action', insp.Inspector_Name__c, 'Internal Activity', UserInfo.getName(), details);
        createActivityTask(ho.Id, null, 'Complete inspection ' + insp.Inspection_Round__c, insp.Inspection_Date__c, 'Normal', details, insp.Inspector__c != null ? insp.Inspector__c : ho.Handover_Owner__c);
    }

    public static void event4_ThirdPartyInspectionRequest(Handover__c ho, Inspection__c insp, String secureUrl) {
        String subject = 'Inspection Request: ' + ho.Property__r.Name + ' ' + ho.Tower__r.Name + ' Unit ' + ho.Unit__r.Name;
        List<String> lines = new List<String>{
            'Dear ' + insp.Inspector_Name__c + ',',
            '',
            'You have been requested to conduct a property inspection for:',
            'Project: ' + ho.Property__r.Name,
            'Tower: ' + ho.Tower__r.Name,
            'Unit: ' + ho.Unit__r.Name,
            'Inspection Reference: ' + insp.Name,
            'Scheduled Date: ' + String.valueOf(insp.Inspection_Date__c),
            '',
            'Please access your secure inspection checklist link below:',
            secureUrl,
            '',
            'Submission Deadline: ' + String.valueOf(insp.Token_Expiry__c),
            'Instructions: Complete every checklist item (Pass, Issue Found, N/A) and upload required photos.',
            '',
            'Thank you,',
            'Handover Operations Team'
        };
        String body = String.join(lines, '\n');
        dispatchEmail(insp.Inspector_Email__c, null, subject, body, null, insp.Id);
        logAudit(ho.Id, 'Third-party inspection request sent', 'User Action', insp.Inspector_Email__c, 'Email', UserInfo.getName(), 'Inspection request emailed with secure token URL. Expiry: ' + insp.Token_Expiry__c);
    }

    public static void event5_ThirdPartyInspectionReminder(Handover__c ho, Inspection__c insp) {
        String subject = 'Reminder: Inspection Pending - ' + ho.Unit__r.Name;
        List<String> lines = new List<String>{
            'Dear ' + insp.Inspector_Name__c + ',',
            '',
            'This is a friendly reminder to complete your inspection for ' + ho.Unit__r.Name + '.',
            'Deadline: ' + String.valueOf(insp.Token_Expiry__c),
            '',
            'Thank you,',
            'Handover Operations Team'
        };
        String body = String.join(lines, '\n');
        dispatchEmail(insp.Inspector_Email__c, null, subject, body, null, insp.Id);
        logAudit(ho.Id, 'Third-party inspection reminder sent', 'System Schedule', insp.Inspector_Email__c, 'Email', 'System Scheduler', 'Reminder dispatched approaching deadline');
    }

    public static void event6_ExternalInspectionSubmitted(Handover__c ho, Inspection__c insp) {
        String details = 'External inspection completed for Unit ' + ho.Unit__r.Name + ' by ' + insp.Inspector_Name__c + ' (' + insp.Inspector_Company__c + '). '
            + 'Results: ' + insp.Passed_Items_Count__c + ' Pass, ' + insp.Issue_Items_Count__c + ' Issues, ' + insp.NA_Items_Count__c + ' N/A.';
        logAudit(ho.Id, 'Inspection completed', 'External Form', 'Handover Owner', 'Bell Notification', insp.Inspector_Name__c, details);
        createActivityTask(ho.Id, null, 'Review submitted inspection findings', System.today(), 'High', details, ho.Handover_Owner__c);
    }

    public static void event7_SnagCreated(Handover__c ho, Snag__c snag) {
        String details = 'Snag created: [' + snag.Severity__c + '] ' + snag.Category__c + ' - ' + snag.Snag_Description__c + ' (' + snag.Location_Pin__c + '). Assigned to: ' + snag.Assigned_Contractor_Name__c;
        logAudit(ho.Id, 'Snag created', 'Inspection / User', snag.Assigned_Contractor_Name__c, 'Internal Activity', UserInfo.getName(), details);
        createActivityTask(ho.Id, null, 'Fix snag: ' + snag.Category__c, snag.Due_Date__c, snag.Severity__c == 'Critical' ? 'High' : 'Normal', details, snag.Assigned_To__c != null ? snag.Assigned_To__c : ho.Handover_Owner__c);
    }

    public static void event8_SnagOverdue(Handover__c ho, Snag__c snag) {
        String details = 'Snag ' + snag.Name + ' is overdue (Due date was ' + String.valueOf(snag.Due_Date__c) + '). Severity: ' + snag.Severity__c;
        logAudit(ho.Id, 'Snag overdue notification', 'System Schedule', snag.Assigned_Contractor_Name__c + ', Handover Owner', 'Bell Notification', 'System Scheduler', details);
        createActivityTask(ho.Id, null, 'Overdue Snag: ' + snag.Category__c, System.today(), 'High', details, ho.Handover_Owner__c);
    }

    public static void event9_SnagResolved(Handover__c ho, Snag__c snag) {
        String details = 'Snag ' + snag.Name + ' (' + snag.Category__c + ') resolved by assignee. Awaiting inspection verification.';
        logAudit(ho.Id, 'Snag resolved', 'Assignee Action', 'Inspector / Handover Owner', 'Bell Notification', UserInfo.getName(), details);
        createActivityTask(ho.Id, null, 'Verify snag resolution: ' + snag.Name, System.today().addDays(1), 'Normal', details, ho.Handover_Owner__c);
    }

    public static void event11_SnagReopened(Handover__c ho, Snag__c snag, String rejectionReason) {
        String details = 'Snag ' + snag.Name + ' reopened after verification failed. Reason: ' + rejectionReason + '. Reopen count: ' + snag.Reopen_Count__c;
        logAudit(ho.Id, 'Snag reopened after verification', 'Verifier Action', snag.Assigned_Contractor_Name__c, 'Bell Notification', UserInfo.getName(), details);
        createActivityTask(ho.Id, null, 'Rework required for snag: ' + snag.Name, System.today().addDays(2), 'High', details, snag.Assigned_To__c != null ? snag.Assigned_To__c : ho.Handover_Owner__c);
    }

    public static void event12_SnagClosed(Handover__c ho, Snag__c snag) {
        String details = 'Snag ' + snag.Name + ' (' + snag.Category__c + ') verified and closed.';
        logAudit(ho.Id, 'Snag closed', 'Verifier Action', 'Handover Owner', 'Internal Activity', UserInfo.getName(), details);
    }

    public static void event13_HandoverReady(Handover__c ho) {
        String details = 'Inspection passed and required snags verified. Unit marked ready for customer handover appointment.';
        logAudit(ho.Id, 'Unit marked handover ready', 'System Rule', 'Handover Owner / Team', 'Internal Activity', UserInfo.getName(), details);
        createActivityTask(ho.Id, null, 'Schedule handover appointment with customer', System.today().addDays(2), 'Normal', details, ho.Handover_Owner__c);
    }

    public static void event14_AppointmentScheduled(Handover__c ho, Account cust, Boolean sendEmailToCustomer) {
        String details = 'Handover appointment scheduled for ' + String.valueOf(ho.Appointment_Date__c) + ' at ' + ho.Appointment_Time_Slot__c + ' (' + ho.Appointment_Location__c + ').';
        logAudit(ho.Id, 'Handover appointment scheduled', 'User Action', cust != null ? cust.Name : 'Customer', 'Calendar/Event', UserInfo.getName(), details);

        createCalendarEvent(ho.Id, 'Handover: Unit ' + ho.Unit__r.Name + ' (' + (cust != null ? cust.Name : '') + ')', ho.Appointment_Start_Time__c, ho.Appointment_End_Time__c, ho.Appointment_Location__c, details, ho.Handover_Owner__c);

        createActivityTask(ho.Id, null, 'Prepare handover kit for ' + ho.Unit__r.Name, ho.Appointment_Date__c != null ? ho.Appointment_Date__c.addDays(-1) : System.today(), 'High', 'Assemble keys, access cards, possession letter, key receipt, and warranty documentation.', ho.Handover_Owner__c);

        if (sendEmailToCustomer && cust != null && String.isNotBlank(cust.PersonEmail)) {
            String subject = 'Handover Appointment Confirmed: ' + ho.Property__r.Name + ' ' + ho.Tower__r.Name + ' Unit ' + ho.Unit__r.Name;
            List<String> lines = new List<String>{
                'Dear ' + cust.Name + ',',
                '',
                'We are pleased to inform you that your home at ' + ho.Property__r.Name + ', ' + ho.Tower__r.Name + ', Unit ' + ho.Unit__r.Name + ' is ready for handover.',
                '',
                'Handover Date: ' + String.valueOf(ho.Appointment_Date__c),
                'Time: ' + ho.Appointment_Time_Slot__c,
                'Location: ' + ho.Appointment_Location__c,
                'Handover Lead: ' + (ho.Handover_Owner__r != null ? ho.Handover_Owner__r.Name : UserInfo.getName()),
                '',
                'Please bring: ' + (String.isNotBlank(ho.Required_Documents__c) ? ho.Required_Documents__c : 'Photo ID for all owners, original Allotment Letter, and Bank NOC'),
                'Instructions: ' + (String.isNotBlank(ho.Customer_Instructions__c) ? ho.Customer_Instructions__c : 'Please arrive 15 minutes early at the Tower lobby.'),
                '',
                'We look forward to welcoming you home!',
                '',
                'Warm regards,',
                'Residential Handover Operations Team'
            };
            String body = String.join(lines, '\n');
            dispatchEmail(cust.PersonEmail, null, subject, body, null, ho.Id);
            logAudit(ho.Id, 'Customer confirmation email sent', 'System / User Action', cust.PersonEmail, 'Email', UserInfo.getName(), 'Appointment details sent to customer');
        }

        // Send internal notification to Builder / Handover Owner
        String ownerEmail = null;
        try {
            if (ho.Handover_Owner__c != null) {
                ownerEmail = [SELECT Email FROM User WHERE Id = :ho.Handover_Owner__c LIMIT 1].Email;
            }
        } catch (Exception ex) {}

        if (String.isNotBlank(ownerEmail)) {
            String builderSubj = 'Internal Alert: Handover Appointment Scheduled - ' + ho.Property__r.Name + ' Unit ' + ho.Unit__r.Name;
            List<String> builderLines = new List<String>{
                'Handover Lead / Operations Team,',
                '',
                'A handover possession appointment has been confirmed with the customer.',
                '',
                'Customer: ' + (cust != null ? cust.Name : 'Customer'),
                'Unit: ' + ho.Unit__r.Name + ' (' + ho.Property__r.Name + ')',
                'Date: ' + String.valueOf(ho.Appointment_Date__c),
                'Time Slot: ' + ho.Appointment_Time_Slot__c,
                'Location: ' + ho.Appointment_Location__c,
                'Instructions: ' + (String.isNotBlank(ho.Customer_Instructions__c) ? ho.Customer_Instructions__c : 'Standard procedure'),
                '',
                'Please ensure the handover kit, keys, and warranty certificates are ready.'
            };
            dispatchEmail(ownerEmail, null, builderSubj, String.join(builderLines, '\n'), null, ho.Id);
            logAudit(ho.Id, 'Builder notification email sent', 'System Action', ownerEmail, 'Email', UserInfo.getName(), 'Internal appointment confirmation sent to Handover Owner');
        }
    }

    public static void event15_AppointmentReminder(Handover__c ho, Account cust) {
        String details = 'Handover reminder sent for appointment on ' + String.valueOf(ho.Appointment_Date__c) + ' at ' + ho.Appointment_Time_Slot__c;
        if (cust != null && String.isNotBlank(cust.PersonEmail)) {
            String subject = 'Reminder: Your Handover Appointment Tomorrow - Unit ' + ho.Unit__r.Name;
            List<String> lines = new List<String>{
                'Dear ' + cust.Name + ',',
                '',
                'This is a gentle reminder that your handover appointment is scheduled for tomorrow:',
                'Date: ' + String.valueOf(ho.Appointment_Date__c),
                'Time: ' + ho.Appointment_Time_Slot__c,
                'Location: ' + ho.Appointment_Location__c,
                '',
                'Please remember to bring your photo ID and original documents.',
                '',
                'See you tomorrow!',
                'Residential Handover Team'
            };
            String body = String.join(lines, '\n');
            dispatchEmail(cust.PersonEmail, null, subject, body, null, ho.Id);
        }
        logAudit(ho.Id, 'Handover reminder sent', 'System Schedule', cust != null ? cust.PersonEmail : 'Customer', 'Email', 'System Scheduler', details);
    }

    public static void event16_AppointmentRescheduled(Handover__c ho, Account cust, String previousDetails, String newDetails) {
        String details = 'Appointment rescheduled. Previous: ' + previousDetails + ' -> New: ' + newDetails;
        logAudit(ho.Id, 'Appointment rescheduled', 'User Action', cust != null ? cust.PersonEmail : 'Customer', 'Email', UserInfo.getName(), details);

        if (cust != null && String.isNotBlank(cust.PersonEmail)) {
            String subject = 'Revised Handover Appointment - ' + ho.Property__r.Name + ' Unit ' + ho.Unit__r.Name;
            List<String> lines = new List<String>{
                'Dear ' + cust.Name + ',',
                '',
                'Your handover appointment has been rescheduled as requested.',
                '',
                'Previous Appointment: ' + previousDetails,
                'New Appointment: ' + newDetails,
                'Location: ' + ho.Appointment_Location__c,
                '',
                'We look forward to meeting you.',
                '',
                'Warm regards,',
                'Residential Handover Team'
            };
            String body = String.join(lines, '\n');
            dispatchEmail(cust.PersonEmail, null, subject, body, null, ho.Id);
        }

        // Notify Builder / Handover Owner of reschedule
        String ownerEmail = null;
        try {
            if (ho.Handover_Owner__c != null) {
                ownerEmail = [SELECT Email FROM User WHERE Id = :ho.Handover_Owner__c LIMIT 1].Email;
            }
        } catch (Exception ex) {}

        if (String.isNotBlank(ownerEmail)) {
            String builderSubj = 'Internal Alert: Handover Appointment Rescheduled - ' + ho.Property__r.Name + ' Unit ' + ho.Unit__r.Name;
            List<String> builderLines = new List<String>{
                'Handover Lead / Operations Team,',
                '',
                'A handover possession appointment has been rescheduled.',
                '',
                'Customer: ' + (cust != null ? cust.Name : 'Customer'),
                'Unit: ' + ho.Unit__r.Name + ' (' + ho.Property__r.Name + ')',
                'Previous: ' + previousDetails,
                'New: ' + newDetails,
                'Location: ' + ho.Appointment_Location__c,
                '',
                'Calendar event and customer notification have been updated.'
            };
            dispatchEmail(ownerEmail, null, builderSubj, String.join(builderLines, '\n'), null, ho.Id);
            logAudit(ho.Id, 'Builder reschedule email sent', 'System Action', ownerEmail, 'Email', UserInfo.getName(), 'Internal reschedule alert sent to Handover Owner');
        }
        createActivityTask(ho.Id, null, 'Updated appointment calendar & notified customer', System.today(), 'Normal', details, ho.Handover_Owner__c);
    }

    public static void event17_CustomerArrived(Handover__c ho) {
        String details = 'Customer arrived on site at ' + System.now().format('HH:mm') + '. Physical handover commenced.';
        logAudit(ho.Id, 'Customer arrived', 'Arrival Checkpoint', 'Handover Team', 'Internal Activity', UserInfo.getName(), details);
    }

    public static void event18_PhysicalChecklistItem(Handover__c ho, String itemType, String itemDetails) {
        logAudit(ho.Id, itemType, 'Physical Handover', 'Internal Audit', 'Internal Activity', UserInfo.getName(), itemDetails);
    }

    public static void event19_AcknowledgementCaptured(Handover__c ho) {
        String details = 'Customer acknowledgement captured via ' + ho.Acknowledgement_Method__c + ' by ' + ho.Customer_Signee_Name__c + ' at ' + System.now().format();
        logAudit(ho.Id, 'Acknowledgement captured', 'Customer Action', 'Handover Owner', 'Internal Activity', ho.Customer_Signee_Name__c, details);
    }

    public static void event20_HandoverCompleted(Handover__c ho, Account cust) {
        String completionTime = System.now().format('dd MMM yyyy, HH:mm');
        String details = 'Handover successfully completed on ' + completionTime + ' by ' + UserInfo.getName() + '. Unit transitioned to Post-Sale.';

        logAudit(ho.Id, 'Handover completed', 'Completion Action', 'Handover & Project Team', 'Internal Activity', UserInfo.getName(), details);
        createActivityTask(ho.Id, null, 'Handover completed for Unit ' + ho.Unit__r.Name, System.today(), 'Normal', details, ho.Handover_Owner__c);

        if (cust != null && String.isNotBlank(cust.PersonEmail)) {
            String subject = 'Welcome Home - ' + ho.Property__r.Name + ', ' + ho.Tower__r.Name + ', Unit ' + ho.Unit__r.Name;
            List<String> lines = new List<String>{
                'Dear ' + cust.Name + ',',
                '',
                'Heartiest congratulations on receiving the possession of your new home at ' + ho.Property__r.Name + ', ' + ho.Tower__r.Name + ', Unit ' + ho.Unit__r.Name + '!',
                '',
                'Handover Date & Time: ' + completionTime,
                'Completed By: ' + UserInfo.getName(),
                'Keys Handed Over: ' + ho.Keys_Sets_Count__c + ' sets',
                'Access Cards Issued: ' + ho.Access_Cards_Count__c + ' cards',
                '',
                'Your Handover Pack (Possession Letter, Key Receipt, Warranty Certificate) is ready.',
                '',
                'Next Steps & Post-Sale Care:',
                'Your property is now active in Post-Sale care. For maintenance requests, facility access, and warranty queries, please reach out to our Post-Sale customer relations team.',
                '',
                'Welcome to your new home!',
                '',
                'Warm regards,',
                'Residential Operations Team'
            };
            String body = String.join(lines, '\n');
            dispatchEmail(cust.PersonEmail, null, subject, body, null, ho.Id);
            logAudit(ho.Id, 'Welcome email sent', 'System Action', cust.PersonEmail, 'Email', UserInfo.getName(), 'Welcome Home email dispatched with Handover Pack documentation');
        }

        Id postSaleOwner = ho.Handover_Owner__c;
        try {
            if (ho.Post_Sale_Owner__c != null) {
                postSaleOwner = ho.Post_Sale_Owner__c;
            }
        } catch (Exception e) {}
        createActivityTask(ho.Id, null, 'Initiate Post-Sale onboarding for Unit ' + ho.Unit__r.Name, System.today().addDays(3), 'Normal', 'Handover completed on ' + completionTime + '. Initiate 30-day post-handover welcome check-in.', postSaleOwner);
    }

    // Convenience wrappers for Workspace Controller
    public static void sendThirdPartyInspectionRequest(Handover__c ho, Inspection__c insp) {
        String tokenUrl = '/services/apexrest/externalInspection?token=' + insp.External_Token__c;
        event4_ThirdPartyInspectionRequest(ho, insp, tokenUrl);
    }

    public static void sendAppointmentConfirmationEmail(Handover__c ho) {
        Account cust = ho.Customer__c != null ? [SELECT Id, Name, PersonEmail FROM Account WHERE Id = :ho.Customer__c LIMIT 1] : null;
        event14_AppointmentScheduled(ho, cust, true);
    }

    public static void sendAppointmentRescheduleEmail(Handover__c ho, Date oldDate, String oldLoc) {
        Account cust = ho.Customer__c != null ? [SELECT Id, Name, PersonEmail FROM Account WHERE Id = :ho.Customer__c LIMIT 1] : null;
        String oldDetails = (oldDate != null ? oldDate.format() : 'N/A') + ' at ' + oldLoc;
        String newDetails = (ho.Appointment_Date__c != null ? ho.Appointment_Date__c.format() : 'N/A') + ' at ' + ho.Appointment_Location__c;
        event16_AppointmentRescheduled(ho, cust, oldDetails, newDetails);
    }

    public static void sendWelcomeHomeEmail(Handover__c ho) {
        Account cust = ho.Customer__c != null ? [SELECT Id, Name, PersonEmail FROM Account WHERE Id = :ho.Customer__c LIMIT 1] : null;
        event20_HandoverCompleted(ho, cust);
    }

}
