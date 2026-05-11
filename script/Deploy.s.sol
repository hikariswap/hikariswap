// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {HikariFactory} from "../src/core/HikariFactory.sol";
import {HikariRouter} from "../src/periphery/HikariRouter.sol";
import {HikariFeeCollector} from "../src/factory/HikariFeeCollector.sol";
import {HikariTokenDeployer} from "../src/factory/HikariTokenDeployer.sol";
import {HikariTokenFactory} from "../src/factory/HikariTokenFactory.sol";
import {HikariLocker} from "../src/locker/HikariLocker.sol";

/// @title Deploy
/// @notice Full deployment of HikariSwap. Runs the entire bring-up sequence in
///         one transaction batch: 8 contracts + 2 wiring calls. Reads the
///         deployer key and (optionally) the WLCAI address from environment.
///         For mainnet, WLCAI defaults to the canonical Lightchain address; on
///         testnet, WLCAI_ADDRESS must be set (run DeployTestWLCAI first).
contract DeployScript is Script {
    /// @notice Canonical Lightchain wrapped native. Deployed at the same
    ///         address on mainnet (chainid 9200) and testnet (chainid 8200).
    address internal constant CANONICAL_WLCAI = 0xeBf97f16d843bFD9d9E6B1857B4C00d94ca7e2B2;

    /// @notice Flat 5,000 LCAI per archetype.
    uint256 internal constant TOKEN_PRICE = 5_000 ether;

    /// @notice Per-chain MIN_PRICE floor. Mainnet enforces the audited 1,000
    ///         LCAI minimum; testnet allows free creation for end-to-end
    ///         frontend testing.
    uint256 internal constant MAINNET_MIN_PRICE = 1_000 ether;
    uint256 internal constant TESTNET_MIN_PRICE = 0;

    function run() external {
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address wlcai = _resolveWLCAI();

        require(wlcai != address(0), "Deploy: WLCAI address resolved to zero");
        require(wlcai.code.length > 0, "Deploy: WLCAI has no code at given address");

        console2.log("");
        console2.log("=== HIKARISWAP DEPLOYMENT ===");
        console2.log("Chain ID:        ", block.chainid);
        console2.log("Deployer:        ", deployer);
        console2.log("Deployer balance:", deployer.balance);
        console2.log("WLCAI:           ", wlcai);
        console2.log("Token price:     ", TOKEN_PRICE / 1 ether, "LCAI per archetype");
        console2.log("");

        require(deployer.balance > 0.1 ether, "Deploy: deployer balance below 0.1 LCAI");

        vm.startBroadcast(deployerPk);

        HikariFactory factory = new HikariFactory(deployer);
        console2.log("HikariFactory       ", address(factory));

        HikariRouter router = new HikariRouter(address(factory), wlcai);
        console2.log("HikariRouter        ", address(router));

        HikariFeeCollector feeCollector = new HikariFeeCollector(deployer);
        console2.log("HikariFeeCollector  ", address(feeCollector));

        HikariTokenDeployer tokenDeployer = new HikariTokenDeployer();
        console2.log("HikariTokenDeployer ", address(tokenDeployer));

        uint256 minPrice = block.chainid == 9200 ? MAINNET_MIN_PRICE : TESTNET_MIN_PRICE;
        uint256 standardPrice = block.chainid == 9200 ? TOKEN_PRICE : 0;
        HikariTokenFactory tokenFactory = new HikariTokenFactory(
            deployer,
            payable(address(feeCollector)),
            address(tokenDeployer),
            minPrice,
            standardPrice,
            standardPrice,
            standardPrice,
            standardPrice
        );
        console2.log("HikariTokenFactory  ", address(tokenFactory));

        // Permission-bind deployer to factory (one-shot).
        tokenDeployer.initFactory(address(tokenFactory));

        // Wire V2 protocol fees into the FeeCollector treasury.
        factory.setFeeTo(address(feeCollector));

        HikariLocker locker = new HikariLocker();
        console2.log("HikariLocker        ", address(locker));

        vm.stopBroadcast();

        // Post-deploy assertions: anything wrong here means we revert before
        // the user thinks the deploy succeeded.
        require(address(factory.feeTo()) == address(feeCollector), "feeTo mismatch");
        require(address(tokenDeployer.factory()) == address(tokenFactory), "deployer not bound");
        require(tokenFactory.price(HikariTokenFactory.TokenType.Standard) == TOKEN_PRICE, "price mismatch");

        console2.log("");
        console2.log("=== DEPLOYMENT COMPLETE ===");
        console2.log("Save these addresses to .env and the README:");
        console2.log("");
        console2.log("WLCAI_ADDRESS=%s", wlcai);
        console2.log("HIKARI_FACTORY=%s", address(factory));
        console2.log("HIKARI_ROUTER=%s", address(router));
        console2.log("HIKARI_FEE_COLLECTOR=%s", address(feeCollector));
        console2.log("HIKARI_TOKEN_DEPLOYER=%s", address(tokenDeployer));
        console2.log("HIKARI_TOKEN_FACTORY=%s", address(tokenFactory));
        console2.log("HIKARI_LOCKER=%s", address(locker));
    }

    /// @dev Env override wins; otherwise default to the canonical address
    ///      (deployed on both Lightchain mainnet and testnet).
    function _resolveWLCAI() internal view returns (address) {
        try vm.envAddress("WLCAI_ADDRESS") returns (address envWlcai) {
            return envWlcai;
        } catch {
            require(
                block.chainid == 9200 || block.chainid == 8200,
                "Deploy: unknown chain, set WLCAI_ADDRESS explicitly"
            );
            return CANONICAL_WLCAI;
        }
    }
}
