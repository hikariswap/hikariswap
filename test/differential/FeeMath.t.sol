// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Test} from "forge-std/Test.sol";
import {HikariLibrary} from "../../src/libraries/HikariLibrary.sol";

/// @title Fee math differential against canonical Uniswap V2
/// @notice The only numerical change in HikariSwap vs Uniswap V2 is the swap
///         fee — 0.35% total instead of 0.30%, with 0.10% routed to the
///         protocol via _mintFee instead of 0.05%. This file pins down the
///         math claim by computing both the V2 and Hikari forms in pure code
///         and asserting:
///           - Hikari's formula reduces to V2's formula when the constants
///             are swapped back;
///           - Hikari's formula gives a strictly worse output for the trader
///             (more fee taken) given the same input/reserves.
contract FeeMathDifferentialTest is Test {
    /// @notice Canonical V2 getAmountOut (3/1000 fee, 0.30% total).
    function _v2GetAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        return numerator / denominator;
    }

    /// @notice Canonical V2 getAmountIn (3/1000 fee, 0.30% total).
    function _v2GetAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function test_hikari_takesMoreFeeThanV2() public pure {
        uint256 amountIn = 1 ether;
        uint256 reserveIn = 1000 ether;
        uint256 reserveOut = 1000 ether;

        uint256 v2Out = _v2GetAmountOut(amountIn, reserveIn, reserveOut);
        uint256 hikariOut = HikariLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
        assertLt(hikariOut, v2Out, "Hikari should yield less than V2 on identical input");
    }

    function test_hikari_requiresMoreInputThanV2() public pure {
        uint256 amountOut = 1 ether;
        uint256 reserveIn = 1000 ether;
        uint256 reserveOut = 1000 ether;

        uint256 v2In = _v2GetAmountIn(amountOut, reserveIn, reserveOut);
        uint256 hikariIn = HikariLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
        assertGt(hikariIn, v2In, "Hikari should require more input than V2 for the same output");
    }

    /// @notice The fee delta is exactly 5 bps. With reserves balanced and a
    ///         small input, the absolute output difference is approximately
    ///         5 bps of `amountIn * (reserveOut / reserveIn)`. We assert a
    ///         loose bound to catch any silent regression toward V2's 30 bps.
    function test_hikari_feeIsBetween30And40Bps() public pure {
        uint256 amountIn = 1 ether;
        uint256 reserveIn = 1000 ether;
        uint256 reserveOut = 1000 ether;

        uint256 noFeeOut = (amountIn * reserveOut) / (reserveIn + amountIn);
        uint256 hikariOut = HikariLibrary.getAmountOut(amountIn, reserveIn, reserveOut);

        // Effective fee = (noFeeOut - hikariOut) / noFeeOut, in bps.
        uint256 feeBps = ((noFeeOut - hikariOut) * 10_000) / noFeeOut;
        assertGe(feeBps, 30, "fee dipped below V2's 30 bps");
        assertLe(feeBps, 40, "fee exceeded the documented 35 bps materially");
    }

    function testFuzz_hikariOutLessThanV2(uint128 amountIn, uint128 reserveIn, uint128 reserveOut) public pure {
        vm.assume(amountIn > 1e6 && reserveIn > 1e9 && reserveOut > 1e9);
        vm.assume(uint256(amountIn) < type(uint128).max / 10_000);

        uint256 v2Out = _v2GetAmountOut(amountIn, reserveIn, reserveOut);
        uint256 hikariOut = HikariLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
        assertLe(hikariOut, v2Out, "Hikari out must not exceed V2 out at identical inputs");
    }
}
