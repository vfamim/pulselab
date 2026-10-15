#!/usr/bin/env python3
"""Ferramentas de release assinada do PulseLab.

Subcomandos:
  gerar-chave  Cria o par de chaves RSA. A chave privada fica fora do repositório;
               a pública é gravada em release-public-key.json e vai no pacote.
  assinar      Gera pulselab-update.json para um ZIP e assina com a chave privada.
  publicar     Assina e cria a release no GitHub (gh release create), com o ZIP, o
               .sha256 (exigido pelo canal legado), o manifesto e a assinatura. Use --pre para publicar como pré-release
               (não é entregue às máquinas até ser promovida a release normal).

O launcher (pulselab-update.ps1) só aceita manifestos assinados por esta chave.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO = "vfamim/pulselab"
DEFAULT_PRIVATE_KEY = Path.home() / ".pulselab" / "release-key.pem"
PUBLIC_KEY_FILE = ROOT / "release-public-key.json"
MANIFEST_NAME = "pulselab-update.json"


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, capture_output=True, **kwargs)


def public_key_jwk(private_key: Path) -> dict:
    modulus_out = run(["openssl", "rsa", "-in", str(private_key), "-noout", "-modulus"]).stdout.decode()
    modulus_hex = modulus_out.strip().split("=", 1)[1]
    text = run(["openssl", "rsa", "-in", str(private_key), "-noout", "-text"]).stdout.decode()
    match = re.search(r"publicExponent:\s*(\d+)", text)
    if not match:
        raise ValueError("Expoente público não encontrado na chave.")
    exponent = int(match.group(1))
    exponent_bytes = exponent.to_bytes((exponent.bit_length() + 7) // 8, "big")
    return {
        "kty": "RSA",
        "alg": "RS256",
        "n": base64.b64encode(bytes.fromhex(modulus_hex)).decode(),
        "e": base64.b64encode(exponent_bytes).decode(),
    }


def generate_key(private_key: Path, public_out: Path, force: bool = False) -> dict:
    if private_key.exists() and not force:
        raise FileExistsError(f"Chave privada já existe em {private_key}. Use --force para substituir.")
    private_key.parent.mkdir(parents=True, exist_ok=True)
    run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:3072", "-out", str(private_key)])
    private_key.chmod(0o600)
    jwk = public_key_jwk(private_key)
    public_out.write_text(json.dumps(jwk, indent=2) + "\n", encoding="utf-8")
    return jwk


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_manifest(zip_path: Path, version: str, package_url: str, notes: str = "") -> dict:
    return {
        "format": 1,
        "version": version,
        "package_url": package_url,
        "package_sha256": sha256_file(zip_path),
        "published_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "notes": notes,
    }


def sign_file(path: Path, private_key: Path) -> Path:
    sig = path.with_name(path.name + ".sig")
    run(["openssl", "dgst", "-sha256", "-sign", str(private_key), "-out", str(sig), str(path)])
    return sig


def write_signed_manifest(zip_path: Path, version: str, private_key: Path, out_dir: Path, package_url: str, notes: str = "") -> tuple[Path, Path]:
    jwk = public_key_jwk(private_key)
    if PUBLIC_KEY_FILE.is_file() and out_dir.resolve() != ROOT:
        committed = json.loads(PUBLIC_KEY_FILE.read_text(encoding="utf-8"))
        if committed.get("n") != jwk["n"]:
            print("AVISO: a chave privada não corresponde a release-public-key.json do repositório.", file=sys.stderr)
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = out_dir / MANIFEST_NAME
    manifest = build_manifest(zip_path, version, package_url, notes)
    manifest_path.write_bytes(json.dumps(manifest, indent=2, ensure_ascii=False).encode("utf-8") + b"\n")
    sig_path = sign_file(manifest_path, private_key)
    return manifest_path, sig_path


def release_url(version: str, zip_name: str) -> str:
    return f"https://github.com/{REPO}/releases/download/v{version}/{zip_name}"


def cmd_generate(args: argparse.Namespace) -> int:
    generate_key(Path(args.private).expanduser(), Path(args.public_out), force=args.force)
    print(f"Chave privada: {args.private} (guarde fora do repositório e faça backup)")
    print(f"Chave pública: {args.public_out} (commitar)")
    return 0


def cmd_sign(args: argparse.Namespace) -> int:
    zip_path = Path(args.zip).resolve()
    url = args.package_url or release_url(args.version, zip_path.name)
    manifest, sig = write_signed_manifest(zip_path, args.version, Path(args.private).expanduser(), Path(args.out_dir), url, args.notes)
    print(f"Manifesto: {manifest}\nAssinatura: {sig}")
    return 0


def cmd_publish(args: argparse.Namespace) -> int:
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    zip_path = ROOT / "dist" / f"PulseLab-{version}-Windows.zip"
    if not zip_path.is_file():
        print(f"Pacote não encontrado: {zip_path}. Rode tooling/release/build-offline-package.sh antes.", file=sys.stderr)
        return 1
    sha_path = Path(str(zip_path) + ".sha256")
    if not sha_path.is_file():
        # O canal legado (máquinas até 2.2.7) baixa "<package_url>.sha256": precisa ser asset da release.
        print(f"Checksum não encontrado: {sha_path}. Rode tooling/release/build-offline-package.sh antes.", file=sys.stderr)
        return 1
    if not PUBLIC_KEY_FILE.is_file():
        print("release-public-key.json ausente: gere a chave com 'gerar-chave' e commite a pública.", file=sys.stderr)
        return 1
    out_dir = ROOT / "dist-release" / version
    manifest, sig = write_signed_manifest(
        zip_path, version, Path(args.private).expanduser(), out_dir, release_url(version, zip_path.name), args.notes
    )
    cmd = [
        "gh", "release", "create", f"v{version}",
        str(zip_path), str(zip_path) + ".sha256", str(manifest), str(sig),
        "--repo", REPO, "--title", f"PulseLab {version}", "--notes", args.notes or f"PulseLab {version}",
    ]
    if args.pre:
        cmd.append("--prerelease")
    print("Executando:", " ".join(cmd))
    subprocess.run(cmd, check=True)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    gen = sub.add_parser("gerar-chave")
    gen.add_argument("--private", default=str(DEFAULT_PRIVATE_KEY))
    gen.add_argument("--public-out", default=str(PUBLIC_KEY_FILE))
    gen.add_argument("--force", action="store_true")
    gen.set_defaults(func=cmd_generate)

    sign = sub.add_parser("assinar")
    sign.add_argument("--zip", required=True)
    sign.add_argument("--version", required=True)
    sign.add_argument("--out-dir", required=True)
    sign.add_argument("--private", default=str(DEFAULT_PRIVATE_KEY))
    sign.add_argument("--package-url", default=None)
    sign.add_argument("--notes", default="")
    sign.set_defaults(func=cmd_sign)

    pub = sub.add_parser("publicar")
    pub.add_argument("--private", default=str(DEFAULT_PRIVATE_KEY))
    pub.add_argument("--notes", default="")
    pub.add_argument("--pre", action="store_true", help="Publicar como pré-release (não chega às máquinas)")
    pub.set_defaults(func=cmd_publish)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
