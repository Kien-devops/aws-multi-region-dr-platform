import importlib.util
import json
import os
import sys
import types
import unittest


class FakeClient:
    def __init__(self):
        self.calls = []

    def __getattr__(self, name):
        def call(**kwargs):
            self.calls.append((name, kwargs))
            return {}
        return call


class HandlersTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.clients = {}
        boto3 = types.SimpleNamespace(client=lambda name, **kwargs: cls.clients.setdefault(name, FakeClient()))
        botocore = types.ModuleType("botocore")
        botocore.exceptions = types.SimpleNamespace(ClientError=Exception)
        sys.modules["boto3"] = boto3
        sys.modules["botocore"] = botocore
        sys.modules["botocore.exceptions"] = botocore.exceptions
        os.environ["LOCK_TABLE_NAME"] = "locks"
        os.environ["APPROVAL_TABLE_NAME"] = "approvals"
        path = os.path.join(os.path.dirname(__file__), "..", "lambda_src", "handlers.py")
        spec = importlib.util.spec_from_file_location("dr_handlers", path)
        cls.handlers = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.handlers)

    def test_validate_requires_raw_event(self):
        with self.assertRaises(RuntimeError):
            self.handlers.validate({"eventId": "e1", "dryRun": False}, None)

    def test_dry_run_is_fail_safe_and_does_not_promote(self):
        event = {"eventId": "e1", "dryRun": True, "failureSignals": ["app", "storage"], "failureConfirmed": True, "primaryFenced": True, "tokyoWritable": True}
        value = self.handlers.validate(event, None)
        value = self.handlers.verify_failure(value, None)
        value = self.handlers.fencing(value, None)
        value = self.handlers.snapmirror(value, None)
        value = self.handlers.promotion(value, None)
        value = self.handlers.promotion_verify(value, None)
        self.assertEqual(value["promotion"], "simulated")
        self.assertTrue(value["tokyoWritable"])

    def test_live_promotion_is_disabled_by_default(self):
        with self.assertRaisesRegex(RuntimeError, "PromotionDisabled"):
            self.handlers.promotion({"correlationId": "e1", "primaryFenced": True, "approval": {"approved": True}}, None)

    def test_promotion_uses_ontap_patch_state_actions(self):
        self.handlers._ontap_secret = lambda: {"host": "https://ontap.local", "username": "u", "password": "p"}
        calls = []
        self.handlers._relationship = lambda data: {"uuid": "rel/1"}
        self.handlers._ontap_request = lambda path, method="GET", body=None: calls.append((path, method, body)) or {"job": {"uuid": "job-1"}}
        os.environ["ENABLE_PROMOTION"] = "true"
        result = self.handlers.promotion({"correlationId": "e1", "primaryFenced": True, "planned": True, "approval": {"approved": True}}, None)
        self.assertEqual(result["promotion"]["job"], "job-1")
        self.assertEqual(calls, [
            ("/api/snapmirror/relationships/rel%2F1", "PATCH", {"state": "paused"}),
            ("/api/snapmirror/relationships/rel%2F1", "PATCH", {"state": "broken_off"}),
        ])
        os.environ["ENABLE_PROMOTION"] = "false"

    def test_lambda_handler_dispatches_by_function_name(self):
        os.environ["FUNCTION_NAME"] = "validate"
        with self.assertRaises(RuntimeError):
            self.handlers.lambda_handler({"eventId": "e1", "dryRun": False}, None)
        os.environ.pop("FUNCTION_NAME", None)

    def test_lambda_handler_maps_failure_alias(self):
        os.environ["FUNCTION_NAME"] = "failure"
        with self.assertRaisesRegex(RuntimeError, "FailureNotConfirmed"):
            self.handlers.lambda_handler({"failureConfirmed": False, "failureSignals": []}, None)
        os.environ.pop("FUNCTION_NAME", None)

    def test_promotion_verify_requires_rw_online_destination(self):
        self.handlers._ontap_request = lambda path, method="GET", body=None: {"state": "success"} if path.startswith("/api/cluster/jobs/") else {"records": [{"type": "dp", "state": "online"}]}
        with self.assertRaisesRegex(RuntimeError, "DestinationNotWritable"):
            self.handlers.promotion_verify({"promotion": {"job": "job-1"}, "destinationPath": "svm:volume"}, None)

    def test_approval_callback_marks_record_consumed_before_resume(self):
        class ApprovalClient(FakeClient):
            def update_item(self, **kwargs):
                self.calls.append(("update_item", kwargs))
                return {"Attributes": {"TaskToken": {"S": "opaque"}, "ApprovalState": {"S": "CONSUMED"}}}

        self.handlers._ddb = ApprovalClient()
        self.handlers._sfn = FakeClient()
        result = self.handlers.approval_callback({"approvalId": "a1", "decision": "approve"}, None)
        self.assertTrue(result["accepted"])
        self.assertEqual(self.handlers._ddb.calls[0][0], "update_item")
        self.assertEqual(self.handlers._sfn.calls[0][0], "send_task_success")

    def test_duplicate_event_is_rejected_by_deduplication_gate(self):
        self.handlers._ddb = FakeClient()
        self.handlers._ddb.put_item = lambda **kwargs: (_ for _ in ()).throw(Exception("ConditionalCheckFailedException"))
        with self.assertRaises(Exception):
            self.handlers.lock({"Payload": {"eventId": "e1", "correlationId": "c1"}}, None)

    def test_state_machine_has_required_safety_states(self):
        with open(os.path.join(os.path.dirname(__file__), "..", "state_machine.asl.json.tftpl"), encoding="utf-8") as source:
            text = source.read()
        for state in ["ValidateEvent", "AcquireLock", "RequestApproval", "VerifyPrimaryFencing", "CheckSnapMirrorStatus", "PromoteTokyo", "VerifyFileService", "SwitchTraffic", "FailureHandler", "ReleaseLock"]:
            self.assertIn(f'"{state}"', text)
        self.assertIn("waitForTaskToken", text)


if __name__ == "__main__":
    unittest.main()
