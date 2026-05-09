// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Test} from "forge-std/Test.sol";
import {TaxToken} from "../../../src/templates/TaxToken.sol";

contract TaxTokenTest is Test {
    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");
    address internal pair = makeAddr("pair");
    address internal taxRecipient = makeAddr("taxRecipient");

    TaxToken internal token;

    uint256 internal constant BUY_TAX = 500; // 5%
    uint256 internal constant SELL_TAX = 700; // 7%

    function setUp() public {
        token = new TaxToken(
            "TaxTok",
            "TAX",
            18,
            1_000_000 ether,
            uint16(BUY_TAX),
            uint16(SELL_TAX),
            taxRecipient,
            owner, // mintTo
            owner // owner
        );
        vm.prank(owner);
        token.setAmmPair(pair, true);
    }

    function test_constructor_storesParams_andDefaultExclusions() public view {
        assertEq(token.buyTaxBps(), BUY_TAX);
        assertEq(token.sellTaxBps(), SELL_TAX);
        assertEq(token.taxRecipient(), taxRecipient);
        assertTrue(token.isExcludedFromTax(owner));
        assertTrue(token.isExcludedFromTax(taxRecipient));
        assertTrue(token.isExcludedFromTax(address(token)));
    }

    function test_constructor_revertsAboveCap() public {
        vm.expectRevert();
        new TaxToken("T", "T", 18, 1, 1001, 0, taxRecipient, owner, owner);
        vm.expectRevert();
        new TaxToken("T", "T", 18, 1, 0, 1001, taxRecipient, owner, owner);
    }

    function test_setBuyTax_onlyOwner_underCap() public {
        vm.prank(user);
        vm.expectRevert();
        token.setBuyTaxBps(0);

        vm.prank(owner);
        token.setBuyTaxBps(0);
        assertEq(token.buyTaxBps(), 0);

        vm.prank(owner);
        vm.expectRevert();
        token.setBuyTaxBps(1001);
    }

    function test_buyTax_appliedOnTransferFromPair() public {
        // Seed pair with tokens (move from owner who is excluded).
        vm.prank(owner);
        token.transfer(pair, 1000 ether);

        uint256 before = token.balanceOf(taxRecipient);
        vm.prank(pair);
        token.transfer(user, 100 ether);

        uint256 expectedTax = (100 ether * BUY_TAX) / 10_000;
        assertEq(token.balanceOf(user), 100 ether - expectedTax);
        assertEq(token.balanceOf(taxRecipient), before + expectedTax);
    }

    function test_sellTax_appliedOnTransferToPair() public {
        // Move tokens to user (no tax — owner excluded).
        vm.prank(owner);
        token.transfer(user, 1000 ether);

        uint256 before = token.balanceOf(taxRecipient);
        vm.prank(user);
        token.transfer(pair, 100 ether);

        uint256 expectedTax = (100 ether * SELL_TAX) / 10_000;
        assertEq(token.balanceOf(pair), 100 ether - expectedTax);
        assertEq(token.balanceOf(taxRecipient), before + expectedTax);
    }

    function test_normalTransfer_betweenWallets_isUntaxed() public {
        vm.prank(owner);
        token.transfer(user, 100 ether);

        address randomGuy = makeAddr("randomGuy");
        uint256 beforeRecipient = token.balanceOf(taxRecipient);
        vm.prank(user);
        token.transfer(randomGuy, 50 ether);
        assertEq(token.balanceOf(randomGuy), 50 ether);
        assertEq(token.balanceOf(taxRecipient), beforeRecipient, "no tax on wallet-to-wallet");
    }

    function test_excludedAccount_bypassesTax() public {
        vm.prank(owner);
        token.setExcludedFromTax(user, true);
        vm.prank(owner);
        token.transfer(user, 1000 ether);

        uint256 before = token.balanceOf(taxRecipient);
        vm.prank(user);
        token.transfer(pair, 100 ether);
        assertEq(token.balanceOf(taxRecipient), before, "excluded -> no tax");
    }
}
