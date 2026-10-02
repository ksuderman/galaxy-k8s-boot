"""Run the certificate/key validation script the role applies to a Leo-injected TLS pair."""
import base64
import datetime
import ipaddress
import subprocess
import tempfile
import unittest
from pathlib import Path

try:
    # A dependency of ansible-core, so present wherever the playbook's tests run.
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID
except ImportError:  # pragma: no cover
    x509 = None


SCRIPT = Path(__file__).resolve().parents[1] / "roles/galaxy_k8s_deployment/files/check_tls_pair.sh"


def make_pair(directory, name, cn, days=365):
    """Write a self-signed certificate and key; a negative ``days`` yields an expired certificate."""
    cert, key = directory / f"{name}.crt", directory / f"{name}.key"
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    now = datetime.datetime.now(datetime.timezone.utc)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])
    certificate = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(subject)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=2))
        .not_valid_after(now + datetime.timedelta(days=days))
        .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address(cn))]), critical=False)
        .sign(private_key, hashes.SHA256())
    )
    cert.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    key.write_bytes(
        private_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    return cert, key


@unittest.skipUnless(x509, "cryptography is not installed")


class CheckTlsPairTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def check(self, *args):
        return subprocess.run(["sh", str(SCRIPT), *map(str, args)], text=True, capture_output=True)

    def test_matching_pair_passes_and_reports_identity(self):
        cert, key = make_pair(self.dir, "good", "10.128.0.6")
        result = self.check(cert, key)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CN=10.128.0.6", result.stdout)
        self.assertIn("IP Address:10.128.0.6", result.stdout)
        self.assertIn("notAfter=", result.stdout)

    def test_key_from_another_certificate_is_rejected(self):
        cert, _ = make_pair(self.dir, "a", "10.0.0.1")
        _, other_key = make_pair(self.dir, "b", "10.0.0.2")
        result = self.check(cert, other_key)
        self.assertEqual(result.returncode, 1)
        self.assertIn("does not match", result.stderr)

    def test_unparseable_material_is_rejected(self):
        cert, key = make_pair(self.dir, "good", "10.0.0.1")
        bad = self.dir / "bad.crt"
        bad.write_text("not a certificate\n")
        self.assertEqual(self.check(bad, key).returncode, 1)
        self.assertEqual(self.check(cert, bad).returncode, 1)

    def test_expired_certificate_is_rejected(self):
        cert, key = make_pair(self.dir, "old", "10.0.0.1", days=-1)
        result = self.check(cert, key)
        self.assertEqual(result.returncode, 1)
        self.assertIn("expired", result.stderr)

    def test_base64_encoded_pem_is_accepted(self):
        cert, key = make_pair(self.dir, "good", "10.0.0.1")
        b64cert, b64key = self.dir / "cert.b64", self.dir / "key.b64"
        b64cert.write_text(base64.b64encode(cert.read_bytes()).decode())
        b64key.write_text(base64.b64encode(key.read_bytes()).decode())
        result = self.check(b64cert, b64key)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CN=10.0.0.1", result.stdout)

    def test_requires_both_arguments(self):
        cert, _ = make_pair(self.dir, "good", "10.0.0.1")
        self.assertEqual(self.check().returncode, 2)
        self.assertEqual(self.check(cert).returncode, 2)


if __name__ == "__main__":
    unittest.main()
