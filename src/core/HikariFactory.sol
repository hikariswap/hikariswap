// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.20;

import {IHikariFactory} from "../interfaces/IHikariFactory.sol";
import {HikariPair} from "./HikariPair.sol";

/// @title HikariFactory
/// @notice Deploys HikariPair instances via CREATE2 with a salt derived from the
///         sorted (token0, token1) pair, giving each pair a deterministic address.
///         Faithful port of UniswapV2Factory (Solidity 0.5.16) to 0.8.20.
/// @dev    The init-code hash is computed at deployment and stored as immutable
///         instead of being hardcoded in a separate library; this guarantees
///         tooling-derived addresses always match the on-chain reality.
contract HikariFactory is IHikariFactory {
    address public feeTo;
    address public feeToSetter;

    /// @notice keccak256 of HikariPair's creation bytecode at the time this
    ///         factory was deployed. Used by HikariLibrary.pairForCreate2.
    bytes32 public immutable INIT_CODE_PAIR_HASH;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor(address feeToSetter_) {
        feeToSetter = feeToSetter_;
        INIT_CODE_PAIR_HASH = keccak256(type(HikariPair).creationCode);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "Hikari: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Hikari: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "Hikari: PAIR_EXISTS");

        bytes memory bytecode = type(HikariPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        require(pair != address(0), "Hikari: CREATE2_FAILED");

        HikariPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // symmetric mapping
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address feeTo_) external {
        require(msg.sender == feeToSetter, "Hikari: FORBIDDEN");
        feeTo = feeTo_;
    }

    function setFeeToSetter(address feeToSetter_) external {
        require(msg.sender == feeToSetter, "Hikari: FORBIDDEN");
        feeToSetter = feeToSetter_;
    }
}
