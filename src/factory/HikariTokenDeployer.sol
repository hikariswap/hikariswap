// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {StandardToken} from "../templates/StandardToken.sol";
import {MintableToken} from "../templates/MintableToken.sol";
import {BurnableToken} from "../templates/BurnableToken.sol";
import {TaxToken} from "../templates/TaxToken.sol";

/// @title HikariTokenDeployer
/// @notice Holds the creation bytecode of all four token templates and exposes
///         narrow CREATE2 deployment entry points. HikariTokenFactory delegates
///         here so its own bytecode stays well under EIP-170 (24,576 bytes).
/// @dev    The deployer is bound to exactly one factory via a one-shot
///         `initFactory` call. Until bound the deployer is inert; after binding
///         only that factory can call any deploy function. The binding can
///         never be changed, which makes the deployer's permission surface
///         trivial to audit.
contract HikariTokenDeployer {
    address public factory;

    error AlreadyBound();
    error OnlyFactory();
    error ZeroFactory();

    modifier onlyFactory() {
        if (msg.sender != factory) revert OnlyFactory();
        _;
    }

    /// @notice Bind this deployer to a single factory. Reverts if already bound
    ///         or if `factory_` is zero. Intended to be called once from the
    ///         deploy script directly after both contracts exist.
    function initFactory(address factory_) external {
        if (factory != address(0)) revert AlreadyBound();
        if (factory_ == address(0)) revert ZeroFactory();
        factory = factory_;
    }

    function deployStandard(
        bytes32 salt,
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address mintTo
    ) external onlyFactory returns (address token) {
        token = address(new StandardToken{salt: salt}(name_, symbol_, decimals_, totalSupply_, mintTo));
    }

    function deployMintable(
        bytes32 salt,
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 initialSupply,
        uint256 maxSupply,
        address mintTo,
        address owner_
    ) external onlyFactory returns (address token) {
        token = address(
            new MintableToken{salt: salt}(name_, symbol_, decimals_, initialSupply, maxSupply, mintTo, owner_)
        );
    }

    function deployBurnable(
        bytes32 salt,
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address mintTo
    ) external onlyFactory returns (address token) {
        token = address(new BurnableToken{salt: salt}(name_, symbol_, decimals_, totalSupply_, mintTo));
    }

    function deployTax(
        bytes32 salt,
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        uint16 buyTaxBps,
        uint16 sellTaxBps,
        address taxRecipient,
        address mintTo,
        address owner_
    ) external onlyFactory returns (address token) {
        token = address(
            new TaxToken{salt: salt}(
                name_, symbol_, decimals_, totalSupply_, buyTaxBps, sellTaxBps, taxRecipient, mintTo, owner_
            )
        );
    }
}
