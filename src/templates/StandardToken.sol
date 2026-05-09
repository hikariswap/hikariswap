// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title StandardToken
/// @notice Plain ERC20 with a fixed total supply minted once to `mintTo`. No
///         minting after deploy. No burn. No tax. No owner. Deliberately
///         minimal — auditors should be able to read this in 30 seconds.
contract StandardToken is ERC20 {
    uint8 private immutable _DECIMALS;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 totalSupply_, address mintTo)
        ERC20(name_, symbol_)
    {
        require(mintTo != address(0), "StdToken: ZERO_MINT_TO");
        _DECIMALS = decimals_;
        _mint(mintTo, totalSupply_);
    }

    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }
}
