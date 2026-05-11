// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Test} from "forge-std/Test.sol";

import {HikariFactory} from "../src/core/HikariFactory.sol";
import {HikariPair} from "../src/core/HikariPair.sol";
import {HikariRouter} from "../src/periphery/HikariRouter.sol";
import {HikariTokenFactory} from "../src/factory/HikariTokenFactory.sol";
import {HikariTokenDeployer} from "../src/factory/HikariTokenDeployer.sol";
import {HikariFeeCollector} from "../src/factory/HikariFeeCollector.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWLCAI} from "./mocks/MockWLCAI.sol";

/// @notice Shared test fixtures for HikariSwap. All unit and integration tests
///         inherit from this and call `deployHikari()` (or one of its variants)
///         in their setUp.
contract Base is Test {
    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");
    address internal otherUser = makeAddr("otherUser");
    address internal taxRecipient = makeAddr("taxRecipient");

    HikariFactory internal factory;
    HikariRouter internal router;
    HikariTokenFactory internal tokenFactory;
    HikariTokenDeployer internal tokenDeployer;
    HikariFeeCollector internal feeCollector;
    MockWLCAI internal wlcai;

    // Default token-creation prices (matches mainnet config: flat 5,000 LCAI).
    uint256 internal constant MIN_PRICE = 1000 ether;
    uint256 internal constant PRICE_STANDARD = 5000 ether;
    uint256 internal constant PRICE_MINTABLE = 5000 ether;
    uint256 internal constant PRICE_BURNABLE = 5000 ether;
    uint256 internal constant PRICE_TAX = 5000 ether;

    function deployHikari() internal {
        wlcai = new MockWLCAI();

        factory = new HikariFactory(owner);
        router = new HikariRouter(address(factory), address(wlcai));

        feeCollector = new HikariFeeCollector(owner);
        tokenDeployer = new HikariTokenDeployer();
        tokenFactory = new HikariTokenFactory(
            owner,
            payable(address(feeCollector)),
            address(tokenDeployer),
            MIN_PRICE,
            PRICE_STANDARD,
            PRICE_MINTABLE,
            PRICE_BURNABLE,
            PRICE_TAX
        );
        tokenDeployer.initFactory(address(tokenFactory));

        // Wire protocol fee from V2 pairs into the FeeCollector.
        vm.prank(owner);
        factory.setFeeTo(address(feeCollector));
    }

    /// @notice Creates a fresh pair of mock tokens already approved on the router
    ///         for both `user` and `otherUser`, with a healthy starting balance.
    function makePair(uint256 amountA, uint256 amountB)
        internal
        returns (MockERC20 tokenA, MockERC20 tokenB, address pair)
    {
        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 18);

        // Deterministic ordering for tests that rely on token0/token1.
        if (address(tokenA) > address(tokenB)) (tokenA, tokenB) = (tokenB, tokenA);

        tokenA.mint(user, amountA * 1000);
        tokenB.mint(user, amountB * 1000);
        tokenA.mint(otherUser, amountA * 1000);
        tokenB.mint(otherUser, amountB * 1000);

        vm.startPrank(user);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(otherUser);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.stopPrank();

        pair = factory.createPair(address(tokenA), address(tokenB));
    }

    /// @notice Adds liquidity to an existing pair via Router.
    function addLiquidity(MockERC20 tokenA, MockERC20 tokenB, uint256 amountA, uint256 amountB, address to) internal {
        vm.prank(to);
        router.addLiquidity(address(tokenA), address(tokenB), amountA, amountB, 0, 0, to, block.timestamp + 1 days);
    }
}
