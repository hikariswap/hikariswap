// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.20;

/// @title TransferHelper
/// @notice Wrappers around ERC20 transfer/approve calls that tolerate
///         non-standard tokens (returning bytes empty or false), plus a
///         safe native-coin sender for refund and unwrap paths.
library TransferHelper {
    /// @dev bytes4(keccak256(bytes("approve(address,uint256)")))
    bytes4 private constant SELECTOR_APPROVE = 0x095ea7b3;
    /// @dev bytes4(keccak256(bytes("transfer(address,uint256)")))
    bytes4 private constant SELECTOR_TRANSFER = 0xa9059cbb;
    /// @dev bytes4(keccak256(bytes("transferFrom(address,address,uint256)")))
    bytes4 private constant SELECTOR_TRANSFER_FROM = 0x23b872dd;

    function safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR_APPROVE, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TH: APPROVE_FAILED");
    }

    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR_TRANSFER, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TH: TRANSFER_FAILED");
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR_TRANSFER_FROM, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TH: TRANSFER_FROM_FAILED");
    }

    function safeTransferLCAI(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "TH: LCAI_TRANSFER_FAILED");
    }
}
