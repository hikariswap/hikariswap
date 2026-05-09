// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Base} from "../Base.t.sol";
import {HikariPair} from "../../src/core/HikariPair.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {PairHandler} from "./PairHandler.sol";

/// @notice Invariant suite for HikariPair under randomised multi-actor activity.
///         Foundry's invariant runner picks random calls on PairHandler and
///         after each tx asserts everything in this contract that begins with
///         `invariant_`.
contract PairInvariantTest is Base {
    PairHandler internal handler;
    HikariPair internal pair;
    MockERC20 internal token0;
    MockERC20 internal token1;
    address[] internal actors;

    function setUp() public {
        deployHikari();

        // Deterministic ordering, so token0 < token1.
        MockERC20 a = new MockERC20("A", "A", 18);
        MockERC20 b = new MockERC20("B", "B", 18);
        if (address(a) > address(b)) (a, b) = (b, a);
        token0 = a;
        token1 = b;
        pair = HikariPair(factory.createPair(address(token0), address(token1)));

        // Seed initial liquidity so swaps have something to chew.
        token0.mint(user, 1000 ether);
        token1.mint(user, 1000 ether);
        vm.startPrank(user);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        router.addLiquidity(address(token0), address(token1), 100 ether, 100 ether, 0, 0, user, type(uint256).max);
        vm.stopPrank();

        actors = new address[](3);
        actors[0] = user;
        actors[1] = otherUser;
        actors[2] = makeAddr("invariantActor3");

        handler = new PairHandler(factory, router, pair, token0, token1, actors);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PairHandler.swap.selector;
        selectors[1] = PairHandler.addLiquidity.selector;
        selectors[2] = PairHandler.removeLiquidity.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice Pair must hold at least its reserves' worth of each token. If a
    ///         caller has transferred extra tokens since the last sync, the
    ///         pair's balance > reserves; never the other way around.
    function invariant_balancesGEReserves() public view {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertGe(token0.balanceOf(address(pair)), r0, "pair token0 balance < reserve0");
        assertGe(token1.balanceOf(address(pair)), r1, "pair token1 balance < reserve1");
    }

    /// @notice LP totalSupply must equal the sum of all holders + the locked
    ///         MINIMUM_LIQUIDITY at address(0). i.e. no LP shares are minted
    ///         or burnt off-book.
    function invariant_lpTotalSupplyMatchesAccounting() public view {
        uint256 sum = pair.balanceOf(address(0));
        sum += pair.balanceOf(address(pair));
        sum += pair.balanceOf(address(feeCollector));
        for (uint256 i; i < actors.length; ++i) {
            sum += pair.balanceOf(actors[i]);
        }
        assertEq(pair.totalSupply(), sum, "LP supply does not equal sum of known holders");
    }

    /// @notice MINIMUM_LIQUIDITY must remain locked at address(0) forever.
    function invariant_minimumLiquidityLocked() public view {
        assertEq(pair.balanceOf(address(0)), pair.MINIMUM_LIQUIDITY(), "min-liquidity moved");
    }

    /// @notice At least one mint must have occurred (sanity for the seed setup).
    function invariant_callSummary() public view {
        assertGe(pair.totalSupply(), pair.MINIMUM_LIQUIDITY(), "supply collapsed");
    }
}
