// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Base} from "../Base.t.sol";
import {HikariFeeCollector} from "../../src/factory/HikariFeeCollector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract HikariFeeCollectorTest is Base {
    event LCAIReceived(address indexed from, uint256 amount);
    event LCAIWithdrawn(address indexed to, uint256 amount);

    function setUp() public {
        deployHikari();
    }

    function test_constructor_revertsOnZeroOwner() public {
        // OZ Ownable's own constructor reverts first with OwnableInvalidOwner;
        // the FeeCollector's redundant ZeroAddress check is therefore dead code.
        // We still assert that construction with address(0) is impossible.
        vm.expectRevert();
        new HikariFeeCollector(address(0));
    }

    function test_receivesNativeAndEmits() public {
        deal(address(this), 1 ether);
        vm.expectEmit(true, false, false, true, address(feeCollector));
        emit LCAIReceived(address(this), 1 ether);
        (bool ok,) = address(feeCollector).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(feeCollector).balance, 1 ether);
    }

    function test_withdrawLCAI_onlyOwner() public {
        deal(address(feeCollector), 1 ether);

        vm.prank(user);
        vm.expectRevert();
        feeCollector.withdrawLCAI(payable(user), 1 ether);

        uint256 ownerBalBefore = owner.balance;
        vm.prank(owner);
        feeCollector.withdrawLCAI(payable(owner), 1 ether);
        assertEq(owner.balance, ownerBalBefore + 1 ether);
    }

    function test_withdrawLCAI_revertsOnZeroToOrAmount() public {
        deal(address(feeCollector), 1 ether);
        vm.prank(owner);
        vm.expectRevert(HikariFeeCollector.ZeroAddress.selector);
        feeCollector.withdrawLCAI(payable(address(0)), 1 ether);

        vm.prank(owner);
        vm.expectRevert(HikariFeeCollector.ZeroAmount.selector);
        feeCollector.withdrawLCAI(payable(owner), 0);
    }

    function test_withdrawERC20_movesTokensToTo() public {
        MockERC20 t = new MockERC20("T", "T", 18);
        t.mint(address(feeCollector), 100 ether);

        vm.prank(user);
        vm.expectRevert();
        feeCollector.withdrawERC20(IERC20(address(t)), user, 100 ether);

        vm.prank(owner);
        feeCollector.withdrawERC20(IERC20(address(t)), owner, 100 ether);
        assertEq(t.balanceOf(owner), 100 ether);
        assertEq(t.balanceOf(address(feeCollector)), 0);
    }
}
