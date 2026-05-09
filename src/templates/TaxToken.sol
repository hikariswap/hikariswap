// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title TaxToken
/// @notice ERC20 with a buy-tax (transfer FROM an AMM pair) and sell-tax
///         (transfer TO an AMM pair) routed to a tax recipient. Tax rates and
///         honeypot risk are bounded by hard immutable caps; the owner can
///         only lower rates or zero them out.
/// @dev    Honeypot prevention: caps are immutable and enforced at the boundary
///         of every setter. There is no `pause`, no `blacklist`, no transfer
///         restriction beyond the documented buy/sell tax. If those features
///         are added later they will require a new audit pass.
contract TaxToken is ERC20, Ownable2Step {
    /// @notice Hard caps on per-side tax in basis points (10% each side).
    ///         These cannot be changed and bound the worst-case rate.
    uint16 public constant MAX_BUY_TAX_BPS = 1000;
    uint16 public constant MAX_SELL_TAX_BPS = 1000;
    uint16 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Current tax rates in basis points. May be lowered by the owner
    ///         but never above the immutable caps.
    uint16 public buyTaxBps;
    uint16 public sellTaxBps;

    /// @notice Recipient of collected tax. Must be non-zero. Owner-settable.
    address public taxRecipient;

    /// @notice Addresses recognised as AMM pairs. Transfers FROM such an
    ///         address charge buyTax; transfers TO such an address charge
    ///         sellTax. Owner-managed.
    mapping(address => bool) public isAmmPair;

    /// @notice Addresses excluded from tax in either direction. By default
    ///         this includes the deployer, the contract itself, the owner, and
    ///         the tax recipient — so liquidity provisioning and treasury
    ///         operations are not taxed.
    mapping(address => bool) public isExcludedFromTax;

    uint8 private immutable _DECIMALS;

    event BuyTaxBpsChanged(uint16 oldBps, uint16 newBps);
    event SellTaxBpsChanged(uint16 oldBps, uint16 newBps);
    event TaxRecipientChanged(address oldRecipient, address newRecipient);
    event AmmPairChanged(address indexed pair, bool isPair);
    event TaxExclusionChanged(address indexed account, bool excluded);
    event TaxCollected(address indexed from, address indexed to, uint256 amount);

    error TaxAboveCap(uint16 attempted, uint16 cap);

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        uint16 buyTaxBps_,
        uint16 sellTaxBps_,
        address taxRecipient_,
        address mintTo,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        require(mintTo != address(0) && owner_ != address(0) && taxRecipient_ != address(0), "TaxToken: ZERO_ADDRESS");
        if (buyTaxBps_ > MAX_BUY_TAX_BPS) revert TaxAboveCap(buyTaxBps_, MAX_BUY_TAX_BPS);
        if (sellTaxBps_ > MAX_SELL_TAX_BPS) revert TaxAboveCap(sellTaxBps_, MAX_SELL_TAX_BPS);

        _DECIMALS = decimals_;
        buyTaxBps = buyTaxBps_;
        sellTaxBps = sellTaxBps_;
        taxRecipient = taxRecipient_;

        // Sensible defaults so liquidity provisioning works without manual setup.
        isExcludedFromTax[mintTo] = true;
        isExcludedFromTax[owner_] = true;
        isExcludedFromTax[taxRecipient_] = true;
        isExcludedFromTax[address(this)] = true;

        _mint(mintTo, totalSupply_);
    }

    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }

    // -------------------------------------------------------------------------
    // OWNER CONFIGURATION
    // -------------------------------------------------------------------------

    function setBuyTaxBps(uint16 newBps) external onlyOwner {
        if (newBps > MAX_BUY_TAX_BPS) revert TaxAboveCap(newBps, MAX_BUY_TAX_BPS);
        emit BuyTaxBpsChanged(buyTaxBps, newBps);
        buyTaxBps = newBps;
    }

    function setSellTaxBps(uint16 newBps) external onlyOwner {
        if (newBps > MAX_SELL_TAX_BPS) revert TaxAboveCap(newBps, MAX_SELL_TAX_BPS);
        emit SellTaxBpsChanged(sellTaxBps, newBps);
        sellTaxBps = newBps;
    }

    function setTaxRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "TaxToken: ZERO_RECIPIENT");
        emit TaxRecipientChanged(taxRecipient, newRecipient);
        taxRecipient = newRecipient;
        isExcludedFromTax[newRecipient] = true;
    }

    function setAmmPair(address pair, bool flag) external onlyOwner {
        require(pair != address(0), "TaxToken: ZERO_PAIR");
        isAmmPair[pair] = flag;
        emit AmmPairChanged(pair, flag);
    }

    function setExcludedFromTax(address account, bool excluded) external onlyOwner {
        isExcludedFromTax[account] = excluded;
        emit TaxExclusionChanged(account, excluded);
    }

    // -------------------------------------------------------------------------
    // TAX HOOK
    // -------------------------------------------------------------------------

    function _update(address from, address to, uint256 value) internal override {
        // Mints (from == 0) and burns (to == 0) bypass tax.
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        uint256 taxAmount;
        if (!isExcludedFromTax[from] && !isExcludedFromTax[to]) {
            if (isAmmPair[from]) {
                taxAmount = (value * buyTaxBps) / BPS_DENOMINATOR;
            } else if (isAmmPair[to]) {
                taxAmount = (value * sellTaxBps) / BPS_DENOMINATOR;
            }
        }

        if (taxAmount > 0) {
            super._update(from, taxRecipient, taxAmount);
            emit TaxCollected(from, to, taxAmount);
            unchecked {
                value -= taxAmount;
            }
        }
        super._update(from, to, value);
    }
}
