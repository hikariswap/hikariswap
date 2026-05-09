// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.20;

import {IHikariFactory} from "../interfaces/IHikariFactory.sol";
import {IHikariPair} from "../interfaces/IHikariPair.sol";

/// @title HikariLibrary
/// @notice Pure helpers for working with HikariSwap pairs. The fee math reflects
///         HikariSwap's 0.35% total swap fee (35 basis points out of 10000).
library HikariLibrary {
    /// @notice Sort two token addresses canonically.
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "HL: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "HL: ZERO_ADDRESS");
    }

    /// @notice Returns the deterministic CREATE2 address of a pair without an
    ///         external call, given the factory's init-code hash. Useful in
    ///         tests, off-chain tooling, and gas-sensitive Router paths where
    ///         the caller has cached the factory hash.
    function pairForCreate2(address factory, bytes32 initCodePairHash, address tokenA, address tokenB)
        internal
        pure
        returns (address pair)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", factory, keccak256(abi.encodePacked(token0, token1)), initCodePairHash
                        )
                    )
                )
            )
        );
    }

    /// @notice Returns the canonical on-chain address of a pair via the factory's
    ///         registry. Always reflects reality, but does an external call.
    function pairFor(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = IHikariFactory(factory).getPair(token0, token1);
        require(pair != address(0), "HL: PAIR_NOT_FOUND");
    }

    /// @notice Fetches and sorts the reserves for a pair.
    function getReserves(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint112 reserve0, uint112 reserve1,) = IHikariPair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) =
            tokenA == token0 ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));
    }

    /// @notice Given an asset amount and pair reserves, returns the equivalent
    ///         amount of the other asset assuming proportional pricing (no fee).
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, "HL: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "HL: INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }

    /// @notice Given an input amount and pair reserves, returns the maximum
    ///         output amount of the other asset, after the 0.35% fee.
    /// @dev    Derivation: an input of `amountIn` arrives but is multiplied by
    ///         (1 - 0.0035) = 0.9965 = 9965/10000 before being applied to the
    ///         constant-product formula:
    ///           amountOut = (amountIn * 9965 * reserveOut) /
    ///                       (reserveIn * 10000 + amountIn * 9965)
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "HL: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "HL: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 9965;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 10_000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Given a desired output amount, returns the required input amount
    ///         (rounded up by 1 wei) given the 0.35% fee.
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "HL: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "HL: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 10_000;
        uint256 denominator = (reserveOut - amountOut) * 9965;
        amountIn = (numerator / denominator) + 1;
    }

    /// @notice Performs a chained getAmountOut along an exact-in path.
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "HL: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; ++i) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /// @notice Performs a chained getAmountIn along an exact-out path.
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "HL: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; --i) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
