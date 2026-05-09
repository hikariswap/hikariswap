// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.20;

/// @title IWLCAI
/// @notice Minimal interface for the canonical Wrapped LCAI contract on
///         Lightchain mainnet at 0xeBf97f16d843bFD9d9E6B1857B4C00d94ca7e2B2
///         (a verbatim Dapphub WETH9 fork compiled with 0.4.18, no admin).
/// @dev    Only the functions HikariRouter actually calls are declared.
interface IWLCAI {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}
