from odoo.tests.common import TransactionCase


class TestCicdDemoGreeting(TransactionCase):
    def test_message_computed(self):
        greeting = self.env["cicd.demo.greeting"].create({"name": "World"})
        self.assertEqual(greeting.message, "Hello, World!")
