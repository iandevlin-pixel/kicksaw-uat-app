trigger UatFeedbackSlackAlert on UAT_Feedback__c (after insert) {
    UatSlackAlert.enqueueIfEnabled(Trigger.newMap.keySet());
}
