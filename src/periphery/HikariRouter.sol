// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.20;

import {IHikariFactory} from "../interfaces/IHikariFactory.sol";
import {IHikariPair} from "../interfaces/IHikariPair.sol";
import {IHikariRouter} from "../interfaces/IHikariRouter.sol";
import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";
import {IWLCAI} from "../interfaces/IWLCAI.sol";
import {HikariLibrary} from "../libraries/HikariLibrary.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";

/// @title HikariRouter
/// @notice User-facing entrypoint for HikariSwap. Faithful port of Uniswap V2's
///         Router02 with native-coin function names changed from `ETH` to
///         `LCAI` and fee math updated for the 0.35% total swap fee. The router
///         holds no state and never custodies user funds across calls.
contract HikariRouter is IHikariRouter {
    address public immutable factory;
    address public immutable WLCAI;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "HR: EXPIRED");
        _;
    }

    constructor(address factory_, address wlcai_) {
        require(factory_ != address(0) && wlcai_ != address(0), "HR: ZERO_ADDRESS");
        factory = factory_;
        WLCAI = wlcai_;
    }

    /// @notice Reject plain LCAI transfers from anyone other than the WLCAI
    ///         contract (which sends LCAI back to us during withdraw).
    receive() external payable {
        require(msg.sender == WLCAI, "HR: ONLY_WLCAI");
    }

    // -------------------------------------------------------------------------
    // ADD LIQUIDITY
    // -------------------------------------------------------------------------

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (IHikariFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IHikariFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = HikariLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = HikariLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "HR: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = HikariLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "HR: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = HikariLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IHikariPair(pair).mint(to);
    }

    function addLiquidityLCAI(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountLCAIMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 amountToken, uint256 amountLCAI, uint256 liquidity) {
        (amountToken, amountLCAI) =
            _addLiquidity(token, WLCAI, amountTokenDesired, msg.value, amountTokenMin, amountLCAIMin);
        address pair = HikariLibrary.pairFor(factory, token, WLCAI);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWLCAI(WLCAI).deposit{value: amountLCAI}();
        require(IWLCAI(WLCAI).transfer(pair, amountLCAI), "HR: WLCAI_TRANSFER_FAILED");
        liquidity = IHikariPair(pair).mint(to);
        if (msg.value > amountLCAI) {
            TransferHelper.safeTransferLCAI(msg.sender, msg.value - amountLCAI);
        }
    }

    // -------------------------------------------------------------------------
    // REMOVE LIQUIDITY
    // -------------------------------------------------------------------------

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = HikariLibrary.pairFor(factory, tokenA, tokenB);
        // HikariLPToken.transferFrom returns true on success and reverts otherwise;
        // the explicit return check is defensive against future LP-token swaps.
        require(IHikariPair(pair).transferFrom(msg.sender, pair, liquidity), "HR: LP_TRANSFER_FAILED");
        (uint256 amount0, uint256 amount1) = IHikariPair(pair).burn(to);
        (address token0,) = HikariLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "HR: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "HR: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityLCAI(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountLCAIMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountToken, uint256 amountLCAI) {
        (amountToken, amountLCAI) = removeLiquidity(
            token, WLCAI, liquidity, amountTokenMin, amountLCAIMin, address(this), deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWLCAI(WLCAI).withdraw(amountLCAI);
        TransferHelper.safeTransferLCAI(to, amountLCAI);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB) {
        address pair = HikariLibrary.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IHikariPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityLCAIWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountLCAIMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountLCAI) {
        address pair = HikariLibrary.pairFor(factory, token, WLCAI);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IHikariPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountLCAI) = removeLiquidityLCAI(token, liquidity, amountTokenMin, amountLCAIMin, to, deadline);
    }

    /// @notice Variant of removeLiquidityLCAI for tokens that take a fee on
    ///         transfer; only the LCAI side has a guaranteed minimum.
    function removeLiquidityLCAISupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountLCAIMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountLCAI) {
        (, amountLCAI) = removeLiquidity(
            token, WLCAI, liquidity, amountTokenMin, amountLCAIMin, address(this), deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20Minimal(token).balanceOf(address(this)));
        IWLCAI(WLCAI).withdraw(amountLCAI);
        TransferHelper.safeTransferLCAI(to, amountLCAI);
    }

    function removeLiquidityLCAIWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountLCAIMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountLCAI) {
        address pair = HikariLibrary.pairFor(factory, token, WLCAI);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IHikariPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountLCAI = removeLiquidityLCAISupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountLCAIMin, to, deadline
        );
    }

    // -------------------------------------------------------------------------
    // SWAP — standard
    // -------------------------------------------------------------------------

    /// @dev Walks the path executing chained pair swaps. Pairs MUST already hold
    ///      the input amount transferred by the caller before this is invoked.
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; ++i) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = HikariLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? HikariLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IHikariPair(HikariLibrary.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = HikariLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "HR: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, HikariLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = HikariLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "HR: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, HikariLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactLCAIForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WLCAI, "HR: INVALID_PATH");
        amounts = HikariLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "HR: INSUFFICIENT_OUTPUT_AMOUNT");
        IWLCAI(WLCAI).deposit{value: amounts[0]}();
        require(
            IWLCAI(WLCAI).transfer(HikariLibrary.pairFor(factory, path[0], path[1]), amounts[0]),
            "HR: WLCAI_TRANSFER_FAILED"
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactLCAI(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WLCAI, "HR: INVALID_PATH");
        amounts = HikariLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "HR: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, HikariLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWLCAI(WLCAI).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferLCAI(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForLCAI(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WLCAI, "HR: INVALID_PATH");
        amounts = HikariLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "HR: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, HikariLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWLCAI(WLCAI).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferLCAI(to, amounts[amounts.length - 1]);
    }

    function swapLCAIForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WLCAI, "HR: INVALID_PATH");
        amounts = HikariLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, "HR: EXCESSIVE_INPUT_AMOUNT");
        IWLCAI(WLCAI).deposit{value: amounts[0]}();
        require(
            IWLCAI(WLCAI).transfer(HikariLibrary.pairFor(factory, path[0], path[1]), amounts[0]),
            "HR: WLCAI_TRANSFER_FAILED"
        );
        _swap(amounts, path, to);
        if (msg.value > amounts[0]) {
            TransferHelper.safeTransferLCAI(msg.sender, msg.value - amounts[0]);
        }
    }

    // -------------------------------------------------------------------------
    // SWAP — supporting fee-on-transfer tokens
    // -------------------------------------------------------------------------

    /// @dev Identical to _swap but reads each pair's reserves after the input
    ///      transfer to derive the actual input amount, accommodating tokens
    ///      that take a fee on transfer.
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; ++i) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = HikariLibrary.sortTokens(input, output);
            IHikariPair pair = IHikariPair(HikariLibrary.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) =
                    input == token0 ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));
                amountInput = IERC20Minimal(input).balanceOf(address(pair)) - reserveInput;
                amountOutput = HikariLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? HikariLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        TransferHelper.safeTransferFrom(path[0], msg.sender, HikariLibrary.pairFor(factory, path[0], path[1]), amountIn);
        uint256 balanceBefore = IERC20Minimal(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20Minimal(path[path.length - 1]).balanceOf(to) - balanceBefore >= amountOutMin,
            "HR: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactLCAIForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) {
        require(path[0] == WLCAI, "HR: INVALID_PATH");
        uint256 amountIn = msg.value;
        IWLCAI(WLCAI).deposit{value: amountIn}();
        require(
            IWLCAI(WLCAI).transfer(HikariLibrary.pairFor(factory, path[0], path[1]), amountIn),
            "HR: WLCAI_TRANSFER_FAILED"
        );
        uint256 balanceBefore = IERC20Minimal(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20Minimal(path[path.length - 1]).balanceOf(to) - balanceBefore >= amountOutMin,
            "HR: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactTokensForLCAISupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        require(path[path.length - 1] == WLCAI, "HR: INVALID_PATH");
        TransferHelper.safeTransferFrom(path[0], msg.sender, HikariLibrary.pairFor(factory, path[0], path[1]), amountIn);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20Minimal(WLCAI).balanceOf(address(this));
        require(amountOut >= amountOutMin, "HR: INSUFFICIENT_OUTPUT_AMOUNT");
        IWLCAI(WLCAI).withdraw(amountOut);
        TransferHelper.safeTransferLCAI(to, amountOut);
    }

    // -------------------------------------------------------------------------
    // VIEW HELPERS
    // -------------------------------------------------------------------------

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256 amountB) {
        return HikariLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountOut)
    {
        return HikariLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountIn)
    {
        return HikariLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts) {
        return HikariLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts) {
        return HikariLibrary.getAmountsIn(factory, amountOut, path);
    }
}
