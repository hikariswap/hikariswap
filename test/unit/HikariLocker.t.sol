// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Test} from "forge-std/Test.sol";
import {HikariLocker} from "../../src/locker/HikariLocker.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract HikariLockerTest is Test {
    HikariLocker internal locker;
    MockERC20 internal token;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        locker = new HikariLocker();
        token = new MockERC20("Tok", "TOK", 18);
        token.mint(alice, 1_000 ether);
        vm.prank(alice);
        token.approve(address(locker), type(uint256).max);
    }

    function _futureUnlock(uint256 secondsFromNow) internal view returns (uint64) {
        return uint64(block.timestamp + secondsFromNow);
    }

    // -------------------------------------------------------------------------
    // LOCK
    // -------------------------------------------------------------------------

    function test_lock_storesAndIndexes() public {
        uint64 unlockAt = _futureUnlock(7 days);
        vm.prank(alice);
        uint256 id = locker.lock(address(token), 100 ether, unlockAt, bob);

        (address tk, address owner, uint128 amount, uint64 ua, bool withdrawn) = locker.locks(id);
        assertEq(tk, address(token));
        assertEq(owner, bob);
        assertEq(amount, 100 ether);
        assertEq(ua, unlockAt);
        assertFalse(withdrawn);

        assertEq(locker.locksLength(), 1);
        assertEq(locker.locksByOwnerLength(bob), 1);
        assertEq(locker.locksByTokenLength(address(token)), 1);

        assertEq(token.balanceOf(address(locker)), 100 ether);
        assertEq(token.balanceOf(alice), 900 ether);
    }

    function test_lock_revertsOnZeroToken() public {
        vm.prank(alice);
        vm.expectRevert(HikariLocker.ZeroAddress.selector);
        locker.lock(address(0), 1 ether, _futureUnlock(1 days), bob);
    }

    function test_lock_revertsOnZeroBeneficiary() public {
        vm.prank(alice);
        vm.expectRevert(HikariLocker.ZeroAddress.selector);
        locker.lock(address(token), 1 ether, _futureUnlock(1 days), address(0));
    }

    function test_lock_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(HikariLocker.ZeroAmount.selector);
        locker.lock(address(token), 0, _futureUnlock(1 days), bob);
    }

    function test_lock_revertsOnPastUnlock() public {
        vm.prank(alice);
        vm.expectRevert(HikariLocker.PastUnlock.selector);
        locker.lock(address(token), 1 ether, uint64(block.timestamp), bob);
    }

    function test_lock_revertsOnTooLongDuration() public {
        uint64 way_future = uint64(block.timestamp) + locker.MAX_LOCK_DURATION() + 1;
        vm.prank(alice);
        vm.expectRevert(HikariLocker.DurationTooLong.selector);
        locker.lock(address(token), 1 ether, way_future, bob);
    }

    // -------------------------------------------------------------------------
    // EXTEND
    // -------------------------------------------------------------------------

    function test_extend_movesUnlockForward() public {
        vm.prank(alice);
        uint256 id = locker.lock(address(token), 1 ether, _futureUnlock(1 days), bob);

        uint64 newUnlock = _futureUnlock(30 days);
        vm.prank(bob);
        locker.extend(id, newUnlock);

        (,,, uint64 ua,) = locker.locks(id);
        assertEq(ua, newUnlock);
    }

    function test_extend_revertsForNonOwner() public {
        vm.prank(alice);
        uint256 id = locker.lock(address(token), 1 ether, _futureUnlock(1 days), bob);

        vm.prank(alice);
        vm.expectRevert(HikariLocker.NotOwner.selector);
        locker.extend(id, _futureUnlock(30 days));
    }

    function test_extend_revertsOnShortening() public {
        vm.prank(alice);
        uint256 id = locker.lock(address(token), 1 ether, _futureUnlock(30 days), bob);

        vm.prank(bob);
        vm.expectRevert(HikariLocker.CannotShorten.selector);
        locker.extend(id, _futureUnlock(1 days));
    }

    function test_extend_revertsOnSameTime() public {
        uint64 unlockAt = _futureUnlock(30 days);
        vm.prank(alice);
        uint256 id = locker.lock(address(token), 1 ether, unlockAt, bob);

        vm.prank(bob);
        vm.expectRevert(HikariLocker.CannotShorten.selector);
        locker.extend(id, unlockAt);
    }

    function test_extend_revertsAfterWithdraw() public {
        vm.prank(alice);
        uint256 id = locker.lock(address(token), 1 ether, _futureUnlock(1 days), bob);
        vm.warp(block.timestamp + 2 days);

        vm.prank(bob);
        locker.withdraw(id);

        vm.prank(bob);
        vm.expectRevert(HikariLocker.AlreadyWithdrawn.selector);
        locker.extend(id, _futureUnlock(30 days));
    }

    // -------------------------------------------------------------------------
    // WITHDRAW
    // -------------------------------------------------------------------------

    function test_withdraw_succeedsAfterUnlock() public {
        vm.prank(alice);
        uint256 id = locker.lock(address(token), 100 ether, _futureUnlock(1 days), bob);

        vm.warp(block.timestamp + 2 days);
        vm.prank(bob);
        locker.withdraw(id);

        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.balanceOf(address(locker)), 0);

        (,,,, bool withdrawn) = locker.locks(id);
        assertTrue(withdrawn);
    }

    function test_withdraw_revertsBeforeUnlock() public {
        vm.prank(alice);
        uint256 id = locker.lock(address(token), 1 ether, _futureUnlock(7 days), bob);

        vm.prank(bob);
        vm.expectRevert(HikariLocker.StillLocked.selector);
        locker.withdraw(id);
    }

    function test_withdraw_revertsForNonOwner() public {
        vm.prank(alice);
        uint256 id = locker.lock(address(token), 1 ether, _futureUnlock(1 days), bob);
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        vm.expectRevert(HikariLocker.NotOwner.selector);
        locker.withdraw(id);
    }

    function test_withdraw_revertsTwice() public {
        vm.prank(alice);
        uint256 id = locker.lock(address(token), 1 ether, _futureUnlock(1 days), bob);
        vm.warp(block.timestamp + 2 days);

        vm.prank(bob);
        locker.withdraw(id);

        vm.prank(bob);
        vm.expectRevert(HikariLocker.AlreadyWithdrawn.selector);
        locker.withdraw(id);
    }

    // -------------------------------------------------------------------------
    // FEE-ON-TRANSFER COMPATIBILITY
    // -------------------------------------------------------------------------

    function test_lock_handlesFeeOnTransferToken() public {
        FeeToken fot = new FeeToken();
        fot.mint(alice, 1_000 ether);
        vm.prank(alice);
        fot.approve(address(locker), type(uint256).max);

        // 5% fee on transfer.
        vm.prank(alice);
        uint256 id = locker.lock(address(fot), 100 ether, _futureUnlock(1 days), bob);

        (,, uint128 amount,,) = locker.locks(id);
        assertEq(amount, 95 ether, "amount must reflect actually-received tokens");

        vm.warp(block.timestamp + 2 days);
        vm.prank(bob);
        locker.withdraw(id);
        // Withdraw transfer also takes 5% fee, so bob gets 95% of 95 ether.
        assertEq(fot.balanceOf(bob), (95 ether * 95) / 100);
    }
}

/// @dev Test-only ERC20 that takes a 5% fee on every transfer (incl. transferFrom).
contract FeeToken {
    string public constant name = "FeeTok";
    string public constant symbol = "FOT";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        return _doTransfer(msg.sender, to, value);
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }
        return _doTransfer(from, to, value);
    }

    function _doTransfer(address from, address to, uint256 value) internal returns (bool) {
        balanceOf[from] -= value;
        uint256 fee = (value * 5) / 100;
        uint256 net = value - fee;
        balanceOf[to] += net;
        // Burn the fee.
        totalSupply -= fee;
        emit Transfer(from, to, net);
        return true;
    }
}
