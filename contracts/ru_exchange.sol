// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "./interfaces/IERC20.sol";
import "./interfaces/IExchange.sol";

/**
 * @dev Constant-product ETH/ERC20 exchange.
 *
 * This contract is also an ERC20 liquidity token.
 */
contract RUExchange is IExchange {
    address private immutable _deployer;

    IERC20 private _RUXtoken;

    bool private _initialized;
    uint8 private _feePercent;

    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256))
        private _allowances;

    bool private _entered;

    modifier nonReentrant() {
        require(!_entered, "Reentrant call");
        _entered = true;
        _;
        _entered = false;
    }

    constructor() {
        _deployer = msg.sender;
    }

    function grade_exchange()
        public
        pure
        returns (bool)
    {
        return true;
    }

    function getToken()
        external
        view
        override
        returns (IERC20)
    {
        return _RUXtoken;
    }

    function initialize(
        IERC20 token,
        uint8 feePercent,
        uint256 initialTOK,
        uint256 initialETH
    )
        public
        payable
        override
        nonReentrant
        returns (uint256)
    {
        require(
            msg.sender == _deployer,
            "Only deployer"
        );

        require(
            !_initialized,
            "Already initialized"
        );

        require(
            address(token) != address(0),
            "Invalid token"
        );

        require(
            feePercent < 100,
            "Invalid fee"
        );

        require(
            initialTOK > 0,
            "Initial tokens required"
        );

        require(
            initialETH > 0,
            "Initial ETH required"
        );

        require(
            msg.value >= initialETH,
            "Insufficient ETH"
        );

        _initialized = true;
        _RUXtoken = token;
        _feePercent = feePercent;

        require(
            token.transferFrom(
                msg.sender,
                address(this),
                initialTOK
            ),
            "Token transfer failed"
        );

        _mintLiquidity(
            msg.sender,
            initialTOK
        );

        uint256 refund =
            msg.value - initialETH;

        if (refund > 0) {
            _sendETH(
                payable(msg.sender),
                refund
            );
        }

        emit MintBurnDetails(
            initialTOK,
            initialETH
        );

        return initialTOK;
    }

    function buyTokens(
        uint256 amount,
        uint256 maxPrice
    )
        public
        payable
        override
        nonReentrant
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        _requireInitialized();

        uint256 oldTOK = tokenBalance();

        uint256 oldETH =
            address(this).balance -
            msg.value;

        require(
            amount > 0,
            "Amount must be positive"
        );

        require(
            amount < oldTOK,
            "Insufficient token liquidity"
        );

        uint256 tokenFee =
            _percentageCeil(
                amount,
                _feePercent
            );

        uint256 tokensAfterTrade =
            oldTOK - amount;

        uint256 requiredNetETH =
            _ceilDiv(
                oldTOK * oldETH,
                tokensAfterTrade
            ) - oldETH;

        uint256 actualPayment =
            _grossFromNet(
                requiredNetETH,
                _feePercent
            );

        uint256 ethFee =
            _percentageCeil(
                actualPayment,
                _feePercent
            );

        require(
            actualPayment <= maxPrice,
            "Price exceeds maximum"
        );

        require(
            msg.value >= actualPayment,
            "Insufficient payment"
        );

        uint256 tokensReceived =
            amount - tokenFee;

        require(
            _RUXtoken.transfer(
                msg.sender,
                tokensReceived
            ),
            "Token transfer failed"
        );

        uint256 refund =
            msg.value - actualPayment;

        if (refund > 0) {
            _sendETH(
                payable(msg.sender),
                refund
            );
        }

        emit FeeDetails(
            actualPayment,
            ethFee,
            tokenFee
        );

        return (
            actualPayment,
            ethFee,
            tokenFee
        );
    }

    function sellTokens(
        uint256 amount,
        uint256 minPrice
    )
        public
        override
        nonReentrant
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        _requireInitialized();

        uint256 oldTOK = tokenBalance();
        uint256 oldETH = address(this).balance;

        require(
            amount > 0,
            "Amount must be positive"
        );

        uint256 tokenFee =
            _percentageCeil(
                amount,
                _feePercent
            );

        uint256 tradedTOK =
            amount - tokenFee;

        uint256 tokensAfterTrade =
            oldTOK + tradedTOK;

        uint256 ethAfterTrade =
            _ceilDiv(
                oldTOK * oldETH,
                tokensAfterTrade
            );

        uint256 grossETH =
            oldETH - ethAfterTrade;

        uint256 ethFee =
            _percentageCeil(
                grossETH,
                _feePercent
            );

        uint256 actualPayment =
            grossETH - ethFee;

        require(
            actualPayment >= minPrice,
            "Price below minimum"
        );

        require(
            _RUXtoken.transferFrom(
                msg.sender,
                address(this),
                amount
            ),
            "Token transfer failed"
        );

        if (actualPayment > 0) {
            _sendETH(
                payable(msg.sender),
                actualPayment
            );
        }

        emit FeeDetails(
            actualPayment,
            ethFee,
            tokenFee
        );

        return (
            actualPayment,
            ethFee,
            tokenFee
        );
    }

    function tokenBalance()
        public
        view
        override
        returns (uint256)
    {
        if (address(_RUXtoken) == address(0)) {
            return 0;
        }

        return _RUXtoken.balanceOf(
            address(this)
        );
    }

    function mintLiquidityTokens(
        uint256 amount,
        uint256 maxTOK,
        uint256 maxETH
    )
        public
        payable
        override
        nonReentrant
        returns (
            uint256,
            uint256
        )
    {
        _requireInitialized();

        require(
            amount > 0,
            "Amount must be positive"
        );

        require(
            _totalSupply > 0,
            "No liquidity supply"
        );

        uint256 currentTOK =
            tokenBalance();

        uint256 currentETH =
            address(this).balance -
            msg.value;

        uint256 numTOK =
            _ceilDiv(
                amount * currentTOK,
                _totalSupply
            );

        uint256 numETH =
            _ceilDiv(
                amount * currentETH,
                _totalSupply
            );

        require(
            numTOK <= maxTOK,
            "Token maximum exceeded"
        );

        require(
            numETH <= maxETH,
            "ETH maximum exceeded"
        );

        require(
            msg.value >= numETH,
            "Insufficient ETH"
        );

        require(
            _RUXtoken.transferFrom(
                msg.sender,
                address(this),
                numTOK
            ),
            "Token transfer failed"
        );

        _mintLiquidity(
            msg.sender,
            amount
        );

        uint256 refund =
            msg.value - numETH;

        if (refund > 0) {
            _sendETH(
                payable(msg.sender),
                refund
            );
        }

        emit MintBurnDetails(
            numTOK,
            numETH
        );

        return (
            numTOK,
            numETH
        );
    }

    function burnLiquidityTokens(
        uint256 amount,
        uint256 minTOK,
        uint256 minETH
    )
        public
        payable
        override
        nonReentrant
        returns (
            uint256,
            uint256
        )
    {
        _requireInitialized();

        require(
            msg.value == 0,
            "ETH not required"
        );

        require(
            amount > 0,
            "Amount must be positive"
        );

        require(
            _balances[msg.sender] >= amount,
            "Insufficient balance"
        );

        uint256 currentTOK =
            tokenBalance();

        uint256 currentETH =
            address(this).balance;

        uint256 numTOK =
            (
                amount *
                currentTOK
            ) / _totalSupply;

        uint256 numETH =
            (
                amount *
                currentETH
            ) / _totalSupply;

        require(
            numTOK >= minTOK,
            "Tokens below minimum"
        );

        require(
            numETH >= minETH,
            "ETH below minimum"
        );

        _burnLiquidity(
            msg.sender,
            amount
        );

        require(
            _RUXtoken.transfer(
                msg.sender,
                numTOK
            ),
            "Token transfer failed"
        );

        if (numETH > 0) {
            _sendETH(
                payable(msg.sender),
                numETH
            );
        }

        emit MintBurnDetails(
            numTOK,
            numETH
        );

        return (
            numTOK,
            numETH
        );
    }

    function totalSupply()
        external
        view
        override
        returns (uint256)
    {
        return _totalSupply;
    }

    function balanceOf(
        address account
    )
        public
        view
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    )
        external
        override
        returns (bool)
    {
        _transferLiquidity(
            msg.sender,
            recipient,
            amount
        );

        return true;
    }

    function allowance(
        address owner,
        address spender
    )
        external
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    )
        external
        override
        returns (bool)
    {
        require(
            spender != address(0),
            "Approve zero address"
        );

        _allowances[msg.sender][spender] =
            amount;

        emit Approval(
            msg.sender,
            spender,
            amount
        );

        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        external
        override
        returns (bool)
    {
        uint256 currentAllowance =
            _allowances[sender][msg.sender];

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

        _transferLiquidity(
            sender,
            recipient,
            amount
        );

        return true;
    }

    function _transferLiquidity(
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

        emit Transfer(
            sender,
            recipient,
            amount
        );
    }

    function _mintLiquidity(
        address account,
        uint256 amount
    ) internal {
        require(
            account != address(0),
            "Mint to zero address"
        );

        _totalSupply += amount;
        _balances[account] += amount;

        emit Transfer(
            address(0),
            account,
            amount
        );
    }

    function _burnLiquidity(
        address account,
        uint256 amount
    ) internal {
        require(
            _balances[account] >= amount,
            "Insufficient balance"
        );

        _balances[account] -= amount;
        _totalSupply -= amount;

        emit Transfer(
            account,
            address(0),
            amount
        );
    }

    function _requireInitialized()
        internal
        view
    {
        require(
            _initialized,
            "Not initialized"
        );
    }

    function _percentageCeil(
        uint256 amount,
        uint256 percent
    )
        internal
        pure
        returns (uint256)
    {
        if (
            amount == 0 ||
            percent == 0
        ) {
            return 0;
        }

        return _ceilDiv(
            amount * percent,
            100
        );
    }

    function _grossFromNet(
        uint256 netAmount,
        uint256 percent
    )
        internal
        pure
        returns (uint256)
    {
        if (
            netAmount == 0 ||
            percent == 0
        ) {
            return netAmount;
        }

        uint256 gross =
            _ceilDiv(
                netAmount * 100,
                100 - percent
            );

        while (
            gross -
            _percentageCeil(
                gross,
                percent
            ) <
            netAmount
        ) {
            gross += 1;
        }

        return gross;
    }

    function _ceilDiv(
        uint256 numerator,
        uint256 denominator
    )
        internal
        pure
        returns (uint256)
    {
        require(
            denominator > 0,
            "Division by zero"
        );

        if (numerator == 0) {
            return 0;
        }

        return
            (
                (numerator - 1) /
                denominator
            ) + 1;
    }

    function _sendETH(
        address payable recipient,
        uint256 amount
    ) internal {
        (bool success, ) =
            recipient.call{value: amount}("");

        require(
            success,
            "ETH transfer failed"
        );
    }
}