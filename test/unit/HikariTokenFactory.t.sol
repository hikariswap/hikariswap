// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Base} from "../Base.t.sol";
import {HikariTokenFactory} from "../../src/factory/HikariTokenFactory.sol";
import {HikariTokenDeployer} from "../../src/factory/HikariTokenDeployer.sol";
import {StandardToken} from "../../src/templates/StandardToken.sol";
import {MintableToken} from "../../src/templates/MintableToken.sol";
import {BurnableToken} from "../../src/templates/BurnableToken.sol";
import {TaxToken} from "../../src/templates/TaxToken.sol";

contract HikariTokenFactoryTest is Base {
    function setUp() public {
        deployHikari();
        deal(user, 1_000_000 ether);
    }

    // -------------------------------------------------------------------------
    // CONSTRUCTOR / WIRING
    // -------------------------------------------------------------------------

    function test_constructor_storesPricesAndFeeCollector() public view {
        assertEq(tokenFactory.price(HikariTokenFactory.TokenType.Standard), PRICE_STANDARD);
        assertEq(tokenFactory.price(HikariTokenFactory.TokenType.Mintable), PRICE_MINTABLE);
        assertEq(tokenFactory.price(HikariTokenFactory.TokenType.Burnable), PRICE_BURNABLE);
        assertEq(tokenFactory.price(HikariTokenFactory.TokenType.Tax), PRICE_TAX);
        assertEq(tokenFactory.feeCollector(), payable(address(feeCollector)));
        assertEq(address(tokenFactory.deployer()), address(tokenDeployer));
    }

    function test_constructor_revertsOnPriceOutOfBounds() public {
        HikariTokenDeployer d = new HikariTokenDeployer();
        vm.expectRevert(abi.encodeWithSelector(HikariTokenFactory.InvalidPrice.selector, uint256(999 ether)));
        new HikariTokenFactory(
            owner, payable(address(feeCollector)), address(d), 999 ether, PRICE_MINTABLE, PRICE_BURNABLE, PRICE_TAX
        );
    }

    function test_deployer_initFactory_isOneShot() public {
        HikariTokenDeployer d = new HikariTokenDeployer();
        d.initFactory(address(0xdead));
        vm.expectRevert(HikariTokenDeployer.AlreadyBound.selector);
        d.initFactory(address(0xbeef));
    }

    function test_deployer_rejectsCallsFromNonFactory() public {
        vm.expectRevert(HikariTokenDeployer.OnlyFactory.selector);
        tokenDeployer.deployStandard(bytes32(0), "X", "X", 18, 1, address(this));
    }

    // -------------------------------------------------------------------------
    // CREATE — STANDARD
    // -------------------------------------------------------------------------

    function test_createStandard_succeeds_andForwardsFee() public {
        uint256 collectorBalBefore = address(feeCollector).balance;
        vm.prank(user);
        address token = tokenFactory.createStandard{value: PRICE_STANDARD}("Std", "STD", 18, 1_000_000 ether);

        StandardToken std = StandardToken(token);
        assertEq(std.name(), "Std");
        assertEq(std.symbol(), "STD");
        assertEq(std.decimals(), 18);
        assertEq(std.totalSupply(), 1_000_000 ether);
        assertEq(std.balanceOf(user), 1_000_000 ether);

        assertTrue(tokenFactory.isCreatedHere(token));
        assertEq(tokenFactory.allTokensLength(), 1);
        assertEq(tokenFactory.allTokens(0), token);
        assertEq(address(feeCollector).balance, collectorBalBefore + PRICE_STANDARD);
    }

    function test_createStandard_revertsOnWrongPayment() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                HikariTokenFactory.InvalidPayment.selector, uint256(PRICE_STANDARD - 1), PRICE_STANDARD
            )
        );
        tokenFactory.createStandard{value: PRICE_STANDARD - 1}("Std", "STD", 18, 1_000_000 ether);
    }

    function test_createStandard_revertsOnZeroSupply() public {
        vm.prank(user);
        vm.expectRevert(HikariTokenFactory.ZeroSupply.selector);
        tokenFactory.createStandard{value: PRICE_STANDARD}("Std", "STD", 18, 0);
    }

    function test_createStandard_revertsOnTooManyDecimals() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(HikariTokenFactory.InvalidDecimals.selector, uint8(19)));
        tokenFactory.createStandard{value: PRICE_STANDARD}("Std", "STD", 19, 1 ether);
    }

    // -------------------------------------------------------------------------
    // CREATE — MINTABLE
    // -------------------------------------------------------------------------

    function test_createMintable_succeeds_creatorIsOwner_canMint() public {
        vm.prank(user);
        address token = tokenFactory.createMintable{value: PRICE_MINTABLE}("M", "M", 18, 1000 ether, 10_000 ether);

        MintableToken mint = MintableToken(token);
        assertEq(mint.totalSupply(), 1000 ether);
        assertEq(mint.maxSupply(), 10_000 ether);
        assertEq(mint.owner(), user);

        vm.prank(user);
        mint.mint(user, 500 ether);
        assertEq(mint.totalSupply(), 1500 ether);
    }

    function test_createMintable_revertsIfCapBelowInitial() public {
        vm.prank(user);
        vm.expectRevert(HikariTokenFactory.CapBelowInitial.selector);
        tokenFactory.createMintable{value: PRICE_MINTABLE}("M", "M", 18, 100 ether, 50 ether);
    }

    // -------------------------------------------------------------------------
    // CREATE — BURNABLE
    // -------------------------------------------------------------------------

    function test_createBurnable_holderCanBurn() public {
        vm.prank(user);
        address token = tokenFactory.createBurnable{value: PRICE_BURNABLE}("B", "B", 18, 1000 ether);

        BurnableToken b = BurnableToken(token);
        vm.prank(user);
        b.burn(100 ether);
        assertEq(b.totalSupply(), 900 ether);
    }

    // -------------------------------------------------------------------------
    // CREATE — TAX
    // -------------------------------------------------------------------------

    function test_createTax_taxParamsApply() public {
        vm.prank(user);
        address token = tokenFactory.createTax{value: PRICE_TAX}("T", "T", 18, 1_000_000 ether, 500, 500, taxRecipient);
        TaxToken t = TaxToken(token);
        assertEq(t.buyTaxBps(), 500);
        assertEq(t.sellTaxBps(), 500);
        assertEq(t.taxRecipient(), taxRecipient);
        assertEq(t.owner(), user);
    }

    function test_createTax_revertsIfTaxAboveCap() public {
        vm.prank(user);
        vm.expectRevert(); // TaxToken.TaxAboveCap propagates from constructor
        tokenFactory.createTax{value: PRICE_TAX}("T", "T", 18, 1 ether, 5000, 0, taxRecipient);
    }

    function test_createTax_revertsOnZeroRecipient() public {
        vm.prank(user);
        vm.expectRevert(HikariTokenFactory.ZeroAddress.selector);
        tokenFactory.createTax{value: PRICE_TAX}("T", "T", 18, 1 ether, 100, 100, address(0));
    }

    // -------------------------------------------------------------------------
    // ADMIN
    // -------------------------------------------------------------------------

    function test_setPrice_onlyOwner_andEnforcesBounds() public {
        vm.prank(user);
        vm.expectRevert(); // OZ Ownable unauthorized custom error
        tokenFactory.setPrice(HikariTokenFactory.TokenType.Standard, 6000 ether);

        vm.prank(owner);
        tokenFactory.setPrice(HikariTokenFactory.TokenType.Standard, 6000 ether);
        assertEq(tokenFactory.price(HikariTokenFactory.TokenType.Standard), 6000 ether);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(HikariTokenFactory.InvalidPrice.selector, uint256(999 ether)));
        tokenFactory.setPrice(HikariTokenFactory.TokenType.Standard, 999 ether);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(HikariTokenFactory.InvalidPrice.selector, uint256(50_001 ether)));
        tokenFactory.setPrice(HikariTokenFactory.TokenType.Standard, 50_001 ether);
    }

    function test_setFeeCollector_onlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        tokenFactory.setFeeCollector(payable(user));

        vm.prank(owner);
        tokenFactory.setFeeCollector(payable(user));
        assertEq(tokenFactory.feeCollector(), payable(user));
    }

    function test_tokensSlice_pagination() public {
        // Create 3 tokens, slice them.
        for (uint256 i; i < 3; ++i) {
            vm.prank(user);
            tokenFactory.createStandard{value: PRICE_STANDARD}("S", "S", 18, 1 ether);
        }
        address[] memory slice = tokenFactory.tokensSlice(0, 2);
        assertEq(slice.length, 2);

        slice = tokenFactory.tokensSlice(2, 10);
        assertEq(slice.length, 1);

        slice = tokenFactory.tokensSlice(10, 10);
        assertEq(slice.length, 0);
    }
}
