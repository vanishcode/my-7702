// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest, Target} from "./Base.t.sol";
import {Account as Wallet} from "../src/Account.sol";
import {Call} from "../src/lib/Types.sol";
import {MultisigValidator} from "../src/modules/MultisigValidator.sol";

/// @notice M-of-N 多签验证器：阈值放行 + 去重/乱序/未登记拒绝 + 越权(admin/模块)防线 + 配置/重配/卸载 + ERC-1271。
///         M-of-N multisig: threshold pass + dedup/order/unregistered rejections + admin/module escalation
///         defenses + config/reconfig/uninstall + ERC-1271.
contract MultisigValidatorTest is BaseTest {
    bytes4 internal constant ERC1271_MAGIC = 0x1626ba7e;
    bytes4 internal constant ERC1271_FAIL = 0xffffffff;

    uint256[] internal pks; // 已按签名者地址升序 / sorted ascending by signer address
    address[] internal signers; // = addresses of pks
    uint256 internal threshold = 2;

    function setUp() public override {
        super.setUp();

        // 三个演示联签私钥，按地址升序排好（合约要求签名严格升序）。
        // Three demo signer keys, sorted ascending by address (the contract requires ascending sigs).
        uint256[] memory raw = new uint256[](3);
        raw[0] = 0xA11CE5161;
        raw[1] = 0xB0B5162;
        raw[2] = 0xCA401533;
        pks = _sortPks(raw);
        signers = new address[](3);
        for (uint256 i; i < 3; i++) {
            signers[i] = vm.addr(pks[i]);
        }

        // 安装并配置 2-of-3 / install and configure 2-of-3.
        _install(MODULE_TYPE_VALIDATOR, address(multisigValidator), abi.encode(signers, threshold));
    }

    // ───────────────────────── 放行 / authorize ─────────────────────────

    function test_Multisig_ExecutesWithThreshold() public {
        Call[] memory calls = _oneCall(address(target), 0.5 ether, abi.encodeCall(Target.ping, (777)));
        bytes memory opData = _multisigOpData(_first(2), calls);

        vm.prank(relayer);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));

        assertEq(target.value(), 777);
        assertEq(target.received(), 0.5 ether);
    }

    function test_Multisig_ExecutesWithAllSigners() public {
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _multisigOpData(_first(3), calls);

        vm.prank(relayer);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
        assertEq(target.value(), 1);
    }

    // ───────────────────────── 拒绝 / reject ─────────────────────────

    function test_Multisig_RejectsBelowThreshold() public {
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _multisigOpData(_first(1), calls); // 仅 1 个签名 / only one signature

        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_Multisig_RejectsDuplicateSigner() public {
        // 同一签名者签两份：破坏"严格升序" → 去重失败 / same signer twice breaks strict ascending.
        uint256[] memory dup = new uint256[](2);
        dup[0] = pks[0];
        dup[1] = pks[0];

        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _multisigOpData(dup, calls);

        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_Multisig_RejectsWrongOrder() public {
        // 两个合法签名者，但降序排列 → 被严格升序检查拒绝 / valid signers, descending order rejected.
        uint256[] memory rev = new uint256[](2);
        rev[0] = pks[1];
        rev[1] = pks[0];

        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _multisigOpData(rev, calls);

        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_Multisig_RejectsUnregisteredSigner() public {
        // 两个合法 secp256k1 签名，但签名者都不在登记集合中 / valid sigs, but signers aren't registered.
        uint256[] memory strangers = _sortPks(_pair(0xDEAD1, 0xBEEF2));

        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _multisigOpData(strangers, calls);

        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    // ───────────────────────── 越权防线（核心强制）/ escalation defenses (enforced by core) ────────────

    /// @notice 即便满足阈值，多签也无法触达账户自身(admin)：核心非 ROOT 路径强制拦截 self-call。
    ///         Even at threshold, the multisig cannot reach admin: the core blocks self-call on non-ROOT paths.
    function test_Multisig_CannotSelfCall() public {
        bytes memory adminCalldata =
            abi.encodeCall(Wallet.installModule, (MODULE_TYPE_EXECUTOR, address(exampleExecutor), abi.encode(eoa)));
        Call[] memory calls = _oneCall(address(account), 0, adminCalldata);
        bytes memory opData = _multisigOpData(_first(2), calls);

        vm.prank(relayer);
        vm.expectRevert(Wallet.SelfCallNotAllowed.selector); // 校验通过，执行阶段拦截 / passes auth, blocked at execution
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    /// @notice 多签也无法把"已安装模块"作为 target 调其配置项 / cannot target an installed module either.
    function test_Multisig_CannotTargetInstalledModule() public {
        _install(MODULE_TYPE_VALIDATOR, address(sessionValidator), "");

        Call[] memory calls =
            _oneCall(address(sessionValidator), 0, abi.encodeWithSignature("revokeSession(address)", eoa));
        bytes memory opData = _multisigOpData(_first(2), calls);

        vm.prank(relayer);
        vm.expectRevert(Wallet.ModuleTargetNotAllowed.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    // ───────────────────────── 配置 / config ─────────────────────────

    function test_Multisig_Config() public view {
        (address[] memory s, uint256 t, bool exists) = multisigValidator.getConfig(eoa);
        assertTrue(exists);
        assertEq(t, 2);
        assertEq(s.length, 3);
        assertEq(s[0], signers[0]);
        assertEq(s[2], signers[2]);
    }

    function test_Multisig_RejectsInvalidThreshold() public {
        vm.startPrank(eoa);
        vm.expectRevert(MultisigValidator.InvalidThreshold.selector);
        multisigValidator.setConfig(signers, 0); // 0 不合法 / zero invalid

        vm.expectRevert(MultisigValidator.InvalidThreshold.selector);
        multisigValidator.setConfig(signers, 4); // > N 不合法 / above N invalid
        vm.stopPrank();
    }

    function test_Multisig_RejectsUnsortedOrZeroSigner() public {
        address[] memory descending = new address[](2);
        descending[0] = signers[2];
        descending[1] = signers[0];

        address[] memory withZero = new address[](2);
        withZero[0] = address(0);
        withZero[1] = signers[0];

        vm.startPrank(eoa);
        vm.expectRevert(MultisigValidator.UnsortedOrZeroSigner.selector);
        multisigValidator.setConfig(descending, 1);

        vm.expectRevert(MultisigValidator.UnsortedOrZeroSigner.selector);
        multisigValidator.setConfig(withZero, 1);
        vm.stopPrank();
    }

    /// @notice 重新配置（无需卸载重装）：改为 1-of-1，单签即可执行 / reconfigure in place to 1-of-1.
    function test_Multisig_ReconfigureThenExecute() public {
        address[] memory one = new address[](1);
        one[0] = signers[0];
        vm.prank(eoa);
        multisigValidator.setConfig(one, 1);

        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (42)));
        bytes memory opData = _multisigOpData(_first(1), calls);

        vm.prank(relayer);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
        assertEq(target.value(), 42);
    }

    function test_Multisig_Uninstall() public {
        _uninstall(MODULE_TYPE_VALIDATOR, address(multisigValidator), "");

        (,, bool exists) = multisigValidator.getConfig(eoa);
        assertFalse(exists);

        // 模块已卸载：execute 在 validator 注册表查不到 → Unauthorized / module gone -> Unauthorized.
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _multisigOpData(_first(2), calls);
        vm.prank(relayer);
        vm.expectRevert(Wallet.Unauthorized.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    // ───────────────────────── ERC-1271 ─────────────────────────

    function test_Multisig_ERC1271_Magic() public view {
        bytes32 msgHash = keccak256("hello multisig");
        bytes32 wrapped = account.hashPersonalSign(msgHash);
        bytes memory sig = _multisig1271(_first(2), wrapped);
        assertEq(account.isValidSignature(msgHash, sig), ERC1271_MAGIC);
    }

    function test_Multisig_ERC1271_BelowThresholdFails() public view {
        bytes32 msgHash = keccak256("hello multisig");
        bytes32 wrapped = account.hashPersonalSign(msgHash);
        bytes memory sig = _multisig1271(_first(1), wrapped); // 仅 1 签 / single signature
        assertEq(account.isValidSignature(msgHash, sig), ERC1271_FAIL);
    }

    // ───────────────────────── helpers ─────────────────────────

    /// @dev 取已排序 pks 的前 k 个 / first k of the sorted pks.
    function _first(uint256 k) internal view returns (uint256[] memory r) {
        r = new uint256[](k);
        for (uint256 i; i < k; i++) {
            r[i] = pks[i];
        }
    }

    function _pair(uint256 a, uint256 b) internal pure returns (uint256[] memory r) {
        r = new uint256[](2);
        r[0] = a;
        r[1] = b;
    }

    /// @dev 插入排序：按 vm.addr(pk) 升序 / insertion-sort pks ascending by signer address.
    function _sortPks(uint256[] memory a) internal pure returns (uint256[] memory) {
        for (uint256 i = 1; i < a.length; i++) {
            uint256 key = a[i];
            address ka = vm.addr(key);
            uint256 j = i;
            while (j > 0 && vm.addr(a[j - 1]) > ka) {
                a[j] = a[j - 1];
                j--;
            }
            a[j] = key;
        }
        return a;
    }

    /// @dev 多签执行 opData：每个 pk 对 execHash 签名，按入参顺序拼成 bytes[] / build the signed-path opData.
    function _multisigOpData(uint256[] memory signerPks, Call[] memory calls) internal view returns (bytes memory) {
        bytes32 h = account.hashExecute(account.getNonce(), calls);
        bytes[] memory sigs = new bytes[](signerPks.length);
        for (uint256 i; i < signerPks.length; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPks[i], h);
            sigs[i] = abi.encodePacked(r, s, v);
        }
        return abi.encode(address(multisigValidator), abi.encode(sigs));
    }

    /// @dev ERC-1271 内层签名：每个 pk 对 wrapped 摘要签名 / inner sig for isValidSignature over the wrapped hash.
    function _multisig1271(uint256[] memory signerPks, bytes32 wrapped) internal view returns (bytes memory) {
        bytes[] memory sigs = new bytes[](signerPks.length);
        for (uint256 i; i < signerPks.length; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPks[i], wrapped);
            sigs[i] = abi.encodePacked(r, s, v);
        }
        return abi.encode(address(multisigValidator), abi.encode(sigs));
    }
}
