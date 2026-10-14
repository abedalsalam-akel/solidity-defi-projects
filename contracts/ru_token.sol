// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "./interfaces/IERC20.sol";
import "./interfaces/IMultisigToken.sol";

/**
 * @dev ERC20 implementation for the Reichman University Token,
 * including the optional 2-out-of-3 multisig extension.
 */
contract RUToken is IERC20, IERC20Metadata, IMultisigToken {
    struct Multisig {
        address pk1;
        address pk2;
        address pk3;
        uint256 nonce;
        bool registered;
    }

    uint256 public maxTokens;
    uint256 public tokenPrice;

    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => Multisig) private _multisigs;

    uint256 private constant SECP256K1_HALF_ORDER =
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    constructor(uint256 _tokenPrice, uint256 _maxTokens) {
        require(_tokenPrice > 0, "Token price must be positive");

        tokenPrice = _tokenPrice;
        maxTokens = _maxTokens;
    }

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function name() public pure override returns (string memory) {
        return "Reichman U Token";
    }

    function symbol() public pure override returns (string memory) {
        return "RUX";
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        require(spender != address(0), "Approve zero address");

        _allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];

        require(
            currentAllowance >= amount,
            "Insufficient allowance"
        );

        _allowances[sender][msg.sender] =
            currentAllowance - amount;

        emit Approval(
            sender,
            msg.sender,
            _allowances[sender][msg.sender]
        );

        _transfer(sender, recipient, amount);

        return true;
    }

    /**
     * @dev Mint msg.value / tokenPrice tokens for the caller.
     */
    function mint() public payable returns (uint256) {
        uint256 amount = msg.value / tokenPrice;

        require(amount > 0, "Not enough ETH");
        require(
            _totalSupply + amount <= maxTokens,
            "Maximum supply exceeded"
        );

        _totalSupply += amount;
        _balances[msg.sender] += amount;

        emit Transfer(address(0), msg.sender, amount);

        return amount;
    }

    /**
     * @dev Burn tokens and return their corresponding ETH value.
     */
    function burn(uint256 amount) public {
        require(
            _balances[msg.sender] >= amount,
            "Insufficient balance"
        );

        uint256 refund = amount * tokenPrice;

        require(
            address(this).balance >= refund,
            "Insufficient contract ETH"
        );

        _balances[msg.sender] -= amount;
        _totalSupply -= amount;

        emit Transfer(msg.sender, address(0), amount);

        (bool success, ) =
            payable(msg.sender).call{value: refund}("");

        require(success, "ETH refund failed");
    }

    /**
     * @dev Return the deterministic address controlled by three owners.
     */
    function getMultisigAddress(
        address pk1,
        address pk2,
        address pk3
    ) public pure override returns (address) {
        (
            address first,
            address second,
            address third
        ) = _sortAddresses(pk1, pk2, pk3);

        bytes32 hashValue = keccak256(
            abi.encode(first, second, third)
        );

        return address(uint160(uint256(hashValue)));
    }

    /**
     * @dev Register a new 2-out-of-3 multisig address.
     */
    function registerMultisigAddress(
        address pk1,
        address pk2,
        address pk3
    ) external override returns (address) {
        require(
            pk1 != address(0) &&
            pk2 != address(0) &&
            pk3 != address(0),
            "Zero owner"
        );

        require(
            pk1 != pk2 &&
            pk1 != pk3 &&
            pk2 != pk3,
            "Owners must be different"
        );

        (
            address first,
            address second,
            address third
        ) = _sortAddresses(pk1, pk2, pk3);

        address multisigAddress =
            getMultisigAddress(first, second, third);

        require(
            !_multisigs[multisigAddress].registered,
            "Already registered"
        );

        _multisigs[multisigAddress] = Multisig({
            pk1: first,
            pk2: second,
            pk3: third,
            nonce: 0,
            registered: true
        });

        return multisigAddress;
    }

    /**
     * @dev Used by the Python client to obtain the next nonce.
     */
    function getMultisigNonce(
        address multisigOwner
    ) external view returns (uint256) {
        require(
            _multisigs[multisigOwner].registered,
            "Multisig not registered"
        );

        return _multisigs[multisigOwner].nonce;
    }

    /**
     * @dev Transfer tokens using two distinct authorized signatures.
     */
    function transfer2of3(
        address multisigOwner,
        address recipient,
        uint256 amount,
        uint256 nonce,
        Signature calldata secondSig
    ) external override returns (bool) {
        Multisig storage multisig =
            _multisigs[multisigOwner];

        require(
            multisig.registered,
            "Multisig not registered"
        );

        require(
            nonce == multisig.nonce,
            "Invalid nonce"
        );

        require(
            _isOwner(multisig, msg.sender),
            "Sender is not an owner"
        );

        bytes32 messageHash = keccak256(
            abi.encode(
                address(this),
                multisigOwner,
                recipient,
                amount,
                nonce
            )
        );

        address secondSigner =
            _recoverSigner(messageHash, secondSig);

        require(
            _isOwner(multisig, secondSigner),
            "Second signer is not an owner"
        );

        require(
            secondSigner != msg.sender,
            "Signers must be different"
        );

        multisig.nonce += 1;

        _transfer(
            multisigOwner,
            recipient,
            amount
        );

        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(
            sender != address(0),
            "Transfer from zero address"
        );

        require(
            recipient != address(0),
            "Transfer to zero address"
        );

        require(
            _balances[sender] >= amount,
            "Insufficient balance"
        );

        _balances[sender] -= amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _isOwner(
        Multisig storage multisig,
        address account
    ) internal view returns (bool) {
        return
            account == multisig.pk1 ||
            account == multisig.pk2 ||
            account == multisig.pk3;
    }

    function _recoverSigner(
        bytes32 messageHash,
        Signature calldata sig
    ) internal pure returns (address) {
        require(
            sig.v == 27 || sig.v == 28,
            "Invalid v"
        );

        require(
            uint256(sig.s) <= SECP256K1_HALF_ORDER,
            "Invalid s"
        );

        address signer = ecrecover(
            messageHash,
            sig.v,
            sig.r,
            sig.s
        );

        require(
            signer != address(0),
            "Invalid signature"
        );

        return signer;
    }

    function _sortAddresses(
        address pk1,
        address pk2,
        address pk3
    )
        internal
        pure
        returns (
            address first,
            address second,
            address third
        )
    {
        first = pk1;
        second = pk2;
        third = pk3;

        if (uint160(first) > uint160(second)) {
            (first, second) = (second, first);
        }

        if (uint160(second) > uint160(third)) {
            (second, third) = (third, second);
        }

        if (uint160(first) > uint160(second)) {
            (first, second) = (second, first);
        }
    }
}