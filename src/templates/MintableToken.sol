// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title MintableToken
/// @notice ERC20 with an owner who can mint new tokens up to a hard supply cap
///         set at deploy. The cap can never be raised. Ownership uses
///         Ownable2Step to prevent fat-finger transfers.
contract MintableToken is ERC20, Ownable2Step {
    /// @notice Hard upper bound on totalSupply. Immutable, cannot be changed.
    uint256 public immutable maxSupply;

    uint8 private immutable _DECIMALS;

    error CapExceeded(uint256 attempted, uint256 cap);

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply,
        uint256 maxSupply_,
        address mintTo,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        require(mintTo != address(0) && owner_ != address(0), "MintToken: ZERO_ADDRESS");
        require(maxSupply_ >= initialSupply, "MintToken: CAP_BELOW_INITIAL");
        _DECIMALS = decimals_;
        maxSupply = maxSupply_;
        _mint(mintTo, initialSupply);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        uint256 newSupply = totalSupply() + amount;
        if (newSupply > maxSupply) revert CapExceeded(newSupply, maxSupply);
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }
}
