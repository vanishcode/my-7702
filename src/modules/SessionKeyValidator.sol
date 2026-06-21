// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Call} from "../lib/Types.sol";
import {IModule, IValidator, MODULE_TYPE_VALIDATOR} from "../interfaces/IERC7579Modules.sol";
import {ECDSA} from "../lib/ECDSA.sol";

/// @title  SessionKeyValidator —— session key 验证器插件 / session-key validator module (type 1).
/// @notice 为账户登记带作用域的临时密钥：时间窗 + 目标白名单 + 选择器白名单 + 单笔 ETH 上限。
///         Registers scoped temporary keys: time window + target allowlist + selector allowlist + per-call ETH cap.
/// @dev    关键安全：session 永远无法触达账户自身（admin），由本模块与核心双重拦截。
///         Security: a session can never reach the account itself (admin); enforced here AND in the core.
contract SessionKeyValidator is IValidator {
    struct Policy {
        uint48 validAfter; // 0 = 立即生效 / 0 = active immediately
        uint48 validUntil; // 0 = 永不过期 / 0 = never expires
        uint256 perCallEthCap; // 每笔 value 上限 / per-call ETH value cap
        address[] targets; // 允许的目标（空 = 拒绝一切）/ allowed targets (empty = deny all)
        bytes4[] selectors; // 允许的选择器（空 = 该目标任意选择器）/ allowed selectors (empty = any on target)
        bool exists;
    }

    mapping(address account => mapping(address sessionKey => Policy)) internal _sessions;

    event SessionInstalled(address indexed account, address indexed sessionKey);
    event SessionRevoked(address indexed account, address indexed sessionKey);

    error ZeroSessionKey();

    /// @inheritdoc IModule
    function isModuleType(uint256 typeId) external pure returns (bool) {
        return typeId == MODULE_TYPE_VALIDATOR;
    }

    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    /// @notice 登记一个 session（仅账户自身可调 / account-only）.
    function installSession(address sessionKey, Policy calldata p) external {
        if (sessionKey == address(0)) revert ZeroSessionKey();
        Policy storage sp = _sessions[msg.sender][sessionKey];
        sp.validAfter = p.validAfter;
        sp.validUntil = p.validUntil;
        sp.perCallEthCap = p.perCallEthCap;
        sp.targets = p.targets;
        sp.selectors = p.selectors;
        sp.exists = true;
        emit SessionInstalled(msg.sender, sessionKey);
    }

    /// @notice 撤销 session（即时；在途签名因 exists==false 失效）/ revoke a session (immediate).
    function revokeSession(address sessionKey) external {
        delete _sessions[msg.sender][sessionKey];
        emit SessionRevoked(msg.sender, sessionKey);
    }

    function getSession(address account, address sessionKey) external view returns (Policy memory) {
        return _sessions[account][sessionKey];
    }

    /// @inheritdoc IValidator
    /// @dev session key 不用于 ERC-1271 消息验签 / session keys are not used for ERC-1271 message signing.
    function validateSignature(bytes32, bytes calldata) external pure returns (bool) {
        return false;
    }

    /// @inheritdoc IValidator
    function validateExecution(bytes32 execHash, bytes calldata executionData, bytes calldata sig)
        external
        view
        returns (bool)
    {
        address account = msg.sender; // 账户经 CALL 调入 / the account calls in
        address sessionKey = ECDSA.recover(execHash, sig);
        if (sessionKey == address(0)) return false;

        Policy storage p = _sessions[account][sessionKey];
        if (!p.exists) return false;
        if (p.validAfter != 0 && block.timestamp < p.validAfter) return false;
        if (p.validUntil != 0 && block.timestamp > p.validUntil) return false;

        (Call[] memory calls,) = abi.decode(executionData, (Call[], bytes));
        uint256 n = calls.length;
        for (uint256 i; i < n; i++) {
            address to = calls[i].target == address(0) ? account : calls[i].target;
            if (to == account) return false; // 禁止触达 admin / never reach the account itself
            if (calls[i].value > p.perCallEthCap) return false;
            if (!_targetAllowed(p, to)) return false;
            if (!_selectorAllowed(p, _selector(calls[i].data))) return false;
        }
        return true;
    }

    function _targetAllowed(Policy storage p, address to) internal view returns (bool) {
        uint256 n = p.targets.length;
        for (uint256 i; i < n; i++) {
            if (p.targets[i] == to) return true;
        }
        return false;
    }

    function _selectorAllowed(Policy storage p, bytes4 sel) internal view returns (bool) {
        uint256 n = p.selectors.length;
        if (n == 0) return true; // 通配 / wildcard
        for (uint256 i; i < n; i++) {
            if (p.selectors[i] == sel) return true;
        }
        return false;
    }

    function _selector(bytes memory data) internal pure returns (bytes4 s) {
        if (data.length < 4) return bytes4(0);
        assembly {
            s := mload(add(data, 0x20))
        }
    }
}
