// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IHook, MODULE_TYPE_HOOK} from "../interfaces/IERC7579Modules.sol";

/// @title  SpendingLimitHook —— 示例钩子插件 / example hook module (type 4).
/// @notice 在每次执行前强制"单笔交易实际转出 ETH 总额"上限（账户传入的是 Σ calls[i].value，非 msg.value）。
///         Enforces a per-tx cap on the TRUE outgoing ETH total (the account passes Σ calls[i].value, not msg.value).
/// @dev    演示 hook 生命周期；hook 由 ROOT 安装、属可信，但恶意/有 bug 的 hook 可致 DoS。
///         Demonstrates the hook lifecycle; hooks are root-installed and trusted, but a faulty hook can DoS.
contract SpendingLimitHook is IHook {
    mapping(address account => uint256) public maxValuePerTx;

    error SpendingLimitExceeded(uint256 value, uint256 cap);

    function isModuleType(uint256 typeId) external pure returns (bool) {
        return typeId == MODULE_TYPE_HOOK;
    }

    /// @notice 安装：initData = abi.encode(uint256 cap) / install: initData = abi.encode(uint256 cap).
    function onInstall(bytes calldata data) external {
        maxValuePerTx[msg.sender] = abi.decode(data, (uint256));
    }

    function onUninstall(bytes calldata) external {
        delete maxValuePerTx[msg.sender];
    }

    /// @inheritdoc IHook
    function preCheck(address, uint256 value, bytes calldata) external view returns (bytes memory) {
        uint256 cap = maxValuePerTx[msg.sender];
        if (value > cap) revert SpendingLimitExceeded(value, cap);
        return "";
    }

    /// @inheritdoc IHook
    function postCheck(bytes calldata) external {}
}
