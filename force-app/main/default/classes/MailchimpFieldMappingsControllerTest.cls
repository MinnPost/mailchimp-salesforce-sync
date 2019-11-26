@isTest
private class MailchimpFieldMappingsControllerTest {
    class MailchimpApiMock implements HttpCalloutMock {
        public String respBody;

        public MailchimpApiMock() {
            this('{}');
        }

        public MailchimpApiMock(String respBody) {
            this.respBody = respBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody(respBody);
            return resp;
        }
    }

    @isTest static void testProperties() {
        Test.startTest();
        MailchimpFieldMappingsController controller =
            new MailchimpFieldMappingsController();

        System.assert(controller.fieldMappings != null);
        System.assert(controller.fieldMappings.size() >= 3);

        System.assert(controller.newMapping != null);

        System.assertEquals(
            new List<SelectOption>{
                new SelectOption('Account', 'Account'),
                new SelectOption('Contact', 'Contact')
            },
            controller.objChoices
        );

        System.assert(controller.fieldChoices != null);
        System.assert(controller.fieldChoices.size() > 0);

        System.assert(controller.directionChoices != null);
        System.assertEquals(3, controller.directionChoices.size());

        Test.stopTest();
    }

    @isTest static void testAttrFieldTagOptions() {
        Test.setMock(
            HttpCalloutMock.class,
            new MailchimpApiMock('{"merge_fields":[],"segments":[],"total_items":0}')
        );
        Test.startTest();
        MailchimpFieldMappingsController controller =
            new MailchimpFieldMappingsController();

        System.assert(controller.attrFieldTagOptions != null);

        Test.stopTest();
    }
}
