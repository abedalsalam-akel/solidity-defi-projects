from typing import Tuple

from ape import project
from eth_abi import encode
from eth_keys import KeyAPI
from eth_keys.backends import NativeECCBackend
from eth_utils import keccak


RUToken = project.RUToken

grade_multisig = True

keys = KeyAPI(NativeECCBackend)


class Signature:
    def __init__(
        self,
        r: bytes,
        s: bytes,
        v: int,
    ) -> None:
        self.r = r
        self.s = s
        self.v = v

    def encoded(self) -> Tuple[bytes, bytes, int]:
        return (
            self.r,
            self.s,
            self.v + 27,
        )


def generate_nonce_and_second_signature_transfer2of3(
    tok: RUToken,
    sk,
    multisigAddr,
    spender,
    amount,
) -> Tuple[int, Signature]:
    key = keys.PrivateKey(
        bytes.fromhex(sk[2:])
    )

    nonce = int(
        tok.getMultisigNonce(multisigAddr)
    )

    encoded_message = encode(
        [
            "address",
            "address",
            "address",
            "uint256",
            "uint256",
        ],
        [
            str(tok.address),
            str(multisigAddr),
            str(spender),
            int(amount),
            nonce,
        ],
    )

    message_hash = keccak(encoded_message)

    signed = keys.ecdsa_sign(
        message_hash,
        key,
    )

    signature = Signature(
        signed.r.to_bytes(
            32,
            byteorder="big",
        ),
        signed.s.to_bytes(
            32,
            byteorder="big",
        ),
        signed.v,
    )

    return nonce, signature