from odoo import fields, models


class CicdDemoGreeting(models.Model):
    _name = "cicd.demo.greeting"
    _description = "CI/CD Demo Greeting"

    name = fields.Char(required=True)
    message = fields.Char(compute="_compute_message")

    def _compute_message(self):
        for record in self:
            record.message = f"Hello, {record.name}!"
