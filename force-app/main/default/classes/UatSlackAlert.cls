/**
 * Posts a short Slack message when a new UAT Feedback item is created, so the team can discuss and triage it.
 * Off unless Kicksaw UAT Setting "Default" has Slack Alerts Enabled. The post goes to the Slack incoming webhook stored
 * in the named credential Kicksaw_UAT_Slack (set up per project; the webhook picks the channel). Either a Slack app
 * incoming webhook (uses "text") or a Workflow Builder "From a webhook" trigger with text variables "bar", "name",
 * "details" and "link" (or only "text", the 0.5.x layout).
 * The post holds the item number, type, severity, story key, submitter and a link: never the tester's text.
 * Runs in the background, so a Slack problem can never block saving an item.
 */
public without sharing class UatSlackAlert implements Queueable, Database.AllowsCallouts {
    public static final String NAMED_CREDENTIAL = 'callout:Kicksaw_UAT_Slack';
    private static final Integer MAX_POSTS = 45;
    @TestVisible private static Boolean enabledOverride;
    @TestVisible private static List<Map<String, String>> sent = new List<Map<String, String>>();

    private final List<Id> itemIds;

    public UatSlackAlert(List<Id> itemIds) {
        this.itemIds = itemIds;
    }

    public static Boolean isEnabled() {
        if (enabledOverride != null) {
            return enabledOverride;
        }
        Kicksaw_UAT_Setting__mdt s = Kicksaw_UAT_Setting__mdt.getInstance('Default');
        return s != null && s.Slack_Alerts_Enabled__c == true;
    }

    /** Called from the trigger after insert. Never throws. */
    public static void enqueueIfEnabled(Set<Id> ids) {
        try {
            if (ids == null || ids.isEmpty() || !isEnabled()) {
                return;
            }
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new UatSlackAlert(new List<Id>(ids)));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'UAT Slack alert not queued: ' + e.getMessage());
        }
    }

    public void execute(QueueableContext ctx) {
        List<UAT_Feedback__c> items = [
            SELECT Id, Name, Type__c, Priority__c, Tested_Story__r.Jira_Key__c, SubmittedBy__r.Name, CreatedBy.Name
            FROM UAT_Feedback__c WHERE Id IN :itemIds ORDER BY Name
        ];
        Integer posted = 0;
        for (UAT_Feedback__c item : items) {
            if (posted == MAX_POSTS) {
                String orgUrl = URL.getOrgDomainUrl().toExternalForm();
                post(payload(priorityBar(null), (items.size() - MAX_POSTS) + ' more items', (items.size() - MAX_POSTS)
                    + ' more new UAT feedback items were created at the same time. Open UAT Review to see them.',
                    orgUrl + '/lightning/o/UAT_Feedback__c/list'));
                break;
            }
            post(message(item));
            posted++;
        }
    }

    /**
     * The webhook body. A Workflow Builder webhook shows every variable as literal text (no Slack markup), so the
     * layout lives in the workflow's message step: {bar} on the first line; then the fixed words "New UAT feedback"
     * linked to {link} (the link button, URL = the variable) followed by {name}; then {details} inside a code block.
     * "text" holds the whole message as plain text for a Slack app incoming webhook or a workflow that uses only "text".
     */
    @TestVisible
    private static Map<String, String> message(UAT_Feedback__c item) {
        String link = URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/UAT_Feedback__c/' + item.Id + '/view';
        String story = item.Tested_Story__r != null ? item.Tested_Story__r.Jira_Key__c : null;
        String who = item.SubmittedBy__r != null ? item.SubmittedBy__r.Name : item.CreatedBy.Name;
        // Labels padded to one width so the values line up in the code block's monospace font.
        String details = row('Type', orNone(item.Type__c)) + '\n'
            + row('Severity', orNone(item.Priority__c)) + '\n'
            + row('Jira Story', orNone(story)) + '\n'
            + row('Submitted By', orNone(who));
        return payload(priorityBar(item.Priority__c), clean(item.Name), details, link);
    }

    private static Map<String, String> payload(String bar, String name, String details, String link) {
        String text = bar + '\n' + (String.isBlank(name) ? '' : 'New UAT feedback ' + name + '\n') + details
            + (String.isBlank(link) ? '' : '\n' + link);
        return new Map<String, String>{
            'text' => text, 'bar' => bar, 'name' => name, 'details' => details, 'link' => link
        };
    }

    @TestVisible
    private static String priorityBar(String priority) {
        String square;
        switch on (priority == null ? '' : priority.toLowerCase()) {
            when 'blocker', 'high' { square = '🟥'; }
            when 'medium' { square = '🟧'; }
            when 'low' { square = '🟩'; }
            when else { square = '⬜'; }
        }
        return square.repeat(8);
    }

    private static String row(String label, String value) {
        return (label + ':').rightPad(14) + value;
    }

    private static String orNone(String s) {
        return String.isBlank(s) ? 'none' : clean(s);
    }

    private static String clean(String s) {
        return s == null ? '' : s.replace('<', '').replace('>', '').replace('`', '\'');
    }

    private static void post(Map<String, String> body) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(10000);
            req.setBody(JSON.serialize(body));
            HttpResponse res = new Http().send(req);
            sent.add(body);
            if (res.getStatusCode() != 200) {
                System.debug(LoggingLevel.WARN, 'UAT Slack alert failed: ' + res.getStatusCode() + ' ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'UAT Slack alert failed: ' + e.getMessage());
        }
    }
}
