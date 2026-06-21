// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Call} from "../lib/Types.sol";
import {IExecutor, MODULE_TYPE_EXECUTOR} from "../interfaces/IERC7579Modules.sol";

interface IExecAccount {
    function executeFromExecutor(bytes32 mode, bytes calldata executionData) external returns (bytes[] memory);
}

/// @title  ExampleExecutor —— 示例执行器插件 / example executor module (type 2).
/// @notice 演示 type-2 路径：一个被授权的 operator 触发账户代为执行一批调用。
///         Demonstrates the type-2 path: an authorized operator triggers the account to run a batch.
/// @dev    安全要点：executor 是头号盗资金面，**必须自带访问控制**（这里是 per-account operator）。
///         即便如此，account.executeFromExecutor 仍强制禁止 self-call，executor 无法触达 admin。
///         Security: executors are the #1 drain vector and MUST carry their own access control. Even so,
///         the account's executeFromExecutor forbids self-calls, so an executor can never reach admin.
contract ExampleExecutor is IExecutor {
    /// @dev 复用核心的 MODE_BATCH 常量 / mirrors the core MODE_BATCH constant.
    bytes32 internal constant MODE_BATCH = 0x0100000000000000000000000000000000000000000000000000000000000000;

    mapping(address account => address operator) public operatorOf;

    error NotOperator();

    function isModuleType(uint256 typeId) external pure returns (bool) {
        return typeId == MODULE_TYPE_EXECUTOR;
    }

    /// @notice 安装：initData = abi.encode(address operator) / install: initData = abi.encode(address operator).
    function onInstall(bytes calldata data) external {
        operatorOf[msg.sender] = abi.decode(data, (address));
    }

    function onUninstall(bytes calldata) external {
        delete operatorOf[msg.sender];
    }

    /// @notice 被授权的 operator 触发账户执行 / authorized operator triggers account execution.
    function executeViaAccount(address account, Call[] calldata calls) external returns (bytes[] memory) {
        if (msg.sender != operatorOf[account]) revert NotOperator();
        return IExecAccount(account).executeFromExecutor(MODE_BATCH, abi.encode(calls));
    }
}
