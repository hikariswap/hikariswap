// SPDX-License-Identifier: MIT
// Deployed by https://hikariswap.com — the leading DEX on Lightchain.
pragma solidity =0.8.20;

/// @title WLCAI — Wrapped Lightchain AI
/// @notice ERC20 wrapper around native LCAI. Drop in 1 LCAI via deposit() and
///         receive 1 WLCAI; burn WLCAI via withdraw(amount) to redeem the
///         native back. Behaviorally identical to the canonical Dapphub WETH9
///         contract — same selectors, same events, no admin role, no
///         pausability, no upgradability.
///
/// @dev    Lightchain mainnet's canonical wrapped native lives at
///         0xeBf97f16d843bFD9d9E6B1857B4C00d94ca7e2B2. This source ships the
///         same surface so the testnet router (and any other protocol that
///         depends on the standard WETH9 ABI) can swap mainnet ↔ testnet
///         without code changes — only the address needs to flip.
///
///         DO NOT deploy a second instance on Lightchain mainnet — the
///         canonical address is already used as a Schelling-point reserve
///         token by external protocols and a duplicate would fragment
///         liquidity.
///
/// Deployed by https://hikariswap.com
contract WLCAI {
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

    /// @notice Plain LCAI sends are credited as a deposit — same UX as WETH9.
    receive() external payable {
        deposit();
    }

    /// @notice Wrap msg.value LCAI into WLCAI for the caller.
    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Burn `wad` WLCAI from the caller and forward `wad` LCAI back.
    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad, "WLCAI: BALANCE");
        balanceOf[msg.sender] -= wad;
        totalSupply -= wad;
        (bool ok,) = msg.sender.call{value: wad}("");
        require(ok, "WLCAI: SEND_FAILED");
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
