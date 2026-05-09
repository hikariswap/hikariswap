// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title HikariFeeCollector
/// @notice Treasury contract that receives:
///           - LCAI from token-creation fees forwarded by HikariTokenFactory;
///           - HikariSwap LP shares from the V2 protocol-fee mechanism (when
///             HikariFactory.feeTo is set to this contract).
///         The owner — initially the deployer EOA, later a Gnosis Safe — is
///         the only address able to withdraw funds.
/// @dev    The contract intentionally has no swap or auto-redemption logic. LP
///         shares are claimed via withdrawERC20 and processed externally
///         (multisig + UI), so audit scope here is bounded to access control
///         and safe transfer wrappers.
contract HikariFeeCollector is Ownable2Step {
    using SafeERC20 for IERC20;

    event LCAIReceived(address indexed from, uint256 amount);
    event LCAIWithdrawn(address indexed to, uint256 amount);
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error WithdrawFailed();

    /// @dev `Ownable(owner_)` rejects address(0), so no explicit check needed.
    constructor(address owner_) Ownable(owner_) {}

    receive() external payable {
        emit LCAIReceived(msg.sender, msg.value);
    }

    /// @notice Withdraw native LCAI. Reverts if the call fails.
    function withdrawLCAI(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert WithdrawFailed();
        emit LCAIWithdrawn(to, amount);
    }

    /// @notice Withdraw an arbitrary ERC20 (typically HikariSwap LP shares
    ///         from the V2 protocol fee, but works for any token).
    function withdrawERC20(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        token.safeTransfer(to, amount);
        emit ERC20Withdrawn(address(token), to, amount);
    }
}
