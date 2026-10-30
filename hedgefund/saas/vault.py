"""Encryption of broker secrets (investor passwords) at rest.

Key: HF_SECRET_KEY (a Fernet key: ``python -c "from cryptography.fernet import Fernet;
print(Fernet.generate_key().decode())"``), kept out of the database and of the repository. The
plaintext only exists inside the MT5 bridge, for the time of a login; it is never returned by the
API, never logged and never shown to a model.
"""

from __future__ import annotations

import os


class VaultError(RuntimeError):
    pass


class Vault:
    def __init__(self, key: str | None = None):
        self.key = (key if key is not None else os.environ.get("HF_SECRET_KEY", "")).strip()
        self._f = None
        if self.key:
            try:
                from cryptography.fernet import Fernet

                self._f = Fernet(self.key.encode())
            except Exception as e:  # noqa: BLE001
                raise VaultError(f"HF_SECRET_KEY invalide : {e}") from e

    @property
    def enabled(self) -> bool:
        return self._f is not None

    def encrypt(self, plaintext: str) -> str:
        if self._f is None:
            raise VaultError("chiffrement non configuré (HF_SECRET_KEY absente) : utilisez l'EA Journal Sync")
        return self._f.encrypt(plaintext.encode()).decode()

    def decrypt(self, token: str) -> str:
        if self._f is None:
            raise VaultError("chiffrement non configuré (HF_SECRET_KEY absente)")
        return self._f.decrypt(token.encode()).decode()
