public with sharing class NavigationServiceController {
    @AuraEnabled
    public static String getObjectNameFromRecordId(String recordId) {
        try {
            if (String.isBlank(recordId) || recordId.length() < 3) {
                return null;
            }
            
            Id convertedId = Id.valueOf(recordId);
            return convertedId.getSObjectType().getDescribe().getName();
        } catch (Exception e) {
            return null;
        }
    }
}