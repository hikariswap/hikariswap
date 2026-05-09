// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Base} from "../Base.t.sol";
import {HikariPair} from "../../src/core/HikariPair.sol";
import {Math} from "../../src/libraries/Math.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract HikariPairTest is Base {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    HikariPair internal pair;

    uint256 internal constant LIQ_A = 10 ether;
    uint256 internal constant LIQ_B = 40 ether;

    function setUp() public {
        deployHikari();
        address pairAddr;
        (tokenA, tokenB, pairAddr) = makePair(LIQ_A, LIQ_B);
        pair = HikariPair(pairAddr);
        addLiquidity(tokenA, tokenB, LIQ_A, LIQ_B, user);
    }

    function test_initialMint_locksMinimumLiquidity() public view {
        assertEq(pair.balanceOf(address(0)), pair.MINIMUM_LIQUIDITY());
        assertGt(pair.balanceOf(user), 0);
        assertEq(pair.totalSupply(), pair.balanceOf(user) + pair.MINIMUM_LIQUIDITY());
    }

    function test_initialize_revertsForNonFactoryCaller() public {
        vm.expectRevert(bytes("Hikari: FORBIDDEN"));
        pair.initialize(address(tokenA), address(tokenB));
    }

    function test_swap_respectsKInvariant() public {
        // Send tokenA to pair, swap for tokenB.
        uint256 amountIn = 1 ether;
        vm.prank(otherUser);
        tokenA.transfer(address(pair), amountIn);

        // Compute expected out using the same 0.35% fee math as HikariLibrary.
        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 reserveIn = pair.token0() == address(tokenA) ? r0 : r1;
        uint256 reserveOut = pair.token0() == address(tokenA) ? r1 : r0;
        uint256 amountOut = (amountIn * 9965 * reserveOut) / (reserveIn * 10_000 + amountIn * 9965);

        (uint256 amount0Out, uint256 amount1Out) =
            pair.token0() == address(tokenA) ? (uint256(0), amountOut) : (amountOut, uint256(0));

        vm.prank(otherUser);
        pair.swap(amount0Out, amount1Out, otherUser, "");

        // K invariant must not have decreased.
        (uint112 nr0, uint112 nr1,) = pair.getReserves();
        assertGe(uint256(nr0) * uint256(nr1), uint256(r0) * uint256(r1));
    }

    function test_swap_revertsOnZeroOutput() public {
        vm.expectRevert(bytes("Hikari: INSUFFICIENT_OUTPUT_AMOUNT"));
        pair.swap(0, 0, user, "");
    }

    function test_swap_revertsOnInsufficientLiquidity() public {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        vm.expectRevert(bytes("Hikari: INSUFFICIENT_LIQUIDITY"));
        pair.swap(uint256(r0) + 1, 0, user, "");
        vm.expectRevert(bytes("Hikari: INSUFFICIENT_LIQUIDITY"));
        pair.swap(0, uint256(r1) + 1, user, "");
    }

    function test_swap_revertsOnInvalidTo() public {
        vm.expectRevert(bytes("Hikari: INVALID_TO"));
        pair.swap(0, 1, address(tokenA), "");
        vm.expectRevert(bytes("Hikari: INVALID_TO"));
        pair.swap(1, 0, address(tokenB), "");
    }

    function test_swap_revertsOnZeroInput() public {
        // Don't send any tokens, but ask for output > 0.
        vm.expectRevert(bytes("Hikari: INSUFFICIENT_INPUT_AMOUNT"));
        pair.swap(0, 1, user, "");
    }

    function test_swap_revertsOnKViolation() public {
        // Transfer barely-enough tokenA, then ask for too much tokenB.
        vm.prank(otherUser);
        tokenA.transfer(address(pair), 1 ether);
        // Ask for an unrealistically large output.
        vm.expectRevert(bytes("Hikari: K"));
        pair.swap(0, 5 ether, otherUser, "");
    }

    function test_skim_returnsExcessTokens() public {
        // Send extra tokenA without minting LP.
        vm.prank(otherUser);
        tokenA.transfer(address(pair), 1 ether);

        uint256 balBefore = tokenA.balanceOf(otherUser);
        pair.skim(otherUser);
        assertEq(tokenA.balanceOf(otherUser), balBefore + 1 ether);
    }

    function test_sync_setsReservesToBalance() public {
        vm.prank(otherUser);
        tokenA.transfer(address(pair), 0.5 ether);
        pair.sync();

        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 reserveA = pair.token0() == address(tokenA) ? r0 : r1;
        assertEq(reserveA, LIQ_A + 0.5 ether);
    }

    function test_burn_returnsTokensProportionally() public {
        uint256 lp = pair.balanceOf(user);
        vm.startPrank(user);
        pair.transfer(address(pair), lp);
        (uint256 a0, uint256 a1) = pair.burn(user);
        vm.stopPrank();

        // After burn, reserves should be near MINIMUM_LIQUIDITY's value.
        // Returned amounts should sum to ~all liquidity minus the locked share.
        assertGt(a0, 0);
        assertGt(a1, 0);
        assertEq(pair.balanceOf(user), 0);
    }

    function test_protocolFee_mintsToFeeTo_onMintAfterSwap() public {
        // Initial: feeTo == feeCollector (set by Base.deployHikari).
        // Trigger swap → builds up k growth.
        uint256 amountIn = 5 ether;
        vm.prank(otherUser);
        tokenA.transfer(address(pair), amountIn);
        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 reserveIn = pair.token0() == address(tokenA) ? r0 : r1;
        uint256 reserveOut = pair.token0() == address(tokenA) ? r1 : r0;
        uint256 amountOut = (amountIn * 9965 * reserveOut) / (reserveIn * 10_000 + amountIn * 9965);
        (uint256 amount0Out, uint256 amount1Out) =
            pair.token0() == address(tokenA) ? (uint256(0), amountOut) : (amountOut, uint256(0));
        vm.prank(otherUser);
        pair.swap(amount0Out, amount1Out, otherUser, "");

        // Now mint more LP — _mintFee should fire and credit feeCollector.
        assertEq(pair.balanceOf(address(feeCollector)), 0);
        addLiquidity(tokenA, tokenB, 1 ether, 4 ether, otherUser);
        assertGt(pair.balanceOf(address(feeCollector)), 0, "feeTo did not receive protocol-fee LP");
    }
}
