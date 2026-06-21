// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice 单笔调用 / A single call within a batch.
/// @dev `target == address(0)` 按 ERC-7821 归一化为 `address(this)`（仅 ROOT 路径允许 self-call）。
///      Per ERC-7821, `target == address(0)` is normalized to `address(this)` (self-call allowed only on the ROOT path).
struct Call {
    address target;
    uint256 value;
    bytes data;
}
