// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// 模块类型常量（ERC-7579 子集）/ Module type ids (subset of ERC-7579).
uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant MODULE_TYPE_EXECUTOR = 2;
uint256 constant MODULE_TYPE_HOOK = 4;

/// @notice 所有模块的公共生命周期接口 / Common lifecycle interface for every module.
interface IModule {
    /// @notice 安装时由账户调用（msg.sender == 账户）/ Called by the account on install (msg.sender == account).
    function onInstall(bytes calldata data) external;
    /// @notice 卸载时由账户调用 / Called by the account on uninstall.
    function onUninstall(bytes calldata data) external;
    /// @notice 是否为某模块类型 / Whether this module is of a given type id.
    function isModuleType(uint256 typeId) external view returns (bool);
}

/// @notice 验证器模块（type 1）：仅鉴权，不能动用资金 / Validator (type 1): authorizes callers, cannot move funds.
interface IValidator is IModule {
    /// @notice 校验一次执行授权 / Validate authorization for one execution.
    /// @param execHash 账户算好的 EIP-712 摘要（绑定 chainId+account+nonce+callsHash）。
    ///                 EIP-712 digest computed by the account (binds chainId+account+nonce+callsHash).
    /// @param executionData 原始 executionData，供 session 类逐笔校验策略 / raw executionData for per-call policy checks.
    /// @param sig 该验证器对应的内层签名 / inner signature for this validator.
    function validateExecution(bytes32 execHash, bytes calldata executionData, bytes calldata sig)
        external
        view
        returns (bool);

    /// @notice ERC-1271 风格的消息验签 / ERC-1271-style message signature check.
    function validateSignature(bytes32 hash, bytes calldata sig) external view returns (bool);
}

/// @notice 执行器模块（type 2，高危）：通过 account.executeFromExecutor 回调代账户执行。
///         Executor (type 2, high-risk): acts on the account via account.executeFromExecutor.
interface IExecutor is IModule {}

/// @notice 钩子模块（type 4）：在执行前后包裹检查 / Hook (type 4): pre/post execution checks.
interface IHook is IModule {
    function preCheck(address sender, uint256 value, bytes calldata data) external returns (bytes memory hookData);
    function postCheck(bytes calldata hookData) external;
}
