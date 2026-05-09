// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.20;

/// @title IHikariCallee
/// @notice Callback interface for HikariPair flash swaps. Contracts that wish to
///         receive flash-swapped tokens must implement this.
interface IHikariCallee {
    function hikariCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
