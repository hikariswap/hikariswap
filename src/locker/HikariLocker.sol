// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title HikariLocker
/// @notice Trustless time-lock vault for arbitrary ERC20 balances. Primarily
///         used to lock HikariSwap LP tokens (so token creators can
///         demonstrate non-rug liquidity) and HikariTokenFactory tokens (team
///         allocations). Each lock is independent: own the lock, set the
///         unlock time, withdraw after expiry. The contract has no admin, no
///         pause, no upgrade path — once a lock is created, only its owner
///         can extend it (forward in time only) or withdraw after expiry.
contract HikariLocker is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Lock {
        address token;
        address owner;
        uint128 amount;
        uint64 unlockAt;
        bool withdrawn;
    }

    /// @notice Append-only list of every lock. The lock id is the index.
    Lock[] public locks;

    /// @notice For UI: every lock id ever owned by `owner`. May contain ids
    ///         no longer owned by `owner` if the owner withdrew. Frontend
    ///         filters on `locks[id].owner == owner` and `!withdrawn`.
    mapping(address => uint256[]) public locksByOwner;

    /// @notice For UI / indexers: every lock id targeting `token`.
    mapping(address => uint256[]) public locksByToken;

    /// @notice Hard upper bound on lock duration. Picked to fit `unlockAt`
    ///         into uint64 with comfortable margin and to prevent griefing
    ///         users into permanent locks via an absurd timestamp.
    uint64 public constant MAX_LOCK_DURATION = 100 * 365 days;

    event LockCreated(
        uint256 indexed id, address indexed token, address indexed owner, uint256 amount, uint256 unlockAt
    );
    event LockExtended(uint256 indexed id, uint256 oldUnlockAt, uint256 newUnlockAt);
    event LockWithdrawn(uint256 indexed id, address indexed to, uint256 amount);

    error PastUnlock();
    error DurationTooLong();
    error ZeroAmount();
    error ZeroAddress();
    error AmountTooLarge();
    error NoTokensReceived();
    error NotOwner();
    error AlreadyWithdrawn();
    error CannotShorten();
    error StillLocked();

    /// @notice Lock `amount` of `token` until `unlockAt`. After expiry, only
    ///         `beneficiary` may withdraw. Caller must approve `amount` first.
    /// @dev    Uses balance-before / balance-after to record the actual amount
    ///         received; this is correct for fee-on-transfer tokens (e.g.
    ///         tokens deployed via HikariTokenFactory's TaxToken template).
    function lock(address token, uint256 amount, uint64 unlockAt, address beneficiary)
        external
        nonReentrant
        returns (uint256 id)
    {
        if (token == address(0) || beneficiary == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (unlockAt <= block.timestamp) revert PastUnlock();
        if (unlockAt > block.timestamp + MAX_LOCK_DURATION) revert DurationTooLong();
        if (amount > type(uint128).max) revert AmountTooLarge();

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - balanceBefore;
        if (received == 0) revert NoTokensReceived();
        if (received > type(uint128).max) revert AmountTooLarge();

        id = locks.length;
        locks.push(
            Lock({
                token: token,
                owner: beneficiary,
                amount: uint128(received),
                unlockAt: unlockAt,
                withdrawn: false
            })
        );
        locksByOwner[beneficiary].push(id);
        locksByToken[token].push(id);

        emit LockCreated(id, token, beneficiary, received, unlockAt);
    }

    /// @notice Extend a lock further into the future. Cannot shorten — that
    ///         would defeat the entire purpose of the contract.
    function extend(uint256 id, uint64 newUnlockAt) external {
        Lock storage l = locks[id];
        if (msg.sender != l.owner) revert NotOwner();
        if (l.withdrawn) revert AlreadyWithdrawn();
        if (newUnlockAt <= l.unlockAt) revert CannotShorten();
        if (newUnlockAt > block.timestamp + MAX_LOCK_DURATION) revert DurationTooLong();

        uint64 old = l.unlockAt;
        l.unlockAt = newUnlockAt;
        emit LockExtended(id, old, newUnlockAt);
    }

    /// @notice After `unlockAt`, transfer the locked amount to the owner.
    function withdraw(uint256 id) external nonReentrant {
        Lock storage l = locks[id];
        if (msg.sender != l.owner) revert NotOwner();
        if (l.withdrawn) revert AlreadyWithdrawn();
        if (block.timestamp < l.unlockAt) revert StillLocked();

        l.withdrawn = true;
        uint256 amount = l.amount;
        address to = l.owner;
        address token = l.token;
        IERC20(token).safeTransfer(to, amount);
        emit LockWithdrawn(id, to, amount);
    }

    // ---- views ---------------------------------------------------------------

    function locksLength() external view returns (uint256) {
        return locks.length;
    }

    function locksByOwnerLength(address owner) external view returns (uint256) {
        return locksByOwner[owner].length;
    }

    function locksByTokenLength(address token) external view returns (uint256) {
        return locksByToken[token].length;
    }
}
