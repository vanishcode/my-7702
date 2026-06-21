// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IModule, IValidator, MODULE_TYPE_VALIDATOR} from "../interfaces/IERC7579Modules.sol";
import {WebAuthn} from "../lib/WebAuthn.sol";

/// @title  WebAuthnValidator —— passkey(P256/WebAuthn) 验证器插件 / passkey validator module (type 1).
/// @notice 每个账户注册一个 passkey 公钥；用真实设备/浏览器 passkey 的 WebAuthn 断言鉴权。
///         Registers one passkey public key per account; authorizes via real WebAuthn assertions.
/// @dev    模块为单例，状态以账户地址为 key；账户经 CALL 调用本模块时 msg.sender == 账户（天然 root 门禁）。
///         Singleton module keyed by account; when the account CALLs in, msg.sender == account (root-gated).
contract WebAuthnValidator is IValidator {
    struct PassKey {
        bytes32 x;
        bytes32 y;
        bool requireUV; // 是否要求 User-Verified / require the User-Verified flag
        bool set;
    }

    mapping(address account => PassKey) public passKeys;

    event PassKeySet(address indexed account, bytes32 x, bytes32 y, bool requireUV);
    event PassKeyRemoved(address indexed account);

    /// @inheritdoc IModule
    function isModuleType(uint256 typeId) external pure returns (bool) {
        return typeId == MODULE_TYPE_VALIDATOR;
    }

    /// @notice 安装：initData = abi.encode(x, y, requireUV)（可为空，稍后用 setPassKey 设置）。
    ///         Install: initData = abi.encode(x, y, requireUV) (may be empty; set later via setPassKey).
    function onInstall(bytes calldata data) external {
        if (data.length != 0) {
            (bytes32 x, bytes32 y, bool requireUV) = abi.decode(data, (bytes32, bytes32, bool));
            _set(msg.sender, x, y, requireUV);
        }
    }

    function onUninstall(bytes calldata) external {
        delete passKeys[msg.sender];
        emit PassKeyRemoved(msg.sender);
    }

    /// @notice 设置/轮换 passkey（仅账户自身可调）/ set or rotate the passkey (account-only).
    function setPassKey(bytes32 x, bytes32 y, bool requireUV) external {
        _set(msg.sender, x, y, requireUV);
    }

    /// @inheritdoc IValidator
    function validateExecution(bytes32 execHash, bytes calldata, bytes calldata sig) external view returns (bool) {
        return _verify(msg.sender, execHash, sig);
    }

    /// @inheritdoc IValidator
    function validateSignature(bytes32 hash, bytes calldata sig) external view returns (bool) {
        return _verify(msg.sender, hash, sig);
    }

    function _set(address account, bytes32 x, bytes32 y, bool requireUV) internal {
        passKeys[account] = PassKey(x, y, requireUV, true);
        emit PassKeySet(account, x, y, requireUV);
    }

    function _verify(address account, bytes32 challenge, bytes calldata sig) internal view returns (bool) {
        PassKey memory k = passKeys[account];
        if (!k.set) return false;
        return WebAuthn.verify(challenge, k.requireUV, sig, k.x, k.y);
    }
}
