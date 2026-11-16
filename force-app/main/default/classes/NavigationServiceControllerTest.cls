@IsTest
private class NavigationServiceControllerTest {
    @IsTest
    static void testGetObjectNameFromRecordId() {
        // Create test account
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        // Test valid record ID
        String objectName = NavigationServiceController.getObjectNameFromRecordId(acc.Id);
        System.assertEquals('Account', objectName, 'Should return Account for Account record ID');
        
        // Test invalid record ID
        String invalidResult = NavigationServiceController.getObjectNameFromRecordId('invalid');
        System.assertEquals(null, invalidResult, 'Should return null for invalid ID');
        
        // Test null record ID
        String nullResult = NavigationServiceController.getObjectNameFromRecordId(null);
        System.assertEquals(null, nullResult, 'Should return null for null ID');
    }
}