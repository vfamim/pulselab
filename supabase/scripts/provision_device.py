#!/usr/bin/env python3
"""
PulseLab - Ferramenta Administrativa de Provisionamento de Dispositivos
Gera tokens individuais de uso único com hash SHA-256 e os registra em
public.device_enrollment_tokens no Supabase via credencial administrativa protegida.

Regras de Segurança:
1. Chave service_role obtida EXCLUSIVAMENTE via variável de ambiente
   (PULSELAB_SERVICE_ROLE_KEY ou SUPABASE_SERVICE_ROLE_KEY) ou entrada protegida (getpass).
2. O token gerado é individual, de uso único e armazenado apenas como hash SHA-256 no banco.
3. Exige obrigatoriamente o parâmetro --output para salvar o arquivo de provisionamento.
4. Aplica permissões restritas (chmod 0600) no arquivo de saída gerado.
5. NUNCA imprime tokens, senhas ou conteúdos sensíveis no stdout.
"""

import argparse
import datetime
import getpass
import hashlib
import json
import os
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


def get_service_role_key() -> str:
    key = (
        os.environ.get("PULSELAB_SERVICE_ROLE_KEY")
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    )
    if key and key.strip():
        return key.strip()

    if sys.stdin.isatty():
        try:
            prompted = getpass.getpass("Supabase service_role key: ")
            if prompted and prompted.strip():
                return prompted.strip()
        except Exception:
            pass

    raise RuntimeError(
        "Supabase service_role key required via environment variable "
        "(PULSELAB_SERVICE_ROLE_KEY or SUPABASE_SERVICE_ROLE_KEY) or protected input."
    )


def request_json(url: str, data=None, headers=None, method="GET"):
    headers = headers or {}
    encoded_data = None
    if data is not None:
        encoded_data = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=encoded_data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            content = resp.read().decode("utf-8")
            return json.loads(content) if content else {}
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8")
        raise RuntimeError(f"HTTP {exc.code}: {exc.reason} - {err_body}") from exc


def generate_enrollment_token() -> str:
    return secrets.token_urlsafe(32)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def register_device_enrollment_token(
    supabase_url: str,
    service_role_key: str,
    token_hash: str,
    installation_id: str,
    site_id: str,
    expires_at: str,
    regional_hub: str = "",
    school_code: str = "",
    computer_id: str = "",
):
    supabase_url = supabase_url.rstrip("/")
    endpoint = f"{supabase_url}/rest/v1/device_enrollment_tokens"
    headers = {
        "apikey": service_role_key,
        "Authorization": f"Bearer {service_role_key}",
        "Prefer": "return=minimal",
    }
    payload = {
        "token_hash": token_hash,
        "installation_id": installation_id,
        "site_id": site_id,
        "regional_hub": regional_hub or None,
        "school_code": school_code or None,
        "computer_id": computer_id or None,
        "expires_at": expires_at,
    }
    request_json(endpoint, data=payload, headers=headers, method="POST")


def write_secure_output(file_path: Path, data: dict):
    file_path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    mode = 0o600
    fd = os.open(str(file_path), flags, mode)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
    except Exception:
        os.close(fd)
        raise

    try:
        os.chmod(str(file_path), mode)
    except Exception:
        pass


def main():
    parser = argparse.ArgumentParser(
        description="PulseLab Administrative Device Provisioning Tool"
    )
    parser.add_argument(
        "--url",
        default=os.environ.get("PULSELAB_URL", ""),
        help="Supabase Project URL (or env PULSELAB_URL)",
    )
    parser.add_argument(
        "--anon-key",
        default=os.environ.get("PULSELAB_ANON_KEY", ""),
        help="Supabase Anon Key (optional, for client bundle)",
    )
    parser.add_argument(
        "--installation-id",
        default="",
        help="Device installation UUID (auto-generated if omitted)",
    )
    parser.add_argument(
        "--site-id",
        required=True,
        help="Site / Hub ID (e.g. JUAZEIRO-BA)",
    )
    parser.add_argument(
        "--regional-hub",
        default="Polo-Nordeste-01",
        help="Regional hub",
    )
    parser.add_argument(
        "--school-code",
        default="ESCOLA-01",
        help="School code",
    )
    parser.add_argument(
        "--computer-id",
        default="LAB-01",
        help="Computer name or identifier",
    )
    parser.add_argument(
        "--expires-hours",
        type=int,
        default=24,
        help="Token validity in hours (default: 24)",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Mandatory output JSON file path for provisioning bundle (chmod 0600)",
    )

    args = parser.parse_args()

    supabase_url = args.url.strip().rstrip("/")
    if not supabase_url:
        sys.exit("Error: Supabase URL is required (via --url or env PULSELAB_URL).")

    installation_id = args.installation_id.strip()
    if not installation_id:
        installation_id = str(uuid.uuid4())
    else:
        # Validate UUID format
        try:
            uuid.UUID(installation_id)
        except ValueError:
            sys.exit(f"Error: Invalid installation_id UUID: {installation_id}")

    service_role_key = get_service_role_key()

    raw_token = generate_enrollment_token()
    token_h = hash_token(raw_token)

    now_utc = datetime.datetime.now(datetime.timezone.utc)
    expires_dt = now_utc + datetime.timedelta(hours=max(1, args.expires_hours))
    expires_at_iso = expires_dt.isoformat()

    # Register in Supabase database
    try:
        register_device_enrollment_token(
            supabase_url=supabase_url,
            service_role_key=service_role_key,
            token_hash=token_h,
            installation_id=installation_id,
            site_id=args.site_id,
            expires_at=expires_at_iso,
            regional_hub=args.regional_hub,
            school_code=args.school_code,
            computer_id=args.computer_id,
        )
    except Exception as exc:
        sys.exit(f"Error registering enrollment token in database: {exc}")

    output_path = Path(args.output).resolve()
    bundle_data = {
        "supabase_url": supabase_url,
        "supabase_anon_key": args.anon_key.strip() or None,
        "installation_id": installation_id,
        "site_id": args.site_id,
        "regional_hub": args.regional_hub,
        "school_code": args.school_code,
        "computer_id": args.computer_id,
        "enrollment_token": raw_token,
        "expires_at": expires_at_iso,
        "created_at": now_utc.isoformat(),
    }

    try:
        write_secure_output(output_path, bundle_data)
    except Exception as exc:
        sys.exit(f"Error writing secure output to {output_path}: {exc}")

    # Sanitized output: NEVER leak raw token or secret to stdout
    print(f"[+] Device provisioning record created for installation {installation_id}")
    print(f"[+] Single-use enrollment token registered in database (expires at {expires_at_iso})")
    print(f"[+] Provisioning bundle saved to {output_path} (mode 0600)")


if __name__ == "__main__":
    main()
