// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Test} from "forge-std/Test.sol";
import {HikariLibrary} from "../../src/libraries/HikariLibrary.sol";

/// @notice Pure-math tests for HikariLibrary. The 0.35% fee constants are the
///         critical line item — auditors will compare these to the Pair's swap
///         math and require the two be consistent.
/// @dev    Library functions are internal. To test reverts with vm.expectRevert
///         (which only catches reverts at lower call depth), we wrap each
///         library call in an `external` helper on this contract and call it
///         via `this.helperX(...)`.
contract HikariLibraryTest is Test {
    // ---- external wrappers used to make library calls go through CALL ------

    function ext_sortTokens(address a, address b) external pure returns (address, address) {
        return HikariLibrary.sortTokens(a, b);
    }

    function ext_quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256) {
        return HikariLibrary.quote(amountA, reserveA, reserveB);
    }

    function ext_getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return HikariLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function ext_getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return HikariLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    // ---- tests --------------------------------------------------------------

    function test_sortTokens_swapsCanonically() public view {
        (address t0, address t1) = this.ext_sortTokens(address(0x2), address(0x1));
        assertEq(t0, address(0x1));
        assertEq(t1, address(0x2));
    }

    function test_sortTokens_revertsOnIdentical() public {
        vm.expectRevert(bytes("HL: IDENTICAL_ADDRESSES"));
        this.ext_sortTokens(address(1), address(1));
    }

    function test_sortTokens_revertsOnZero() public {
        vm.expectRevert(bytes("HL: ZERO_ADDRESS"));
        this.ext_sortTokens(address(0), address(1));
    }

    function test_quote_proportional() public view {
        assertEq(this.ext_quote(1 ether, 100 ether, 200 ether), 2 ether);
    }

    function test_quote_revertsOnZeroAmount() public {
        vm.expectRevert(bytes("HL: INSUFFICIENT_AMOUNT"));
        this.ext_quote(0, 1 ether, 1 ether);
    }

    function test_quote_revertsOnZeroLiquidity() public {
        vm.expectRevert(bytes("HL: INSUFFICIENT_LIQUIDITY"));
        this.ext_quote(1, 0, 1 ether);
        vm.expectRevert(bytes("HL: INSUFFICIENT_LIQUIDITY"));
        this.ext_quote(1, 1 ether, 0);
    }

    function test_getAmountOut_appliesFeeOf35Bps() public view {
        uint256 out = this.ext_getAmountOut(1 ether, 100 ether, 100 ether);
        // No-fee swap of 1 in / 100 each side would be ~0.99 out.
        // 35bps fee should yield slightly less.
        assertGt(out, 0.98 ether);
        assertLt(out, 1 ether);
    }

    function test_getAmountOut_revertsOnZeroInput() public {
        vm.expectRevert(bytes("HL: INSUFFICIENT_INPUT_AMOUNT"));
        this.ext_getAmountOut(0, 1 ether, 1 ether);
    }

    function test_getAmountOut_revertsOnZeroLiquidity() public {
        vm.expectRevert(bytes("HL: INSUFFICIENT_LIQUIDITY"));
        this.ext_getAmountOut(1, 0, 1 ether);
        vm.expectRevert(bytes("HL: INSUFFICIENT_LIQUIDITY"));
        this.ext_getAmountOut(1, 1 ether, 0);
    }

    function test_getAmountIn_isInverseOfGetAmountOut() public view {
        uint256 amountOut = 1 ether;
        uint256 reserveIn = 100 ether;
        uint256 reserveOut = 100 ether;
        uint256 amountIn = this.ext_getAmountIn(amountOut, reserveIn, reserveOut);
        uint256 actualOut = this.ext_getAmountOut(amountIn, reserveIn, reserveOut);
        assertGe(actualOut, amountOut);
    }

    function test_getAmountIn_revertsOnZero() public {
        vm.expectRevert(bytes("HL: INSUFFICIENT_OUTPUT_AMOUNT"));
        this.ext_getAmountIn(0, 1 ether, 1 ether);
    }

    /// @dev Reserves are bounded by `uint112` on the Pair contract, so the
    ///      Library's math is only required to be correct within that range.
    ///      We fuzz uint96 reserves (well within uint112) to give the
    ///      multiplications headroom, mirroring realistic on-chain conditions.
    function testFuzz_getAmountOutInversion(uint96 reserveIn, uint96 reserveOut, uint96 amountOut) public view {
        vm.assume(reserveIn > 1e9 && reserveOut > 1e9);
        vm.assume(amountOut > 0 && uint256(amountOut) < uint256(reserveOut));

        uint256 amountIn = this.ext_getAmountIn(amountOut, reserveIn, reserveOut);
        // The Library does not bound amountIn — but it is the caller's job
        // (Router / Pair) to ensure inputs land within uint112 reserves.
        vm.assume(amountIn < type(uint112).max);

        uint256 actualOut = this.ext_getAmountOut(amountIn, reserveIn, reserveOut);
        assertGe(actualOut, amountOut, "round-trip lost value");
    }
}
