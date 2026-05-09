// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Base} from "../Base.t.sol";
import {HikariRouter} from "../../src/periphery/HikariRouter.sol";
import {HikariPair} from "../../src/core/HikariPair.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract HikariRouterTest is Base {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    HikariPair internal pair;

    function setUp() public {
        deployHikari();
        address pairAddr;
        (tokenA, tokenB, pairAddr) = makePair(10 ether, 40 ether);
        pair = HikariPair(pairAddr);
        addLiquidity(tokenA, tokenB, 10 ether, 40 ether, user);
    }

    function test_constructor_revertsOnZeroFactory() public {
        vm.expectRevert(bytes("HR: ZERO_ADDRESS"));
        new HikariRouter(address(0), address(wlcai));
    }

    function test_constructor_revertsOnZeroWLCAI() public {
        vm.expectRevert(bytes("HR: ZERO_ADDRESS"));
        new HikariRouter(address(factory), address(0));
    }

    function test_addLiquidity_proportional() public {
        // Adding 1A / 4B to a 10A / 40B pool should mint LP cleanly.
        uint256 lpBefore = pair.balanceOf(otherUser);
        vm.prank(otherUser);
        router.addLiquidity(
            address(tokenA), address(tokenB), 1 ether, 4 ether, 0.99 ether, 3.99 ether, otherUser, block.timestamp + 1
        );
        assertGt(pair.balanceOf(otherUser), lpBefore);
    }

    function test_addLiquidity_revertsOnSlippageA() public {
        // Pool ratio is 10A : 40B (i.e. price = 4 B per A).
        // Caller wants 100A / 1B. Optimal A for 1B = 1*10/40 = 0.25. That's the
        // "needs less A" branch. With amountAMin=10, the 0.25 result fails the
        // floor check → INSUFFICIENT_A_AMOUNT.
        vm.prank(otherUser);
        vm.expectRevert(bytes("HR: INSUFFICIENT_A_AMOUNT"));
        router.addLiquidity(
            address(tokenA), address(tokenB), 100 ether, 1 ether, 10 ether, 0, otherUser, block.timestamp + 1
        );
    }

    function test_addLiquidity_revertsOnDeadline() public {
        vm.warp(1000);
        vm.prank(otherUser);
        vm.expectRevert(bytes("HR: EXPIRED"));
        router.addLiquidity(address(tokenA), address(tokenB), 1 ether, 4 ether, 0, 0, otherUser, 999);
    }

    function test_swapExactTokensForTokens_respectsMinOutAndDeadline() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory expected = router.getAmountsOut(1 ether, path);

        vm.prank(otherUser);
        uint256[] memory amounts =
            router.swapExactTokensForTokens(1 ether, expected[1], path, otherUser, block.timestamp + 1);
        assertEq(amounts[1], expected[1]);

        vm.prank(otherUser);
        vm.expectRevert(bytes("HR: INSUFFICIENT_OUTPUT_AMOUNT"));
        router.swapExactTokensForTokens(1 ether, type(uint256).max, path, otherUser, block.timestamp + 1);

        vm.warp(2000);
        vm.prank(otherUser);
        vm.expectRevert(bytes("HR: EXPIRED"));
        router.swapExactTokensForTokens(1 ether, 0, path, otherUser, 1);
    }

    function test_swapTokensForExactTokens_respectsMaxIn() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory required = router.getAmountsIn(1 ether, path);

        vm.prank(otherUser);
        vm.expectRevert(bytes("HR: EXCESSIVE_INPUT_AMOUNT"));
        router.swapTokensForExactTokens(1 ether, required[0] - 1, path, otherUser, block.timestamp + 1);

        vm.prank(otherUser);
        uint256[] memory amounts =
            router.swapTokensForExactTokens(1 ether, required[0], path, otherUser, block.timestamp + 1);
        assertEq(amounts[1], 1 ether);
    }

    function test_addAndRemoveLiquidityLCAI_roundTrip() public {
        deal(otherUser, 10 ether);

        vm.prank(otherUser);
        (,, uint256 liquidity) = router.addLiquidityLCAI{value: 4 ether}(
            address(tokenA), 1 ether, 0.99 ether, 3.99 ether, otherUser, block.timestamp + 1
        );
        assertGt(liquidity, 0);

        address pairAddr = factory.getPair(address(tokenA), address(wlcai));
        HikariPair p = HikariPair(pairAddr);

        vm.prank(otherUser);
        p.approve(address(router), type(uint256).max);

        uint256 lcaiBefore = otherUser.balance;
        uint256 tokenABefore = tokenA.balanceOf(otherUser);

        vm.prank(otherUser);
        router.removeLiquidityLCAI(address(tokenA), liquidity, 0, 0, otherUser, block.timestamp + 1);

        assertGt(otherUser.balance, lcaiBefore, "no LCAI returned");
        assertGt(tokenA.balanceOf(otherUser), tokenABefore, "no tokenA returned");
    }

    function test_swapExactLCAIForTokens_works() public {
        deal(otherUser, 10 ether);

        // Add LCAI/tokenA pair first.
        vm.prank(otherUser);
        router.addLiquidityLCAI{value: 4 ether}(address(tokenA), 1 ether, 0, 0, otherUser, block.timestamp + 1);

        address[] memory path = new address[](2);
        path[0] = address(wlcai);
        path[1] = address(tokenA);

        uint256 balBefore = tokenA.balanceOf(otherUser);
        vm.prank(otherUser);
        router.swapExactLCAIForTokens{value: 0.1 ether}(0, path, otherUser, block.timestamp + 1);
        assertGt(tokenA.balanceOf(otherUser), balBefore);
    }

    function test_receive_rejectsNonWLCAI() public {
        // Random EOA cannot send LCAI to the router.
        deal(user, 1 ether);
        vm.prank(user);
        (bool ok,) = address(router).call{value: 1 ether}("");
        assertFalse(ok, "router should reject LCAI from non-WLCAI senders");
    }
}
