// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.20;

import {HikariLPToken} from "./HikariLPToken.sol";
import {IHikariPair} from "../interfaces/IHikariPair.sol";
import {IHikariFactory} from "../interfaces/IHikariFactory.sol";
import {IHikariCallee} from "../interfaces/IHikariCallee.sol";
import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";
import {Math} from "../libraries/Math.sol";
import {UQ112x112} from "../libraries/UQ112x112.sol";

/// @title HikariPair
/// @notice Constant-product AMM pair. Faithful port of Uniswap V2's Pair contract
///         (Solidity 0.5.16) to 0.8.20. SafeMath is removed in favour of native
///         checked arithmetic; the TWAP accumulator overflow remains explicitly
///         `unchecked` because wrap-around is intentional.
/// @dev    Pairs are deployed by HikariFactory via CREATE2 from the (token0, token1)
///         pair, where token0 < token1.
contract HikariPair is IHikariPair, HikariLPToken {
    using UQ112x112 for uint224;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    /// @dev bytes4(keccak256(bytes("transfer(address,uint256)")))
    bytes4 private constant SELECTOR_TRANSFER = 0xa9059cbb;

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    /// @notice Reserve product at the time `feeTo` last accrued fees. Zero when
    ///         protocol fee is disabled. See `_mintFee`.
    uint256 public kLast;

    uint256 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, "Hikari: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor() {
        factory = msg.sender;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR_TRANSFER, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Hikari: TRANSFER_FAILED");
    }

    /// @notice Called once by the factory at deploy.
    function initialize(address token0_, address token1_) external {
        require(msg.sender == factory, "Hikari: FORBIDDEN");
        token0 = token0_;
        token1 = token1_;
    }

    /// @dev Update reserves and, on the first call per block, update price accumulators.
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "Hikari: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        unchecked {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                // * never overflows, and + overflow is desired
                price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
            }
        }
        // Casts are bounds-checked by the require above.
        // forge-lint: disable-next-line(unsafe-typecast)
        reserve0 = uint112(balance0);
        // forge-lint: disable-next-line(unsafe-typecast)
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp % 2 ** 32);
        emit Sync(reserve0, reserve1);
    }

    /// @dev If protocol fee is on, mint LP shares to `feeTo` whose value equals
    ///      2/7 of the liquidity-fee growth since the previous mint/burn. With
    ///      the 0.35% total swap fee, this captures exactly 0.10% to the
    ///      protocol while LPs retain 0.25%.
    ///
    ///      Derivation: let s = totalSupply, r0 = sqrt(kLast), r1 = sqrt(k_now),
    ///      and let phi = 2/7 be the fraction of fee growth (r1 - r0) we want
    ///      `feeTo` to capture. Solving L/(s+L) * r1 = phi * (r1 - r0) for L:
    ///        L = phi * (r1 - r0) * s / (r1 * (1 - phi) + r0 * phi)
    ///      With phi = 2/7 this reduces to:
    ///        L = 2 * s * (r1 - r0) / (5 * r1 + 2 * r0)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IHikariFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0) * uint256(_reserve1));
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply * (rootK - rootKLast) * 2;
                    uint256 denominator = rootK * 5 + rootKLast * 2;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    /// @notice Mint LP shares against the surplus of token0/token1 over the
    ///         tracked reserves. Caller must transfer tokens to this pair first.
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20Minimal(token0).balanceOf(address(this));
        uint256 balance1 = IERC20Minimal(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings; reads after _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY
        } else {
            liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }
        require(liquidity > 0, "Hikari: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * uint256(reserve1);
        emit Mint(msg.sender, amount0, amount1);
    }

    /// @notice Burn LP shares already transferred to this pair, returning the
    ///         pro-rata share of token0/token1 to `to`.
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20Minimal(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20Minimal(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings; reads after _mintFee
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "Hikari: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20Minimal(_token0).balanceOf(address(this));
        balance1 = IERC20Minimal(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * uint256(reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /// @notice Swap. Optionally executes a flash-swap callback if `data` is non-empty.
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, "Hikari: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "Hikari: INSUFFICIENT_LIQUIDITY");

        uint256 balance0;
        uint256 balance1;
        {
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "Hikari: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
            if (data.length > 0) IHikariCallee(to).hikariCall(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20Minimal(_token0).balanceOf(address(this));
            balance1 = IERC20Minimal(_token1).balanceOf(address(this));
        }

        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "Hikari: INSUFFICIENT_INPUT_AMOUNT");
        {
            // 0.35% total swap fee = 35/10000 retained in the pair (k grows by
            // ~0.35% of input on each swap). Of that, 2/7 (= 0.10%) is captured
            // by `feeTo` via _mintFee on the next mint/burn; the remaining 5/7
            // (= 0.25%) accrues to LPs.
            uint256 balance0Adjusted = balance0 * 10_000 - amount0In * 35;
            uint256 balance1Adjusted = balance1 * 10_000 - amount1In * 35;
            require(
                balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * uint256(_reserve1) * 10_000 ** 2,
                "Hikari: K"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @notice Force balances to match reserves by transferring excess to `to`.
    function skim(address to) external lock {
        address _token0 = token0;
        address _token1 = token1;
        _safeTransfer(_token0, to, IERC20Minimal(_token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(_token1, to, IERC20Minimal(_token1).balanceOf(address(this)) - reserve1);
    }

    /// @notice Force reserves to match balances.
    function sync() external lock {
        _update(
            IERC20Minimal(token0).balanceOf(address(this)),
            IERC20Minimal(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }
}
