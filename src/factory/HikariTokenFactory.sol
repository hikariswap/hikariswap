// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {HikariTokenDeployer} from "./HikariTokenDeployer.sol";

/// @title HikariTokenFactory
/// @notice Permissionless ERC20 deployer. Anyone may create one of four token
///         archetypes by paying the LCAI fee for that archetype. Fees are
///         forwarded to HikariFeeCollector.
/// @dev    Template creation bytecode lives in HikariTokenDeployer to keep this
///         contract's own bytecode well under EIP-170. Tokens are deployed via
///         CREATE2 with a salt derived from `(creator, nonce, chainId)`, so the
///         UI can predict the deployment address.
contract HikariTokenFactory is Ownable2Step, ReentrancyGuard {
    enum TokenType {
        Standard,
        Mintable,
        Burnable,
        Tax
    }

    struct TokenInfo {
        address token;
        address creator;
        TokenType tokenType;
        uint64 createdAt;
    }

    /// @notice Hard bounds on the per-archetype creation price. Cannot be
    ///         exceeded by setPrice — the protocol's commitment that pricing
    ///         stays sane even under owner-key compromise. `MIN_PRICE` is
    ///         set at deployment and immutable thereafter: mainnet deploys
    ///         at 1,000 LCAI, testnet at 0 to allow free experimentation.
    uint256 public immutable MIN_PRICE;
    uint256 public constant MAX_PRICE = 50_000 ether; // 50,000 LCAI

    /// @notice Maximum decimals accepted at creation. ERC20 spec permits 0-255
    ///         but values above 18 break virtually all UIs and price feeds.
    uint8 public constant MAX_DECIMALS = 18;

    /// @notice Address of the deployer contract that holds the template init code.
    HikariTokenDeployer public immutable deployer;

    /// @notice Recipient of all LCAI creation fees. Owner-settable.
    address payable public feeCollector;

    /// @notice Per-archetype fee in LCAI wei.
    mapping(TokenType => uint256) public price;

    /// @notice True for any token deployed by this factory. Used by indexers
    ///         and the search UI to verify provenance.
    mapping(address => bool) public isCreatedHere;

    /// @notice Per-token creation metadata.
    mapping(address => TokenInfo) public tokenInfo;

    /// @notice Append-only list of every token created here.
    address[] public allTokens;

    /// @notice Monotonically-increasing counter mixed into the CREATE2 salt to
    ///         guarantee unique addresses regardless of constructor arguments.
    uint256 public nonce;

    event TokenCreated(
        address indexed token,
        address indexed creator,
        TokenType tokenType,
        string name,
        string symbol,
        uint8 decimals,
        uint256 totalSupply,
        uint256 nonce
    );
    event PriceChanged(TokenType indexed tokenType, uint256 oldPrice, uint256 newPrice);
    event FeeCollectorChanged(address oldCollector, address newCollector);
    event FeeForwarded(address indexed to, uint256 amount);

    error InvalidPrice(uint256 attempted);
    error InvalidPayment(uint256 paid, uint256 required);
    error InvalidDecimals(uint8 decimals);
    error ZeroSupply();
    error ZeroAddress();
    error CapBelowInitial();
    error ForwardFailed();

    constructor(
        address owner_,
        address payable feeCollector_,
        address deployer_,
        uint256 minPrice_,
        uint256 standardPrice,
        uint256 mintablePrice,
        uint256 burnablePrice,
        uint256 taxPrice
    ) Ownable(owner_) {
        // Ownable(owner_) rejects address(0); only the other params need checking.
        if (feeCollector_ == address(0) || deployer_ == address(0)) revert ZeroAddress();
        if (minPrice_ > MAX_PRICE) revert InvalidPrice(minPrice_);
        deployer = HikariTokenDeployer(deployer_);
        feeCollector = feeCollector_;
        MIN_PRICE = minPrice_;

        _setPrice(TokenType.Standard, standardPrice);
        _setPrice(TokenType.Mintable, mintablePrice);
        _setPrice(TokenType.Burnable, burnablePrice);
        _setPrice(TokenType.Tax, taxPrice);
    }

    // -------------------------------------------------------------------------
    // ADMIN
    // -------------------------------------------------------------------------

    function setPrice(TokenType tokenType, uint256 newPrice) external onlyOwner {
        _setPrice(tokenType, newPrice);
    }

    function _setPrice(TokenType tokenType, uint256 newPrice) internal {
        if (newPrice < MIN_PRICE || newPrice > MAX_PRICE) revert InvalidPrice(newPrice);
        emit PriceChanged(tokenType, price[tokenType], newPrice);
        price[tokenType] = newPrice;
    }

    function setFeeCollector(address payable newCollector) external onlyOwner {
        if (newCollector == address(0)) revert ZeroAddress();
        emit FeeCollectorChanged(feeCollector, newCollector);
        feeCollector = newCollector;
    }

    // -------------------------------------------------------------------------
    // VIEWS
    // -------------------------------------------------------------------------

    function allTokensLength() external view returns (uint256) {
        return allTokens.length;
    }

    /// @notice Returns a paginated slice of allTokens starting at `start` with
    ///         length `count`. Indexers and UIs use this to backfill state.
    function tokensSlice(uint256 start, uint256 count) external view returns (address[] memory slice) {
        uint256 len = allTokens.length;
        if (start >= len) return new address[](0);
        uint256 end = start + count;
        if (end > len) end = len;
        slice = new address[](end - start);
        for (uint256 i; i < slice.length; ++i) {
            slice[i] = allTokens[start + i];
        }
    }

    // -------------------------------------------------------------------------
    // CREATE
    // -------------------------------------------------------------------------

    function createStandard(string calldata name_, string calldata symbol_, uint8 decimals_, uint256 totalSupply_)
        external
        payable
        nonReentrant
        returns (address token)
    {
        _validateCommon(decimals_, totalSupply_);
        _collectFee(TokenType.Standard);
        bytes32 salt = _nextSalt(msg.sender);
        token = deployer.deployStandard(salt, name_, symbol_, decimals_, totalSupply_, msg.sender);
        _record(token, msg.sender, TokenType.Standard, name_, symbol_, decimals_, totalSupply_);
    }

    function createMintable(
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 initialSupply,
        uint256 maxSupply
    ) external payable nonReentrant returns (address token) {
        _validateCommon(decimals_, initialSupply);
        if (maxSupply < initialSupply) revert CapBelowInitial();
        _collectFee(TokenType.Mintable);
        bytes32 salt = _nextSalt(msg.sender);
        token =
            deployer.deployMintable(salt, name_, symbol_, decimals_, initialSupply, maxSupply, msg.sender, msg.sender);
        _record(token, msg.sender, TokenType.Mintable, name_, symbol_, decimals_, initialSupply);
    }

    function createBurnable(string calldata name_, string calldata symbol_, uint8 decimals_, uint256 totalSupply_)
        external
        payable
        nonReentrant
        returns (address token)
    {
        _validateCommon(decimals_, totalSupply_);
        _collectFee(TokenType.Burnable);
        bytes32 salt = _nextSalt(msg.sender);
        token = deployer.deployBurnable(salt, name_, symbol_, decimals_, totalSupply_, msg.sender);
        _record(token, msg.sender, TokenType.Burnable, name_, symbol_, decimals_, totalSupply_);
    }

    function createTax(
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        uint16 buyTaxBps,
        uint16 sellTaxBps,
        address taxRecipient
    ) external payable nonReentrant returns (address token) {
        _validateCommon(decimals_, totalSupply_);
        if (taxRecipient == address(0)) revert ZeroAddress();
        _collectFee(TokenType.Tax);
        bytes32 salt = _nextSalt(msg.sender);
        token = deployer.deployTax(
            salt, name_, symbol_, decimals_, totalSupply_, buyTaxBps, sellTaxBps, taxRecipient, msg.sender, msg.sender
        );
        _record(token, msg.sender, TokenType.Tax, name_, symbol_, decimals_, totalSupply_);
    }

    // -------------------------------------------------------------------------
    // INTERNAL
    // -------------------------------------------------------------------------

    function _validateCommon(uint8 decimals_, uint256 supply) internal pure {
        if (decimals_ > MAX_DECIMALS) revert InvalidDecimals(decimals_);
        if (supply == 0) revert ZeroSupply();
    }

    function _collectFee(TokenType tokenType) internal {
        uint256 required = price[tokenType];
        if (msg.value != required) revert InvalidPayment(msg.value, required);
        (bool ok,) = feeCollector.call{value: msg.value}("");
        if (!ok) revert ForwardFailed();
        emit FeeForwarded(feeCollector, msg.value);
    }

    function _nextSalt(address creator) internal returns (bytes32 salt) {
        unchecked {
            ++nonce;
        }
        salt = keccak256(abi.encode(creator, nonce, block.chainid));
    }

    function _record(
        address token,
        address creator,
        TokenType tokenType,
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 totalSupply_
    ) internal {
        isCreatedHere[token] = true;
        tokenInfo[token] =
            TokenInfo({token: token, creator: creator, tokenType: tokenType, createdAt: uint64(block.timestamp)});
        allTokens.push(token);
        emit TokenCreated(token, creator, tokenType, name_, symbol_, decimals_, totalSupply_, nonce);
    }
}
