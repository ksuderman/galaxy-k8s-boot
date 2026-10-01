"""Exercise the actual Ansible permission tasks against a local Galaxy API stub."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


TASKS = Path(__file__).resolve().parents[1] / "roles/galaxy_k8s_deployment/tasks/user_defined_tools.yml"
EMAIL = "default-user@galaxyproject.org"
API_KEY = "test-bootstrap-key"


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
class PermissionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.single_user = True
        self.created_user = False
        self.roles = []
        self.requests = []
        self.posts = []
        test = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def respond(self, body, status=200):
                content = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)

            def do_GET(self):
                url = urlsplit(self.path)
                test.requests.append(url.path)
                if url.path == "/galaxy/api/version":
                    self.respond({"version_major": "26.1"})
                    return
                if url.path == "/galaxy/api/configuration":
                    test.created_user = test.single_user
                    self.respond({"single_user": test.single_user})
                    return
                if self.headers.get("x-api-key") != API_KEY:
                    self.respond({}, 403)
                    return
                if url.path == "/galaxy/api/users":
                    query = parse_qs(url.query)
                    users = [{"id": "encoded-user", "email": EMAIL}] if test.created_user else []
                    self.respond(users if query.get("f_email") == [EMAIL] else [])
                elif url.path == "/galaxy/api/users/encoded-user/roles":
                    # This endpoint includes deleted roles, as Galaxy's does.
                    self.respond([{k: v for k, v in role.items() if k != "deleted"} for role in test.roles])
                elif url.path == "/galaxy/api/roles":
                    self.respond([role for role in test.roles if not role.get("deleted", False)])
                else:
                    self.respond({}, 404)

            def do_POST(self):
                if self.path != "/galaxy/api/roles" or self.headers.get("x-api-key") != API_KEY:
                    self.respond({}, 403)
                    return
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if any(role["name"] == body["name"] for role in test.roles):
                    self.respond({}, 409)
                    return
                test.posts.append(body)
                role = {"id": f"role-{len(test.roles)}", "name": body["name"], "type": body["role_type"]}
                test.roles.append(role)
                self.respond(role)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)

    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def run_tasks(self):
        playbook = self.root / "playbook.json"
        playbook.write_text(json.dumps([{
            "hosts": "localhost",
            "gather_facts": False,
            "tasks": [{"ansible.builtin.include_tasks": str(TASKS)}],
        }]))
        env = dict(os.environ, ANSIBLE_LOCAL_TEMP=str(self.root / "local"),
                   ANSIBLE_REMOTE_TEMP=str(self.root / "remote"), ANSIBLE_NOCOLOR="1")
        result = subprocess.run([
            "ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
            "-e", json.dumps({
                "_udt_api": f"http://127.0.0.1:{self.server.server_port}/galaxy",
                "galaxy_prefix": "/galaxy", "galaxy_user": EMAIL,
                "galaxy_bootstrap_api_key": API_KEY, "ansible_python_interpreter": sys.executable,
            }),
        ], env=env, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_fresh_install_and_rerun(self):
        first = self.run_tasks()
        self.assertTrue(self.created_user)
        self.assertEqual(len(self.posts), 1)
        self.assertEqual(self.posts[0]["role_type"], "user_tool_execute")
        self.assertEqual(self.posts[0]["user_ids"], ["encoded-user"])
        self.assertIn("changed=1", first)
        second = self.run_tasks()
        self.assertEqual(len(self.posts), 1)
        self.assertIn("changed=0", second)

    def test_restored_permission_is_preserved(self):
        self.roles = [{"id": "restored-role", "name": "existing-execution", "type": "user_tool_execute"}]
        output = self.run_tasks()
        self.assertEqual(self.posts, [])
        self.assertIn("changed=0", output)

    def test_deleted_permission_is_replaced(self):
        self.roles = [{"id": "deleted-role", "name": "anvil-user-tools-encoded-user-0",
                       "type": "user_tool_execute", "deleted": True}]
        self.run_tasks()
        self.assertEqual(len(self.posts), 1)
        self.assertEqual(self.posts[0]["name"], "anvil-user-tools-encoded-user-1")

    def test_multiuser_instance_does_not_receive_permission(self):
        self.single_user = False
        self.run_tasks()
        self.assertEqual(self.posts, [])
        self.assertEqual(self.requests, ["/galaxy/api/version", "/galaxy/api/configuration"])


if __name__ == "__main__":
    unittest.main()
