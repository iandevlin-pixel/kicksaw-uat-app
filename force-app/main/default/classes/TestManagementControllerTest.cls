@IsTest(SeeAllData=false)
public class TestManagementControllerTest {
    @TestSetup
    static void setupTestData() {
        // Create test user
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User'];
        User testUser = new User(
            Alias = 'tuser',
            Email = 'testuser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser@testorg.com' + System.currentTimeMillis()
        );
        insert testUser;

        // Create test cases
        List<TestCase__c> testCases = new List<TestCase__c>();
        for(Integer i = 0; i < 3; i++) {
            testCases.add(new TestCase__c(
                Name = 'Test Case ' + i,
                Status__c = 'Not Complete',
                Persona__c = 'Test Persona'
            ));
        }
        insert testCases;
    }

    @IsTest
    static void testGetOpenTestCases() {
        // Create a completed test case (should not be returned)
        TestCase__c completedCase = new TestCase__c(
            Name = 'Completed Test Case',
            Status__c = 'Complete',
            Persona__c = 'Test Persona'
        );
        insert completedCase;

        Test.startTest();
        List<TestCase__c> openTestCases = TestManagementController.getOpenTestCases();
        Test.stopTest();

        System.assertEquals(3, openTestCases.size(), 'Should return only non-completed test cases');
        for(TestCase__c tc : openTestCases) {
            System.assertNotEquals('Complete', tc.Status__c, 'Should not return completed test cases');
        }
    }

    @IsTest
    static void testCreateTestCase() {
        Map<String, Object> testCaseFields = new Map<String, Object>{
            'Name' => 'New Test Case',
            'Persona__c' => 'Test Persona',
            'Status__c' => 'Not Complete'
        };

        Test.startTest();
        Id testCaseId = TestManagementController.createTestCase(testCaseFields);
        Test.stopTest();

        TestCase__c createdCase = [SELECT Id, Name, Persona__c FROM TestCase__c WHERE Id = :testCaseId];
        System.assertEquals('New Test Case', createdCase.Name, 'Test case name should match');
        System.assertEquals('Test Persona', createdCase.Persona__c, 'Test case persona should match');
    }

    @IsTest
    static void testCreateNewTestRun() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@testorg.com' LIMIT 1];

        Test.startTest();
        Id testRunId = TestManagementController.createNewTestRun(testUser.Id);
        Test.stopTest();

        TestRun__c createdRun = [SELECT Id, Tester__c, Status__c FROM TestRun__c WHERE Id = :testRunId];
        System.assertEquals(testUser.Id, createdRun.Tester__c, 'Tester should be assigned');
        System.assertEquals('Not Complete', createdRun.Status__c, 'Status should be Not Complete');
    }

    @IsTest
    static void testCreateNewTestRunWithBlankTester() {
        Test.startTest();
        String errorMessage;
        try {
            TestManagementController.createNewTestRun(null);
            System.assert(false, 'Should have thrown an exception');
        } catch (Exception e) {
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        System.assert(String.isNotBlank(errorMessage), 'Error message should not be blank');
    }

    @IsTest
    static void testCreateNewTestRunCases() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@testorg.com' LIMIT 1];
        List<TestCase__c> testCases = [SELECT Id FROM TestCase__c LIMIT 2];
        
        // Create test run
        Id testRunId = TestManagementController.createNewTestRun(testUser.Id);
        List<Id> testCaseIds = new List<Id>();
        for(TestCase__c tc : testCases) {
            testCaseIds.add(tc.Id);
        }

        Test.startTest();
        TestManagementController.createNewTestRunCases(testRunId, testCaseIds);
        Test.stopTest();

        List<TestRunCase__c> createdCases = [SELECT Id, RunOrder__c FROM TestRunCase__c WHERE TestRun__c = :testRunId ORDER BY RunOrder__c];
        System.assertEquals(2, createdCases.size(), 'Should have created 2 test run cases');
        System.assertEquals(1, createdCases[0].RunOrder__c, 'First case should have order 1');
        System.assertEquals(2, createdCases[1].RunOrder__c, 'Second case should have order 2');
    }

    @IsTest
    static void testGetTestRunsWithCasesWhereTesterIsNull() {
        // Create test run without tester
        TestRun__c testRun = new TestRun__c(Status__c = 'Not Complete');
        
        Test.startTest();
        insert testRun;

        // Create test run cases
        List<TestCase__c> testCases = [SELECT Id FROM TestCase__c LIMIT 2];
        List<TestRunCase__c> testRunCases = new List<TestRunCase__c>();
        for(Integer i = 0; i < testCases.size(); i++) {
            testRunCases.add(new TestRunCase__c(
                TestRun__c = testRun.Id,
                TestCase__c = testCases[i].Id,
                RunOrder__c = i + 1
            ));
        }
        insert testRunCases;

        List<TestRun__c> testRuns = TestManagementController.getTestRunsWithCasesWhereTesterIsNull();
        Test.stopTest();

        System.assertEquals(1, testRuns.size(), 'Should return one test run');
        System.assertEquals(2, testRuns[0].TestRunCases__r.size(), 'Should have 2 test run cases');
    }

    @IsTest
    static void testCloneTestRun() {
        // Create original test run
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@testorg.com' LIMIT 1];
        Id testRunId = TestManagementController.createNewTestRun(testUser.Id);
        
        // Add test cases to original run
        List<TestCase__c> testCases = [SELECT Id FROM TestCase__c LIMIT 2];
        List<Id> testCaseIds = new List<Id>();
        for(TestCase__c tc : testCases) {
            testCaseIds.add(tc.Id);
        }
        TestManagementController.createNewTestRunCases(testRunId, testCaseIds);

        Test.startTest();
        TestRun__c clonedRun = TestManagementController.cloneTestRun(testRunId);
        Test.stopTest();

        List<TestRunCase__c> clonedCases = [SELECT Id FROM TestRunCase__c WHERE TestRun__c = :clonedRun.Id];
        System.assertEquals(2, clonedCases.size(), 'Cloned run should have same number of test cases');
    }

    @IsTest
    static void testSearchUsers() {
        User testUser = [SELECT Id, Name FROM User WHERE Email = 'testuser@testorg.com' LIMIT 1];

        Test.startTest();
        List<User> foundUsers = TestManagementController.searchUsers('Testing');
        Test.stopTest();

        System.assert(!foundUsers.isEmpty(), 'Should find at least one user');
        System.assertEquals(testUser.Id, foundUsers[0].Id, 'Should find the test user');
    }

    @IsTest
    static void testAssignTesterToTestRun() {
        // Create test run with required fields
        TestRun__c testRun = new TestRun__c(
            Status__c = 'Not Complete'
        );
        
        Test.startTest();
        insert testRun;
        
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@testorg.com' LIMIT 1];
        TestManagementController.assignTesterToTestRun(testRun.Id, testUser.Id);
        Test.stopTest();

        TestRun__c updatedRun = [SELECT Tester__c FROM TestRun__c WHERE Id = :testRun.Id];
        System.assertEquals(testUser.Id, updatedRun.Tester__c, 'Tester should be assigned to test run');
    }

    @IsTest
    static void testUpdateRunOrder() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@testorg.com' LIMIT 1];
        List<TestCase__c> cases = [SELECT Id FROM TestCase__c ORDER BY Name];
        Id runId = TestManagementController.createNewTestRun(testUser.Id);
        TestManagementController.createNewTestRunCases(runId, new List<Id>{ cases[0].Id, cases[1].Id });

        Test.startTest();
        TestManagementController.updateRunOrder(new List<TestRunCase__c>{
            new TestRunCase__c(TestRun__c = runId, TestCase__c = cases[0].Id, RunOrder__c = 2),
            new TestRunCase__c(TestRun__c = runId, TestCase__c = cases[1].Id, RunOrder__c = 1)
        });
        Test.stopTest();

        TestRunCase__c first = [SELECT RunOrder__c FROM TestRunCase__c WHERE TestRun__c = :runId AND TestCase__c = :cases[0].Id];
        System.assertEquals(2, first.RunOrder__c, 'Run order should be updated');
    }

    @IsTest
    static void testAssignTesters() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@testorg.com' LIMIT 1];
        Id runId = TestManagementController.createNewTestRun(testUser.Id);

        Test.startTest();
        TestManagementController.assignTesters(runId, new List<Id>{ testUser.Id, UserInfo.getUserId() });
        Boolean failed = false;
        try {
            TestManagementController.assignTesters(testUser.Id, new List<Id>{ testUser.Id });
        } catch (AuraHandledException e) {
            failed = true;
        }
        Test.stopTest();

        System.assertEquals(3, [SELECT COUNT() FROM TestRun__c], 'One new run per tester');
        System.assert(failed, 'Unknown test run is rejected');
    }

    @IsTest
    static void testCloneTestRunError() {
        Boolean failed = false;
        try {
            TestManagementController.cloneTestRun(UserInfo.getUserId());
        } catch (AuraHandledException e) {
            failed = true;
        }
        System.assert(failed, 'Cloning a missing test run is rejected');
    }
}
