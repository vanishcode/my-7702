// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Call} from "./lib/Types.sol";
import {AccountStorage} from "./lib/AccountStorage.sol";
import {ECDSA} from "./lib/ECDSA.sol";
import {
    IModule,
    IValidator,
    IHook,
    MODULE_TYPE_VALIDATOR,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_HOOK
} from "./interfaces/IERC7579Modules.sol";

/// @title  my-7702 Account —— 最小化 EIP-7702 智能账户委托合约 / minimal EIP-7702 smart-account delegate.
/// @notice EOA 通过 type-4 授权把代码委托到本合约（不可升级单例，非 proxy），即可获得：
///         批量执行、可装卸的插件模块、ERC-1271、以及由 validator 插件提供的 passkey / session 鉴权。
///         An EOA delegates to this immutable singleton (no proxy) via a type-4 authorization to gain
///         batched execution, pluggable modules, ERC-1271, and passkey/session auth from validator plugins.
/// @dev    无 ERC-4337（无 EntryPoint/UserOp/paymaster/bundler）。`address(this) == 被委托的 EOA`。
///         No ERC-4337. `address(this)` equals the delegating EOA.
contract Account {
    using AccountStorage for AccountStorage.Layout;

    // ───────────────────────── ERC-7821 模式常量 / mode constants ─────────────────────────
    /// @dev 批量、失败即回滚、无 opData（自发路径）/ batch, revert-on-failure, no opData (self path).
    bytes32 public constant MODE_BATCH = 0x0100000000000000000000000000000000000000000000000000000000000000;
    /// @dev 批量、失败即回滚、带 opData（签名路径）/ batch, revert-on-failure, with opData (signed path).
    bytes32 public constant MODE_BATCH_OPDATA = 0x0100000000007821000100000000000000000000000000000000000000000000;

    bytes4 internal constant ERC1271_MAGIC = 0x1626ba7e;
    bytes4 internal constant ERC1271_FAIL = 0xffffffff;

    // EIP-712
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant NAME_HASH = keccak256("my7702");
    bytes32 internal constant VERSION_HASH = keccak256("1");
    bytes32 internal constant EXECUTE_TYPEHASH = keccak256("Execute(uint256 nonce,bytes32 callsHash)");
    /// @dev ERC-1271 消息独立的 typehash，确保消息签名空间与执行授权空间不相交（防越域重放）。
    ///      A distinct typehash for ERC-1271 messages so message signatures can never equal an execHash.
    bytes32 internal constant PERSONAL_SIGN_TYPEHASH = keccak256("PersonalSign(bytes32 hash)");

    // EIP-1153 瞬态重入锁，逐交易自动清零 / transient reentrancy lock, auto-cleared per tx.
    bool private transient _entered;

    event ModuleInstalled(uint256 indexed typeId, address indexed module);
    event ModuleUninstalled(uint256 indexed typeId, address indexed module);

    error Unauthorized();
    error UnsupportedExecutionMode();
    error UnsupportedModuleType();
    error InvalidModuleType();
    error ModuleAlreadyInstalled();
    error ModuleNotInstalled();
    error SelfCallNotAllowed();
    error ModuleTargetNotAllowed();
    error InvalidSignature();
    error Reentrancy();

    /// @dev 仅允许账户自身（ROOT：EOA 自发或经 execute 自调用）/ only the account itself (ROOT path).
    modifier onlySelf() {
        if (msg.sender != address(this)) revert Unauthorized();
        _;
    }

    modifier nonReentrant() {
        if (_entered) revert Reentrancy();
        _entered = true;
        _;
        _entered = false;
    }

    receive() external payable {}

    // ───────────────────────── 执行 / execution (ERC-7821) ─────────────────────────

    /// @notice 批量执行入口（兼容 MetaMask wallet_sendCalls / EIP-5792）/ batch execution entry point.
    /// @param mode MODE_BATCH（自发）或 MODE_BATCH_OPDATA（签名）/ MODE_BATCH (self) or MODE_BATCH_OPDATA (signed).
    /// @param executionData id1: abi.encode(Call[])；id2: abi.encode(Call[], bytes opData)，
    ///        opData = abi.encode(address validator, bytes sig)。validator==address(this) 表示 ROOT(ecrecover)。
    function execute(bytes32 mode, bytes calldata executionData) external payable nonReentrant {
        uint256 id = _modeId(mode);
        AccountStorage.Layout storage s = AccountStorage.layout();

        bool allowSelfCall;
        Call[] memory calls;

        if (id == 1) {
            // 自发批量：仅账户自身可调 / self-batch: only the account itself.
            if (msg.sender != address(this)) revert Unauthorized();
            calls = abi.decode(executionData, (Call[]));
            allowSelfCall = true;
        } else if (id == 2) {
            // 签名批量：opData 鉴权 / signed batch authorized by opData.
            bytes memory opData;
            (calls, opData) = abi.decode(executionData, (Call[], bytes));
            (address validator, bytes memory sig) = abi.decode(opData, (address, bytes));

            bytes32 execHash = _execHash(s.nonce, keccak256(abi.encode(calls)));
            unchecked {
                s.nonce++; // checks-effects-interactions：先消费 nonce 再外呼 / consume nonce before calls.
            }

            if (validator == address(this)) {
                // ROOT：EOA 的 secp256k1 私钥签名 / root: the EOA's own secp256k1 key.
                if (ECDSA.recover(execHash, sig) != address(this)) revert InvalidSignature();
                allowSelfCall = true;
            } else if (s.validators[validator]) {
                // 插件鉴权（passkey / session 等）/ plugin auth (passkey / session / ...).
                if (!IValidator(validator).validateExecution(execHash, executionData, sig)) {
                    revert InvalidSignature();
                }
                allowSelfCall = false; // 非 ROOT 路径禁止 self-call / non-root path cannot self-call.
            } else {
                revert Unauthorized();
            }
        } else {
            revert UnsupportedExecutionMode();
        }

        // hooks 在鉴权之后运行，并以"实际转出总额"为 value / hooks run post-auth, with the true outgoing total.
        (address[] memory hookList, bytes[] memory hookData) = _preHooks(msg.sender, _sumValues(calls), msg.data);
        _executeCalls(calls, allowSelfCall);
        _postHooks(hookList, hookData);
    }

    /// @notice 由已安装的 executor(type 2) 模块回调，代账户执行批量 / called back by an installed executor module.
    /// @dev executor 路径强制 allowSelfCall=false：无法触达账户自身或任何已安装模块（防越权/盗资金）。
    ///      The executor path forces allowSelfCall=false: it can reach neither the account nor any installed module.
    function executeFromExecutor(bytes32 mode, bytes calldata executionData)
        external
        nonReentrant
        returns (bytes[] memory results)
    {
        AccountStorage.Layout storage s = AccountStorage.layout();
        if (!s.executors[msg.sender]) revert Unauthorized();
        if (_modeId(mode) != 1) revert UnsupportedExecutionMode();

        Call[] memory calls = abi.decode(executionData, (Call[]));
        (address[] memory hookList, bytes[] memory hookData) = _preHooks(msg.sender, _sumValues(calls), msg.data);
        results = _executeCalls(calls, false);
        _postHooks(hookList, hookData);
    }

    function supportsExecutionMode(bytes32 mode) external pure returns (bool) {
        return _modeId(mode) != 0;
    }

    // ───────────────────────── 模块系统 / module system ─────────────────────────

    /// @notice 安装模块（validator/executor/hook）/ install a module.
    /// @dev onlySelf：只能经 ROOT 路径（EOA 自发或 execute 自调用）。无 nonReentrant：避免与 execute 的锁互斥。
    ///      onlySelf gates to the ROOT path. No nonReentrant here to avoid deadlock with execute's lock.
    function installModule(uint256 typeId, address module, bytes calldata initData) external onlySelf {
        AccountStorage.Layout storage s = AccountStorage.layout();
        if (!IModule(module).isModuleType(typeId)) revert InvalidModuleType();

        if (typeId == MODULE_TYPE_VALIDATOR) {
            if (s.validators[module]) revert ModuleAlreadyInstalled();
            s.validators[module] = true;
        } else if (typeId == MODULE_TYPE_EXECUTOR) {
            if (s.executors[module]) revert ModuleAlreadyInstalled();
            s.executors[module] = true;
        } else if (typeId == MODULE_TYPE_HOOK) {
            if (s.isHook[module]) revert ModuleAlreadyInstalled();
            s.isHook[module] = true;
            s.hooks.push(module);
        } else {
            revert UnsupportedModuleType();
        }

        IModule(module).onInstall(initData);
        emit ModuleInstalled(typeId, module);
    }

    /// @notice 卸载模块 / uninstall a module.
    /// @dev onUninstall 包 try/catch：恶意模块无法靠 revert 自锁 / a malicious module cannot brick itself.
    function uninstallModule(uint256 typeId, address module, bytes calldata deInitData) external onlySelf {
        AccountStorage.Layout storage s = AccountStorage.layout();

        if (typeId == MODULE_TYPE_VALIDATOR) {
            if (!s.validators[module]) revert ModuleNotInstalled();
            s.validators[module] = false;
        } else if (typeId == MODULE_TYPE_EXECUTOR) {
            if (!s.executors[module]) revert ModuleNotInstalled();
            s.executors[module] = false;
        } else if (typeId == MODULE_TYPE_HOOK) {
            if (!s.isHook[module]) revert ModuleNotInstalled();
            s.isHook[module] = false;
            _removeHook(s, module);
        } else {
            revert UnsupportedModuleType();
        }

        try IModule(module).onUninstall(deInitData) {} catch {}
        emit ModuleUninstalled(typeId, module);
    }

    function isModuleInstalled(uint256 typeId, address module, bytes calldata) external view returns (bool) {
        AccountStorage.Layout storage s = AccountStorage.layout();
        if (typeId == MODULE_TYPE_VALIDATOR) return s.validators[module];
        if (typeId == MODULE_TYPE_EXECUTOR) return s.executors[module];
        if (typeId == MODULE_TYPE_HOOK) return s.isHook[module];
        return false;
    }

    function getHooks() external view returns (address[] memory) {
        return AccountStorage.layout().hooks;
    }

    // ───────────────────────── ERC-1271 ─────────────────────────

    /// @notice 合约签名校验：ROOT(ecrecover) 或路由到已安装 validator / ROOT ecrecover, else route to a validator.
    /// @dev 1) 7702 EOA 现在带 code，朴素验签会跳过 ecrecover；此处显式回退到 EOA 地址。
    ///         A 7702 EOA now has code; naive verifiers skip ecrecover, so we fall back to it explicitly.
    ///      2) 待验消息先用 PersonalSign typehash 包裹，确保与执行授权摘要(execHash)互不相交（防越域重放）。
    ///         The message is wrapped with the PersonalSign typehash so it can never collide with an execHash.
    ///      3) 任何畸形签名都返回 ERC1271_FAIL，而非 revert / any malformed signature returns FAIL, never reverts.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        bytes32 wrapped = _personalSignHash(hash);

        if (signature.length == 65) {
            return ECDSA.recover(wrapped, signature) == address(this) ? ERC1271_MAGIC : ERC1271_FAIL;
        }
        // 模块路由用 try/catch 兜底，畸形输入不 revert / module routing guarded so malformed input can't revert.
        try this.validateViaModule(wrapped, signature) returns (bool ok) {
            return ok ? ERC1271_MAGIC : ERC1271_FAIL;
        } catch {
            return ERC1271_FAIL;
        }
    }

    /// @dev 仅供 isValidSignature 通过 this.call 自调用 / only self-callable, used by isValidSignature's try/catch.
    function validateViaModule(bytes32 wrapped, bytes calldata signature) external view returns (bool) {
        if (msg.sender != address(this)) revert Unauthorized();
        (address validator, bytes memory inner) = abi.decode(signature, (address, bytes));
        AccountStorage.Layout storage s = AccountStorage.layout();
        return s.validators[validator] && IValidator(validator).validateSignature(wrapped, inner);
    }

    // ───────────────────────── 视图 / views ─────────────────────────

    function getNonce() external view returns (uint256) {
        return AccountStorage.layout().nonce;
    }

    /// @notice 计算签名路径的 EIP-712 摘要（供链下/测试构造签名）/ compute the signed-path digest (off-chain/tests).
    function hashExecute(uint256 nonce, Call[] calldata calls) external view returns (bytes32) {
        return _execHash(nonce, keccak256(abi.encode(calls)));
    }

    /// @notice 计算 ERC-1271 消息的包裹摘要（链下需对此签名）/ the wrapped digest a signer must sign for ERC-1271.
    function hashPersonalSign(bytes32 hash) external view returns (bytes32) {
        return _personalSignHash(hash);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return 0xbc197c81;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7 // ERC-165
            || id == 0x1626ba7e // ERC-1271
            || id == 0x150b7a02 // ERC-721 receiver
            || id == 0x4e2312e0; // ERC-1155 receiver
    }

    // ───────────────────────── 内部 / internal ─────────────────────────

    function _executeCalls(Call[] memory calls, bool allowSelfCall) internal returns (bytes[] memory results) {
        AccountStorage.Layout storage s = AccountStorage.layout();
        uint256 n = calls.length;
        results = new bytes[](n);
        for (uint256 i; i < n; i++) {
            address to = calls[i].target;
            if (to == address(0)) to = address(this); // ERC-7821 归一化 / normalization
            if (!allowSelfCall) {
                // 非 ROOT 路径严禁触达账户自身或任何已安装模块（含 address(0) 归一化）。
                // 否则 executor/session 可经模块配置项(setPassKey/installSession)越权接管账户。
                // Non-root paths must reach neither the account nor any installed module; otherwise an
                // executor/session could escalate via module config setters (setPassKey/installSession).
                if (to == address(this)) revert SelfCallNotAllowed();
                if (s.validators[to] || s.executors[to] || s.isHook[to]) revert ModuleTargetNotAllowed();
            }

            (bool ok, bytes memory ret) = to.call{value: calls[i].value}(calls[i].data);
            if (!ok) {
                assembly {
                    revert(add(ret, 0x20), mload(ret)) // 冒泡原始 revert / bubble revert data
                }
            }
            results[i] = ret;
        }
    }

    /// @dev 快照 hook 地址与其 preCheck 返回值；防止执行期间增删 hook 造成 _postHooks 错位/越界。
    ///      Snapshot hook addresses + preCheck data so mid-execution (un)install can't desync _postHooks.
    function _preHooks(address sender, uint256 value, bytes calldata data)
        internal
        returns (address[] memory hookList, bytes[] memory hookData)
    {
        address[] storage hooks = AccountStorage.layout().hooks;
        uint256 n = hooks.length;
        hookList = new address[](n);
        hookData = new bytes[](n);
        for (uint256 i; i < n; i++) {
            hookList[i] = hooks[i];
            hookData[i] = IHook(hooks[i]).preCheck(sender, value, data);
        }
    }

    function _postHooks(address[] memory hookList, bytes[] memory hookData) internal {
        for (uint256 i; i < hookList.length; i++) {
            IHook(hookList[i]).postCheck(hookData[i]);
        }
    }

    function _removeHook(AccountStorage.Layout storage s, address module) internal {
        address[] storage hooks = s.hooks;
        uint256 n = hooks.length;
        for (uint256 i; i < n; i++) {
            if (hooks[i] == module) {
                hooks[i] = hooks[n - 1];
                hooks.pop();
                return;
            }
        }
    }

    function _sumValues(Call[] memory calls) internal pure returns (uint256 total) {
        for (uint256 i; i < calls.length; i++) {
            total += calls[i].value;
        }
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
    }

    function _execHash(uint256 nonce, bytes32 callsHash) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(EXECUTE_TYPEHASH, nonce, callsHash));
        return keccak256(abi.encodePacked(hex"1901", _domainSeparator(), structHash));
    }

    function _personalSignHash(bytes32 hash) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, hash));
        return keccak256(abi.encodePacked(hex"1901", _domainSeparator(), structHash));
    }

    /// @dev 解析 ERC-7821 mode：返回 1(无 opData) / 2(带 opData) / 0(不支持)。
    ///      Decode ERC-7821 mode: 1 (no opData) / 2 (with opData) / 0 (unsupported).
    function _modeId(bytes32 mode) internal pure returns (uint256) {
        if (mode[0] != 0x01 || mode[1] != 0x00) return 0; // calltype=batch, exectype=revert-on-failure
        bytes4 selector = bytes4(mode << 48); // bytes[6..9]
        if (selector == 0x00000000) return 1;
        if (selector == 0x78210001) return 2;
        return 0;
    }
}
