// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title BurnableToken
/// @notice ERC20 with a fixed initial supply and the standard burn / burnFrom
///         entry points (anyone can burn their own balance, or another
///         account's balance via allowance). No mint, no owner, no tax.
contract BurnableToken is ERC20, ERC20Burnable {
    uint8 private immutable _DECIMALS;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 totalSupply_, address mintTo)
        ERC20(name_, symbol_)
    {
        require(mintTo != address(0), "BurnToken: ZERO_MINT_TO");
        _DECIMALS = decimals_;
        _mint(mintTo, totalSupply_);
    }

    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }
}
