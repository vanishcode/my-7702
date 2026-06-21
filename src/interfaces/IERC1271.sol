// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice ERC-1271 标准合约签名校验接口 / ERC-1271 contract signature validation.
interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);
}
