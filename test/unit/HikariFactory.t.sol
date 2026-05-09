// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Base} from "../Base.t.sol";
import {HikariFactory} from "../../src/core/HikariFactory.sol";
import {HikariPair} from "../../src/core/HikariPair.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract HikariFactoryTest is Base {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairCount);

    function setUp() public {
        deployHikari();
    }

    function test_constructor_storesFeeToSetter() public view {
        assertEq(factory.feeToSetter(), owner);
    }

    function test_constructor_initCodeHashMatchesPairCreationCode() public view {
        assertEq(factory.INIT_CODE_PAIR_HASH(), keccak256(type(HikariPair).creationCode));
    }

    function test_constructor_feeToInitiallyZero_thenSetByOwnerInBase() public view {
        // Base.deployHikari sets feeTo to feeCollector for protocol-fee tests.
        assertEq(factory.feeTo(), address(feeCollector));
    }

    function test_createPair_succeeds_emitsEvent_andSortsTokens() public {
        MockERC20 a = new MockERC20("A", "A", 18);
        MockERC20 b = new MockERC20("B", "B", 18);
        (address t0, address t1) = address(a) < address(b) ? (address(a), address(b)) : (address(b), address(a));

        vm.expectEmit(true, true, false, false);
        emit PairCreated(t0, t1, address(0), 1);
        address pair = factory.createPair(address(a), address(b));

        assertEq(factory.getPair(address(a), address(b)), pair);
        assertEq(factory.getPair(address(b), address(a)), pair); // symmetric
        assertEq(factory.allPairs(0), pair);
        assertEq(factory.allPairsLength(), 1);

        assertEq(HikariPair(pair).token0(), t0);
        assertEq(HikariPair(pair).token1(), t1);
        assertEq(HikariPair(pair).factory(), address(factory));
    }

    function test_createPair_revertsOnIdenticalAddresses() public {
        MockERC20 a = new MockERC20("A", "A", 18);
        vm.expectRevert(bytes("Hikari: IDENTICAL_ADDRESSES"));
        factory.createPair(address(a), address(a));
    }

    function test_createPair_revertsOnZeroAddress() public {
        MockERC20 a = new MockERC20("A", "A", 18);
        vm.expectRevert(bytes("Hikari: ZERO_ADDRESS"));
        factory.createPair(address(0), address(a));
    }

    function test_createPair_revertsOnDuplicate() public {
        MockERC20 a = new MockERC20("A", "A", 18);
        MockERC20 b = new MockERC20("B", "B", 18);
        factory.createPair(address(a), address(b));
        vm.expectRevert(bytes("Hikari: PAIR_EXISTS"));
        factory.createPair(address(a), address(b));
    }

    function test_setFeeTo_onlyFeeToSetter() public {
        vm.prank(owner);
        factory.setFeeTo(user);
        assertEq(factory.feeTo(), user);

        vm.prank(otherUser);
        vm.expectRevert(bytes("Hikari: FORBIDDEN"));
        factory.setFeeTo(user);
    }

    function test_setFeeToSetter_onlyFeeToSetter_andRotates() public {
        vm.prank(owner);
        factory.setFeeToSetter(user);
        assertEq(factory.feeToSetter(), user);

        // Old setter no longer works.
        vm.prank(owner);
        vm.expectRevert(bytes("Hikari: FORBIDDEN"));
        factory.setFeeTo(user);

        // New setter does.
        vm.prank(user);
        factory.setFeeTo(otherUser);
        assertEq(factory.feeTo(), otherUser);
    }

    function test_createPair_addressMatchesCreate2Prediction() public {
        MockERC20 a = new MockERC20("A", "A", 18);
        MockERC20 b = new MockERC20("B", "B", 18);
        (address t0, address t1) = address(a) < address(b) ? (address(a), address(b)) : (address(b), address(a));

        bytes32 salt = keccak256(abi.encodePacked(t0, t1));
        address predicted = address(
            uint160(
                uint256(keccak256(abi.encodePacked(hex"ff", address(factory), salt, factory.INIT_CODE_PAIR_HASH())))
            )
        );
        address actual = factory.createPair(address(a), address(b));
        assertEq(actual, predicted);
    }
}
