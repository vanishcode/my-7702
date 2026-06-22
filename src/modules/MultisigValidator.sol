// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IModule, IValidator, MODULE_TYPE_VALIDATOR} from "../interfaces/IERC7579Modules.sol";
import {ECDSA} from "../lib/ECDSA.sol";

/// @title  MultisigValidator —— M-of-N 多签验证器插件 / M-of-N multisig validator module (type 1).
/// @notice 为账户登记一组授权签名者(N) 与阈值(M)：一笔执行(或一条 ERC-1271 消息)需要至少 M 个不同的
///         登记签名者对同一摘要(execHash / wrapped hash)各签一份 secp256k1 签名，方可放行。
///         Registers N authorized signers + a threshold M: an execution (or an ERC-1271 message) is
///         authorized only when at least M distinct registered signers each sign the same digest.
/// @dev    安全要点 / security notes:
///         1) 每个签名都对账户算好的 `execHash`（已绑定 chainId+account+nonce+callsHash）签名，
///            天然防重放与跨链/跨账户重用；secp256k1 由 ECDSA 库强制 low-s（拒绝可塑签名）。
///            Each signature is over the account-computed digest (binds chainId+account+nonce+callsHash);
///            ECDSA enforces low-s, so a signature can't be reshaped to forge a second one.
///         2) 多个签名必须按"恢复出的签名者地址严格升序"排列——以 O(N) 完成去重，杜绝同一签名者重复计数。
///            Signatures must be ordered by strictly-ascending recovered signer address: cheap de-dup.
///         3) 本模块只做"鉴权"，不放宽核心不变式：非 ROOT 路径仍被 Account 强制 `to != address(this)` 且
///            不得触达任何已安装模块。因此多签可以授权对外调用/转账，但**无法触达 admin**（装卸模块、改配置）——
///            账户的 EOA ROOT 私钥仍是最终管理员/后备。This authorizes external calls/transfers but can never
///            reach admin (the core blocks it on non-ROOT paths); the EOA ROOT key remains the ultimate admin.
contract MultisigValidator is IValidator {
    /// @param signers 授权签名者，存储时保证严格升序、去重、非零 / authorized signers, stored strictly ascending & nonzero.
    /// @param threshold 放行所需的最小签名数 M（1 ≤ M ≤ N）/ minimum signatures M required (1 ≤ M ≤ N).
    struct Config {
        address[] signers;
        uint256 threshold;
        bool exists;
    }

    mapping(address account => Config) internal _configs;

    event MultisigConfigured(address indexed account, uint256 signerCount, uint256 threshold);
    event MultisigCleared(address indexed account);

    /// @dev 阈值越界（0 或 > 签名者数量）/ threshold is zero or exceeds the signer count.
    error InvalidThreshold();
    /// @dev 签名者未严格升序或含零地址（升序同时保证去重与非零）/ signers not strictly ascending, or a zero address.
    error UnsortedOrZeroSigner();

    /// @inheritdoc IModule
    function isModuleType(uint256 typeId) external pure returns (bool) {
        return typeId == MODULE_TYPE_VALIDATOR;
    }

    /// @notice 安装时配置多签；`data` 为空则仅安装、稍后由 setConfig 配置（与 SessionKeyValidator 一致）。
    ///         On install, configure the multisig; empty `data` installs unconfigured (configure later via setConfig).
    /// @param data abi.encode(address[] signers, uint256 threshold)
    function onInstall(bytes calldata data) external {
        if (data.length == 0) return; // 空配置：仅登记模块，待 setConfig / install only, configure later
        (address[] memory signers, uint256 threshold) = abi.decode(data, (address[], uint256));
        _setConfig(msg.sender, signers, threshold);
    }

    /// @notice 卸载时清空本账户配置 / wipe this account's config on uninstall.
    function onUninstall(bytes calldata) external {
        delete _configs[msg.sender];
        emit MultisigCleared(msg.sender);
    }

    /// @notice 设置/更新多签配置（仅账户自身：以 msg.sender 为账户 key，无需卸载重装）。
    ///         Set/update the config (account-only: keyed by msg.sender; no uninstall/reinstall needed).
    function setConfig(address[] calldata signers, uint256 threshold) external {
        _setConfig(msg.sender, signers, threshold);
    }

    function getConfig(address account)
        external
        view
        returns (address[] memory signers, uint256 threshold, bool exists)
    {
        Config storage c = _configs[account];
        return (c.signers, c.threshold, c.exists);
    }

    /// @inheritdoc IValidator
    /// @dev `executionData` 未使用：多签授权整批执行（已由 execHash 绑定），不做逐笔策略；自调用由核心拦截。
    ///      `executionData` is unused: the multisig authorizes the whole batch (bound in execHash); the core
    ///      still blocks self/module targets on this non-ROOT path.
    function validateExecution(bytes32 execHash, bytes calldata, bytes calldata sig) external view returns (bool) {
        return _check(msg.sender, execHash, sig);
    }

    /// @inheritdoc IValidator
    /// @notice ERC-1271：让账户产出 M-of-N 的合约签名（账户经 validateViaModule 调入，msg.sender==account）。
    ///         ERC-1271: lets the account produce M-of-N contract signatures.
    function validateSignature(bytes32 hash, bytes calldata sig) external view returns (bool) {
        return _check(msg.sender, hash, sig);
    }

    // ───────────────────────── 内部 / internal ─────────────────────────

    /// @dev 校验 `sig` 是否包含至少 threshold 个"不同的登记签名者"对 `digest` 的有效签名。
    ///      `sig = abi.encode(bytes[] signatures)`，每个元素是 65 字节 r‖s‖v 签名，必须按签名者地址严格升序。
    ///      返回 false 而非 revert（畸形的内层签名同样安全失败）；仅当外层 ABI 编码本身损坏时才会 revert。
    ///      Returns true iff `sig` carries >= threshold valid signatures from distinct registered signers,
    ///      ordered by strictly-ascending recovered address. Returns false (not revert) on any inner mismatch.
    function _check(address account, bytes32 digest, bytes calldata sig) internal view returns (bool) {
        Config storage c = _configs[account];
        if (!c.exists) return false;

        bytes[] memory sigs = abi.decode(sig, (bytes[]));
        uint256 threshold = c.threshold;
        if (sigs.length < threshold) return false;

        address last; // address(0)：要求首个签名者 > 0 / forces the first signer to be nonzero
        uint256 count;
        for (uint256 i; i < sigs.length; i++) {
            address signer = ECDSA.recover(digest, sigs[i]); // low-s 强制；非法签名返回 0 / invalid -> 0
            if (signer <= last) return false; // 严格升序 → 去重；并隐式拒绝 signer==0 / strict ascending ⇒ unique
            if (!_isSigner(c, signer)) return false; // 必须是登记的签名者 / must be a registered signer
            last = signer;
            unchecked {
                count++;
            }
        }
        return count >= threshold;
    }

    function _isSigner(Config storage c, address a) internal view returns (bool) {
        address[] storage signers = c.signers;
        uint256 n = signers.length;
        for (uint256 i; i < n; i++) {
            if (signers[i] == a) return true;
        }
        return false;
    }

    function _setConfig(address account, address[] memory signers, uint256 threshold) internal {
        uint256 n = signers.length;
        if (threshold == 0 || threshold > n) revert InvalidThreshold();

        address last; // 0：要求 signers[0] > 0 且整体严格升序（保证去重+非零）/ ascending from 0 ⇒ unique & nonzero
        for (uint256 i; i < n; i++) {
            if (signers[i] <= last) revert UnsortedOrZeroSigner();
            last = signers[i];
        }

        Config storage c = _configs[account];
        c.signers = signers;
        c.threshold = threshold;
        c.exists = true;
        emit MultisigConfigured(account, n, threshold);
    }
}
