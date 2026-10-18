import base64
import hashlib
import json
import os
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

import boto3
from botocore.exceptions import ClientError

LOCK_TABLE = os.environ.get("LOCK_TABLE_NAME", "")
APPROVAL_TABLE = os.environ.get("APPROVAL_TABLE_NAME", "")
NOTIFICATION_TOPIC_ARN = os.environ.get("NOTIFICATION_TOPIC_ARN", "")
TOPIC_ARN = NOTIFICATION_TOPIC_ARN
SOURCE_PATH = os.environ.get("SOURCE_PATH", "dr-sg-svm:drdata")
DESTINATION_PATH = os.environ.get("DESTINATION_PATH", "dr-tokyo-svm:dr_data_dr")

_ssl_ctx = ssl._create_unverified_context()

_ddb = boto3.client("dynamodb")
_sns = boto3.client("sns")
_sfn = boto3.client("stepfunctions")
_ga = boto3.client("globalaccelerator", region_name="us-west-2")


def _ontap_secret():
    arn = os.environ.get("ONTAP_SECRET_ARN", "")
    if not arn:
        _fail("OntapSecretMissing", "ONTAP_SECRET_ARN is required for live inspection")
    secret = boto3.client("secretsmanager").get_secret_value(SecretId=arn)
    value = json.loads(secret.get("SecretString", "{}"))
    if not value.get("host") or not value.get("username") or not value.get("password"):
        _fail("OntapSecretInvalid", "ONTAP secret must contain host, username, and password")
    return value


def _gitops_secret():
    arn = os.environ.get("GITOPS_SECRET_ARN", "")
    if not arn:
        _fail("GitOpsSecretMissing", "GITOPS_SECRET_ARN is required for live GitOps updates")
    value = json.loads(boto3.client("secretsmanager").get_secret_value(SecretId=arn).get("SecretString", "{}"))
    required = ["token", "owner", "repo", "path"]
    if any(not value.get(key) for key in required):
        _fail("GitOpsSecretInvalid", "GitOps secret is missing required fields")
    return value


def _github_request(secret, method, path, body=None, allow_not_found=False):
    request = urllib.request.Request(f"https://api.github.com{path}", method=method, data=json.dumps(body).encode() if body is not None else None, headers={"Accept": "application/vnd.github+json", "Authorization": f"Bearer {secret['token']}", "X-GitHub-Api-Version": "2022-11-28", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.loads(response.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        if allow_not_found and exc.code == 404:
            return None
        _fail("GitOpsApiError", f"HTTP {exc.code}")


def _argocd_request(secret, path):
    server = secret.get("argocd_server", "").rstrip("/")
    token = secret.get("argocd_token", "")
    if not server or not token:
        _fail("ArgoCdSecretInvalid", "argocd_server and argocd_token are required")
    request = urllib.request.Request(
        server + path,
        headers={"Accept": "application/json", "Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.loads(response.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        _fail("ArgoCdApiError", f"HTTP {exc.code}")
    except (urllib.error.URLError, TimeoutError) as exc:
        _fail("ArgoCdApiUnavailable", type(exc).__name__)


def _ontap_request(path, method="GET", body=None):
    secret = _ontap_secret()
    request = urllib.request.Request(secret["host"].rstrip("/") + path, method=method, data=json.dumps(body).encode() if body is not None else None, headers={"Accept": "application/json", "Content-Type": "application/json"})
    token = (f'{secret["username"]}:{secret["password"]}').encode()
    request.add_header("Authorization", "Basic " + base64.b64encode(token).decode())
    try:
        with urllib.request.urlopen(request, timeout=15, context=_ssl_ctx) as response:
            return json.loads(response.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        _fail("OntapApiError", f"HTTP {exc.code}")
    except (urllib.error.URLError, TimeoutError) as exc:
        _fail("OntapApiUnavailable", type(exc).__name__)


def _relationship(data):
    # ONTAP REST exposes relationship paths as nested source/destination fields.
    query = urllib.parse.urlencode({"source.path": data.get("sourcePath", SOURCE_PATH), "destination.path": data.get("destinationPath", DESTINATION_PATH), "fields": "uuid,state,status,healthy,lag_time,last_transfer_end_timestamp,source,destination"})
    response = _ontap_request(f"/api/snapmirror/relationships?{query}")
    records = response.get("records", [])
    if len(records) != 1 or not records[0].get("uuid"):
        _fail("SnapMirrorRelationshipInvalid", "expected exactly one identified relationship")
    return records[0]


def _payload(event):
    return event.get("Payload", event) if isinstance(event, dict) else {}


def _input(event):
    value = _payload(event)
    return value.get("input", value) if isinstance(value, dict) else {}


def _dry_run(value):
    return bool(value.get("dryRun", False))


def _fail(error, cause):
    raise RuntimeError(f"{error}:{cause}")


def _audit(status, details):
    if not TOPIC_ARN:
        return
    _sns.publish(TopicArn=TOPIC_ARN, Subject=f"FSx DR {status}", Message=json.dumps({"status": status, **details}, separators=(",", ":")))


def validate(event, context):
    data = _payload(event)
    if not isinstance(data, dict) or not data.get("eventId"):
        _fail("InvalidEvent", "eventId is required")
    if not data.get("dryRun") and not data.get("alarm"):
        _fail("InvalidEvent", "raw alarm evidence is required")
    data.setdefault("correlationId", str(uuid.uuid4()))
    data.setdefault("receivedAt", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    data.setdefault("sourcePath", SOURCE_PATH)
    data.setdefault("destinationPath", DESTINATION_PATH)
    return data


def lock(event, context):
    data = _input(event)
    operation = _payload(event).get("operation", "acquire")
    name = "fsx-dr-execution"
    if _dry_run(data):
        return {**data, "lock": "simulated"}
    if operation == "release":
        if data.get("lock") not in {"acquired", "simulated"}:
            return data
        current = _ddb.get_item(TableName=LOCK_TABLE, Key={"LockName": {"S": name}}).get("Item", {})
        owner = current.get("executionId", {}).get("S")
        if owner and owner != data.get("correlationId"):
            _fail("LockOwnershipMismatch", "refusing to release another execution lock")
        if owner:
            _ddb.delete_item(TableName=LOCK_TABLE, Key={"LockName": {"S": name}}, ConditionExpression="executionId = :owner", ExpressionAttributeValues={":owner": {"S": data.get("correlationId", "")}})
        return {**data, "lock": "released"}
    event_id = data.get("eventId")
    if not event_id:
        _fail("EventIdMissing", "eventId is required for deduplication")
    try:
        _ddb.put_item(TableName=LOCK_TABLE, Item={"LockName": {"S": f"event:{event_id}"}, "executionId": {"S": data.get("correlationId", "unknown")}, "expiresAt": {"N": str(int(time.time()) + 86400)}}, ConditionExpression="attribute_not_exists(LockName)")
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            _fail("DuplicateEvent", "eventId was already accepted")
        raise
    try:
        _ddb.put_item(TableName=LOCK_TABLE, Item={"LockName": {"S": name}, "executionId": {"S": data.get("correlationId", "unknown")}, "expiresAt": {"N": str(int(time.time()) + 1800)}}, ConditionExpression="attribute_not_exists(LockName)")
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            _fail("LockBusy", "another DR execution is active")
        raise
    return {**data, "lock": "acquired"}


def verify_failure(event, context):
    data = _payload(event)
    if _dry_run(data):
        return {**data, "failureConfirmed": True}
    signals = data.get("failureSignals", [])
    if not data.get("failureConfirmed") or not isinstance(signals, list) or len(set(signals)) < 2:
        _fail("FailureNotConfirmed", "require explicit confirmation and two independent signals")
    return data


def approval(event, context):
    data = _input(event)
    token = _payload(event).get("taskToken")
    if not token:
        _fail("ApprovalTokenMissing", "callback token is required")
    approval_id = data.get("correlationId") or str(uuid.uuid4())
    if _dry_run(data):
        _sfn.send_task_success(taskToken=token, output=json.dumps({"approved": True, "mode": "dry-run"}))
        return {"accepted": True}
    _ddb.put_item(TableName=APPROVAL_TABLE, Item={"ApprovalId": {"S": approval_id}, "TaskToken": {"S": token}, "ApprovalState": {"S": "PENDING"}, "expiresAt": {"N": str(int(time.time()) + 900)}}, ConditionExpression="attribute_not_exists(ApprovalId)")
    _audit("approval-required", {"approvalId": approval_id, "expiresInSeconds": 900})
    # The token is intentionally never included in the notification or logs.
    return {"accepted": True}


def approval_callback(event, context):
    if isinstance(event, dict) and event.get("body"):
        try:
            body = base64.b64decode(event["body"]).decode() if event.get("isBase64Encoded") else event["body"]
            event = json.loads(body)
        except json.JSONDecodeError:
            _fail("InvalidApproval", "request body must be JSON")
    approval_id = event.get("approvalId")
    decision = event.get("decision")
    if not approval_id or decision not in {"approve", "reject"}:
        _fail("InvalidApproval", "approvalId and approve/reject decision are required")
    try:
        response = _ddb.update_item(
            TableName=APPROVAL_TABLE,
            Key={"ApprovalId": {"S": approval_id}},
            UpdateExpression="SET ApprovalState = :consumed",
            ConditionExpression="attribute_exists(ApprovalId) AND ApprovalState = :pending",
            ExpressionAttributeValues={":pending": {"S": "PENDING"}, ":consumed": {"S": "CONSUMED"}},
            ReturnValues="ALL_NEW",
        )
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            _fail("ApprovalNotFound", "approval is missing, expired, or already consumed")
        raise
    item = response.get("Attributes")
    if not item:
        _fail("ApprovalNotFound", "approval is missing, expired, or already consumed")
    token = item["TaskToken"]["S"]
    if decision == "approve":
        _sfn.send_task_success(taskToken=token, output=json.dumps({"approved": True, "approvedAt": time.time()}))
    else:
        _sfn.send_task_failure(taskToken=token, error="ApprovalRejected", cause="operator rejected DR execution")
    return {"accepted": True}


def fencing(event, context):
    data = _payload(event)
    if _dry_run(data):
        return {**data, "primaryFenced": True, "fencingEvidence": "simulation"}
    if not data.get("primaryFenced") or not data.get("fencingEvidence"):
        _fail("FencingRequired", "source writer fencing evidence is mandatory")
    return data


def snapmirror(event, context):
    data = _input(event)
    if _dry_run(data):
        return {**data, "snapmirror": {"state": "Snapmirrored", "status": "Idle", "healthy": True}}
    if not data.get("snapmirrorEvidence"):
        data["snapmirrorEvidence"] = _relationship(data)
    return {**data, "snapmirror": data["snapmirrorEvidence"]}


def promotion(event, context):
    data = _input(event)
    if _dry_run(data):
        return {**data, "promotion": "simulated"}
    if os.environ.get("ENABLE_PROMOTION", "false").lower() != "true":
        _fail("PromotionDisabled", "enable_promotion is false")
    if not data.get("primaryFenced") or data.get("approval", {}).get("approved") is not True:
        _fail("PromotionNotAuthorized", "approval and fencing are required")
    relationship = _relationship(data)
    relationship_url = f"/api/snapmirror/relationships/{urllib.parse.quote(relationship['uuid'], safe='')}"
    if data.get("planned"):
        _ontap_request(relationship_url, method="PATCH", body={"state": "paused"})
    response = _ontap_request(relationship_url, method="PATCH", body={"state": "broken_off"})
    return {**data, "promotion": {"job": response.get("job", {}).get("uuid"), "relationship": relationship["uuid"]}}


def promotion_verify(event, context):
    data = _payload(event)
    if _dry_run(data):
        return {**data, "tokyoWritable": True}
    job = data.get("promotion", {}).get("job")
    if job:
        status = _ontap_request(f"/api/cluster/jobs/{job}")
        state = str(status.get("state", "")).lower()
        if state in {"failure", "failed", "error", "cancelled", "canceled"}:
            _fail("PromotionFailed", f"ONTAP promotion job ended in {state}")
        if state != "success":
            _fail("PromotionIncomplete", "ONTAP promotion job has not completed successfully")
    destination = data.get("destinationPath", DESTINATION_PATH)
    svm, volume = destination.split(":", 1)
    query = urllib.parse.urlencode({"name": volume, "svm.name": svm, "fields": "type,state,junction.path"})
    response = _ontap_request(f"/api/storage/volumes?{query}")
    records = response.get("records", [])
    if len(records) != 1 or records[0].get("type") != "rw" or records[0].get("state") != "online":
        _fail("DestinationNotWritable", "Tokyo volume is not RW and online")
    return {**data, "tokyoWritable": True, "promotionVerified": records[0]}


def storage(event, context):
    data = _payload(event)
    if not _dry_run(data) and data.get("tokyoWritable") is not True:
        _fail("StorageNotWritable", "Tokyo storage must be verified writable before GitOps activation")
    return {**data, "storagePrepared": True}


def gitops(event, context):
    data = _payload(event)
    if not _dry_run(data):
        if data.get("allowGitOpsUpdate") is not True:
            _fail("GitOpsUpdateDisabled", "explicit allowGitOpsUpdate is required")
        secret = _gitops_secret()
        base = secret.get("base_branch", "main")
        ref = _github_request(secret, "GET", f"/repos/{secret['owner']}/{secret['repo']}/git/ref/heads/{base}")
        base_sha = ref.get("object", {}).get("sha")
        branch = f"dr-failover-{data.get('correlationId', uuid.uuid4().hex)[:20]}"
        branch_ref = _github_request(secret, "GET", f"/repos/{secret['owner']}/{secret['repo']}/git/ref/heads/{branch}", allow_not_found=True)
        if branch_ref is None:
            content = _github_request(secret, "GET", f"/repos/{secret['owner']}/{secret['repo']}/contents/{secret['path']}?ref={base}")
            source = base64.b64decode(content["content"]).decode()
            updated = source.replace("readOnly: true", "readOnly: false", 1).replace("value: /health", "value: /ready", 1)
            if updated == source:
                _fail("GitOpsPatchNotFound", "Tokyo storage patch did not contain expected read-only settings")
            _github_request(secret, "POST", f"/repos/{secret['owner']}/{secret['repo']}/git/refs", {"ref": f"refs/heads/{branch}", "sha": base_sha})
            _github_request(secret, "PUT", f"/repos/{secret['owner']}/{secret['repo']}/contents/{secret['path']}", {"message": f"chore(dr): enable Tokyo writable storage {data.get('correlationId')}", "content": base64.b64encode(updated.encode()).decode(), "sha": content["sha"], "branch": branch})
            _github_request(secret, "POST", f"/repos/{secret['owner']}/{secret['repo']}/pulls", {"title": "DR: enable Tokyo writable storage", "head": branch, "base": base, "body": f"Automated DR change for correlation {data.get('correlationId')}. Merge only after operator review."})
        head = urllib.parse.quote(f"{secret['owner']}:{branch}")
        pulls = _github_request(secret, "GET", f"/repos/{secret['owner']}/{secret['repo']}/pulls?state=all&head={head}")
        if not pulls or pulls[0].get("merged_at") is None:
            _fail("GitOpsAwaitingMerge", "DR pull request requires operator review and merge")
        application = secret.get("argocd_application")
        if not application:
            _fail("ArgoCdSecretInvalid", "argocd_application is required")
        argo = _argocd_request(secret, f"/api/v1/applications/{urllib.parse.quote(application, safe='')}")
        sync = argo.get("status", {}).get("sync", {}).get("status")
        health = argo.get("status", {}).get("health", {}).get("status")
        phase = argo.get("status", {}).get("operationState", {}).get("phase")
        if (sync, health, phase) != ("Synced", "Healthy", "Succeeded"):
            _fail("ArgoCdNotReady", f"sync={sync}, health={health}, phase={phase}")
        return {**data, "gitOps": {"branch": branch, "commit": pulls[0].get("merge_commit_sha"), "pullRequest": pulls[0].get("html_url"), "merged": True, "argocd": {"sync": sync, "health": health, "phase": phase}}}
    return {**data, "gitOps": {"mode": "simulation", "commit": None}}


def file_verify(event, context):
    data = _payload(event)
    if _dry_run(data):
        return {**data, "fileVerification": {"health": True, "ready": True, "sha256": hashlib.sha256(b"dry-run").hexdigest()}}
    url = os.environ.get("FILE_SERVICE_URL", "").rstrip("/")
    if not url:
        _fail("FileServiceUrlMissing", "FILE_SERVICE_URL is required")
    checks = {}
    for endpoint in ("health", "ready"):
        try:
            with urllib.request.urlopen(f"{url}/{endpoint}", timeout=15) as response:
                checks[endpoint] = response.status == 200
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError):
            checks[endpoint] = False
    if not all(checks.values()):
        _fail("FileServiceNotReady", f"health={checks['health']}, ready={checks['ready']}")
    boundary = f"----dr-{uuid.uuid4().hex}"
    content = f"dr-synthetic-{data.get('correlationId', uuid.uuid4().hex)}".encode()
    body = b"--" + boundary.encode() + b"\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dr-synthetic.txt\"\r\nContent-Type: text/plain\r\n\r\n" + content + b"\r\n--" + boundary.encode() + b"--\r\n"
    request = urllib.request.Request(f"{url}/api/v1/files", method="POST", data=body, headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(request, timeout=15) as response:
        metadata = json.loads(response.read().decode())
    file_id = metadata["id"]
    try:
        with urllib.request.urlopen(f"{url}/api/v1/files/{urllib.parse.quote(file_id)}/download", timeout=15) as response:
            downloaded = response.read()
        if hashlib.sha256(downloaded).hexdigest() != metadata.get("sha256"):
            _fail("FileChecksumMismatch", "synthetic download checksum did not match metadata")
        with urllib.request.urlopen(f"{url}/api/v1/files/{urllib.parse.quote(file_id)}/verify", timeout=15) as response:
            verification = json.loads(response.read().decode())
    finally:
        urllib.request.urlopen(urllib.request.Request(f"{url}/api/v1/files/{urllib.parse.quote(file_id)}", method="DELETE"), timeout=15).close()
    if verification.get("integrity") != "PASS":
        _fail("FileIntegrityFailed", "file-service verification did not pass")
    return {**data, "fileVerification": {**checks, "id": file_id, "sha256": metadata.get("sha256"), "integrity": verification.get("integrity")}}


def traffic(event, context):
    data = _payload(event)
    if _dry_run(data):
        return {**data, "traffic": "simulated"}
    if os.environ.get("ENABLE_TRAFFIC_SWITCH", "false").lower() != "true":
        _fail("TrafficSwitchDisabled", "enable_traffic_switch is false")
    if data.get("tokyoWritable") is not True or not data.get("fileVerification", {}).get("ready"):
        _fail("TrafficSwitchNotAuthorized", "writable storage and file verification are required")
    updates = data.get("trafficEndpointGroups", [])
    if not updates:
        _fail("TrafficEndpointGroupsMissing", "explicit endpoint group ARN and dial values are required")
    for update in updates:
        _ga.update_endpoint_group(EndpointGroupArn=update["arn"], TrafficDialPercentage=update["trafficDialPercentage"])
    return {**data, "traffic": {"updated": [u["arn"] for u in updates]}}


def notify(event, context):
    data = _payload(event)
    status = data.get("status", "unknown")
    _audit(status, {"correlationId": _input(data).get("correlationId")})
    return {"status": status, "correlationId": _input(data).get("correlationId")}


def lambda_handler(event, context):
    """Dispatch one zipped handler module through a single Lambda entrypoint."""
    name = os.environ.get("FUNCTION_NAME", "")
    aliases = {"failure": "verify_failure", "approval_callback": "approval_callback"}
    function = globals().get(aliases.get(name, name))
    if not callable(function) or name == "lambda_handler":
        _fail("HandlerNotConfigured", "FUNCTION_NAME does not identify a workflow handler")
    correlation_id = _input(event).get("correlationId")
    print(json.dumps({"event": "handler_started", "function": name, "correlationId": correlation_id, "timestamp": time.time()}))
    try:
        result = function(event, context)
    except Exception as exc:
        print(json.dumps({"event": "handler_failed", "function": name, "correlationId": correlation_id, "errorType": type(exc).__name__, "timestamp": time.time()}))
        raise
    print(json.dumps({"event": "handler_completed", "function": name, "correlationId": correlation_id, "timestamp": time.time()}))
    return result

