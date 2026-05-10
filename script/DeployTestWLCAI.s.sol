// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Script, console2} from "forge-std/Script.sol";

/// @title TestWLCAI
/// @notice Deployable test-only Wrapped LCAI for the Lightchain testnet (chain
///         id 8200). Behaviourally equivalent to the canonical Dapphub WETH9
///         that lives on Lightchain mainnet at
///         0xeBf97f16d843bFD9d9E6B1857B4C00d94ca7e2B2 — same `deposit`,
///         `withdraw`, ERC20 surface, no admin functions.
/// @dev    DO NOT deploy this on mainnet. The mainnet WLCAI already exists; a
///         second one would fragment liquidity for every protocol.
contract TestWLCAI {
    string public constant name = "Wrapped LightchainAI";
    string public constant symbol = "WLCAI";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad, "WLCAI: BALANCE");
        balanceOf[msg.sender] -= wad;
        totalSupply -= wad;
        (bool ok,) = msg.sender.call{value: wad}("");
        require(ok, "WLCAI: SEND");
        emit Withdrawal(msg.sender, wad);
    }

    function approve(address guy, uint256 wad) external returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) external returns (bool) {
        return _transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) external returns (bool) {
        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad, "WLCAI: ALLOWANCE");
            allowance[src][msg.sender] -= wad;
        }
        return _transferFrom(src, dst, wad);
    }

    function _transferFrom(address src, address dst, uint256 wad) internal returns (bool) {
        require(balanceOf[src] >= wad, "WLCAI: BALANCE");
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        emit Transfer(src, dst, wad);
        return true;
    }
}

/// @notice Bootstrap script for Lightchain testnet only. Deploys a WLCAI clone
///         so HikariSwap has a wrapped-native to point at. Run once per
///         testnet, before `Deploy.s.sol`.
contract DeployTestWLCAIScript is Script {
    function run() external {
        require(block.chainid == 8200, "TestWLCAI: refuse to deploy on non-testnet chain");

        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        console2.log("Chain ID:        ", block.chainid);
        console2.log("Deployer:        ", deployer);
        console2.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPk);
        TestWLCAI wlcai = new TestWLCAI();
        vm.stopBroadcast();

        console2.log("");
        console2.log("=== TESTNET WLCAI DEPLOYED ===");
        console2.log("WLCAI:", address(wlcai));
        console2.log("");
        console2.log("Add to your .env before running Deploy.s.sol:");
        console2.log("WLCAI_ADDRESS=%s", address(wlcai));
    }
}
