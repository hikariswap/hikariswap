// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Test} from "forge-std/Test.sol";
import {HikariFactory} from "../../src/core/HikariFactory.sol";
import {HikariPair} from "../../src/core/HikariPair.sol";
import {HikariRouter} from "../../src/periphery/HikariRouter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Random-action driver for invariant tests. Foundry calls the
///         external functions on this contract with random arguments; we
///         normalise inputs into valid HikariPair operations and execute them.
///         Each successful operation either preserves the k-invariant (swap)
///         or operates on liquidity (mint/burn) — see PairInvariant.t.sol for
///         the assertions that hold across any sequence of these calls.
contract PairHandler is Test {
    HikariFactory public immutable factory;
    HikariRouter public immutable router;
    HikariPair public immutable pair;
    MockERC20 public immutable token0;
    MockERC20 public immutable token1;

    address[] internal actors;
    uint256 public ghostSwaps;
    uint256 public ghostMints;
    uint256 public ghostBurns;

    constructor(
        HikariFactory factory_,
        HikariRouter router_,
        HikariPair pair_,
        MockERC20 token0_,
        MockERC20 token1_,
        address[] memory actors_
    ) {
        factory = factory_;
        router = router_;
        pair = pair_;
        token0 = token0_;
        token1 = token1_;
        actors = actors_;
    }

    function _pickActor(uint256 actorSeed) internal view returns (address) {
        return actors[actorSeed % actors.length];
    }

    function swap(uint256 actorSeed, bool zeroForOne, uint256 amountIn) external {
        address actor = _pickActor(actorSeed);
        (uint112 r0, uint112 r1,) = pair.getReserves();
        if (r0 == 0 || r1 == 0) return;

        // Bound input to a small fraction of reserves to stay within sane regimes.
        amountIn = bound(amountIn, 1, uint256(zeroForOne ? r0 : r1) / 4);

        if (zeroForOne) {
            token0.mint(actor, amountIn);
            vm.prank(actor);
            token0.transfer(address(pair), amountIn);
            // Use Library-equivalent math but keep it inline to avoid coupling.
            uint256 amountInWithFee = amountIn * 9965;
            uint256 amountOut = (amountInWithFee * uint256(r1)) / (uint256(r0) * 10_000 + amountInWithFee);
            if (amountOut == 0) return;
            vm.prank(actor);
            pair.swap(0, amountOut, actor, "");
        } else {
            token1.mint(actor, amountIn);
            vm.prank(actor);
            token1.transfer(address(pair), amountIn);
            uint256 amountInWithFee = amountIn * 9965;
            uint256 amountOut = (amountInWithFee * uint256(r0)) / (uint256(r1) * 10_000 + amountInWithFee);
            if (amountOut == 0) return;
            vm.prank(actor);
            pair.swap(amountOut, 0, actor, "");
        }
        unchecked {
            ++ghostSwaps;
        }
    }

    function addLiquidity(uint256 actorSeed, uint256 amount0, uint256 amount1) external {
        address actor = _pickActor(actorSeed);
        (uint112 r0, uint112 r1,) = pair.getReserves();

        if (r0 == 0 || r1 == 0) {
            // Pair already has initial liquidity from setup; skip if reset somehow.
            return;
        }

        // Bound to a small range proportional to reserves.
        amount0 = bound(amount0, 1e6, uint256(r0) / 2);
        // Maintain ratio so the Router won't refund unused tokens, simplifying accounting.
        amount1 = (amount0 * uint256(r1)) / uint256(r0);
        amount1 = bound(amount1, 1, uint256(r1) / 2);

        token0.mint(actor, amount0);
        token1.mint(actor, amount1);

        vm.startPrank(actor);
        token0.approve(address(router), amount0);
        token1.approve(address(router), amount1);
        try router.addLiquidity(address(token0), address(token1), amount0, amount1, 0, 0, actor, type(uint256).max) {
            unchecked {
                ++ghostMints;
            }
        } catch {
            // Mint may revert on insufficient liquidity (1 wei dust); ignore.
        }
        vm.stopPrank();
    }

    function removeLiquidity(uint256 actorSeed, uint256 lpFraction) external {
        address actor = _pickActor(actorSeed);
        uint256 bal = pair.balanceOf(actor);
        if (bal == 0) return;

        lpFraction = bound(lpFraction, 1, bal);
        vm.startPrank(actor);
        pair.approve(address(router), lpFraction);
        try router.removeLiquidity(address(token0), address(token1), lpFraction, 0, 0, actor, type(uint256).max) {
            unchecked {
                ++ghostBurns;
            }
        } catch {
            // Burn may revert if it'd drain reserves below dust; ignore.
        }
        vm.stopPrank();
    }
}
