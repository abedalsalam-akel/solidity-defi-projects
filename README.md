# Solidity DeFi Projects — ERC-20, Multisig, and ETH/Token AMM

A Solidity and Python coursework project from **Blockchains and Cryptocurrencies** at Reichman University. The source includes an ERC-20 token, a 2-of-3 multisignature transfer extension, and a constant-product ETH/ERC-20 exchange with liquidity-provider tokens.

## Components

- `contracts/ru_token.sol` — ERC-20 operations, multisignature registration, signature verification, and nonce-based replay protection.
- `contracts/ru_exchange.sol` — exchange initialization, ETH/token buys and sells, liquidity minting and burning, and swap-fee accounting.
- `contracts/interfaces/` — original coursework interfaces.
- `scripts/multisig_token.py` — client-side nonce and second-signature generation.
- `tests/` — Python tests written for Ape and Hypothesis.

## Running locally

The project requests Solidity `0.8.35` and uses Ape (see `requirements.txt` and `ape/ape-config.yaml`). In a compatible Python/EVM development environment:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
ape test
```

These commands **have not yet been verified** on a clean local EVM installation. Do not interpret the presence of tests as evidence of a security audit or passing execution.

## Security

**Educational proof of concept only — do not deploy with real funds.** This code has not been independently security-audited. Areas requiring review include ECDSA domain separation and replay protection, reentrancy, slippage, reserve accounting, rounding, and ERC-20 interactions.

The Ape configuration contains a standard **public development-only test mnemonic**. Never use that mnemonic for real assets.

## Attribution and publication

Adapted from a university assignment; some interfaces and test scaffolding may be course-provided rather than original work. The course submission instructions required a private repository. Verify permission and appropriate attribution before making this source public. No overall repository license is granted; individual Solidity SPDX declarations remain subject to their own terms.
