// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest, Target} from "./Base.t.sol";
import {Account as Wallet} from "../src/Account.sol";
import {Call} from "../src/lib/Types.sol";

/// @notice 核心账户：批量执行、签名路径、模块装卸、ERC-1271、mode 解析。
///         Core account: batch execution, signed path, module (un)install, ERC-1271, mode decoding.
contract AccountTest is BaseTest {
    function test_SelfBatch_ExecutesCalls() public {
        Call[] memory calls = new Call[](2);
        calls[0] = Call(address(target), 0, abi.encodeCall(Target.ping, (11)));
        calls[1] = Call(address(target), 1 ether, abi.encodeCall(Target.ping, (22)));

        vm.prank(eoa);
        account.execute(MODE_BATCH, abi.encode(calls));

        assertEq(target.value(), 22);
        assertEq(target.received(), 1 ether);
        assertEq(target.lastCaller(), eoa);
    }

    function test_SelfBatch_RevertsForNonSelf() public {
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        vm.prank(relayer);
        vm.expectRevert(Wallet.Unauthorized.selector);
        account.execute(MODE_BATCH, abi.encode(calls));
    }

    function test_SelfBatch_BubblesRevert() public {
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.boom, ()));
        vm.prank(eoa);
        vm.expectRevert(bytes("boom"));
        account.execute(MODE_BATCH, abi.encode(calls));
    }

    function test_RootOpData_Batch() public {
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (33)));
        bytes memory opData = _rootOpData(calls);

        uint256 nonceBefore = account.getNonce();
        vm.prank(relayer); // 任意提交者 / any submitter
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));

        assertEq(target.value(), 33);
        assertEq(account.getNonce(), nonceBefore + 1);
    }

    function test_RootOpData_ReplayReverts() public {
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (44)));
        bytes memory opData = _rootOpData(calls);

        vm.prank(relayer);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));

        // 同一 opData 重放：nonce 已自增，execHash 不再匹配 / replay fails: nonce advanced.
        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_RootOpData_WrongSignerReverts() public {
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        bytes32 h = account.hashExecute(account.getNonce(), calls);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(0xDEAD), h); // 非 EOA 私钥 / not the EOA key
        bytes memory opData = abi.encode(eoa, abi.encodePacked(r, s, v));

        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_ModuleInstallUninstall() public {
        _install(MODULE_TYPE_VALIDATOR, address(sessionValidator), "");
        assertTrue(account.isModuleInstalled(MODULE_TYPE_VALIDATOR, address(sessionValidator), ""));

        _uninstall(MODULE_TYPE_VALIDATOR, address(sessionValidator), "");
        assertFalse(account.isModuleInstalled(MODULE_TYPE_VALIDATOR, address(sessionValidator), ""));
    }

    function test_InstallModule_OnlySelf() public {
        vm.prank(relayer);
        vm.expectRevert(Wallet.Unauthorized.selector);
        account.installModule(MODULE_TYPE_VALIDATOR, address(sessionValidator), "");
    }

    function test_InstallModule_WrongTypeReverts() public {
        // sessionValidator 不是 hook / sessionValidator is not a hook (type 4).
        vm.prank(eoa);
        vm.expectRevert(Wallet.InvalidModuleType.selector);
        account.installModule(MODULE_TYPE_HOOK, address(sessionValidator), "");
    }

    function test_HookInstall_TracksList() public {
        _install(MODULE_TYPE_HOOK, address(spendingHook), abi.encode(uint256(5 ether)));
        address[] memory hooks = account.getHooks();
        assertEq(hooks.length, 1);
        assertEq(hooks[0], address(spendingHook));
    }

    function test_ERC1271_RootSignature() public view {
        bytes32 hash = keccak256("hello world");
        // 链下需对 PersonalSign 包裹摘要签名 / the signer signs the wrapped PersonalSign digest.
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPk, account.hashPersonalSign(hash));
        bytes memory sig = abi.encodePacked(r, s, v);
        assertEq(account.isValidSignature(hash, sig), bytes4(0x1626ba7e));
    }

    function test_ERC1271_BadSignatureFails() public view {
        bytes32 hash = keccak256("hello world");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(0xDEAD), account.hashPersonalSign(hash));
        bytes memory sig = abi.encodePacked(r, s, v);
        assertEq(account.isValidSignature(hash, sig), bytes4(0xffffffff));
    }

    function test_ERC1271_MalformedReturnsFail() public view {
        // 畸形签名应返回 FAIL 而非 revert / malformed signatures return FAIL, never revert.
        assertEq(account.isValidSignature(keccak256("x"), hex"deadbeef"), bytes4(0xffffffff));
        assertEq(account.isValidSignature(keccak256("x"), ""), bytes4(0xffffffff));
    }

    /// @notice 消息签名空间与执行授权空间互不相交（防越域重放）/ message-sig space disjoint from execution-auth.
    function test_ERC1271_DomainSeparation() public {
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (5)));
        bytes32 execHash = account.hashExecute(account.getNonce(), calls);

        // 对 execHash 直接签名的签名，不能被当作 ERC-1271 消息接受 / an execHash sig is not a valid message sig.
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPk, execHash);
        bytes memory sigExec = abi.encodePacked(r, s, v);
        assertEq(account.isValidSignature(execHash, sigExec), bytes4(0xffffffff));

        // 反向：合法 ERC-1271 消息签名不能授权 execute / a valid message sig cannot authorize execution.
        (v, r, s) = vm.sign(eoaPk, account.hashPersonalSign(execHash));
        bytes memory sigMsg = abi.encodePacked(r, s, v);
        assertEq(account.isValidSignature(execHash, sigMsg), bytes4(0x1626ba7e));
        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, abi.encode(eoa, sigMsg)));
    }

    function test_ModeSupport() public view {
        assertTrue(account.supportsExecutionMode(MODE_BATCH));
        assertTrue(account.supportsExecutionMode(MODE_BATCH_OPDATA));
        assertFalse(account.supportsExecutionMode(bytes32(0)));
        // batch-of-batches (id3) 不支持 / unsupported.
        assertFalse(account.supportsExecutionMode(0x0100000000007821000200000000000000000000000000000000000000000000));
    }

    /// @notice 用真实 7702 cheatcode 验证委托确实生效 / verify genuine 7702 delegation via the real cheatcode.
    function test_RealDelegation_SelfBatch() public {
        uint256 pk = 0xB0B;
        address payable bob = payable(vm.addr(pk));
        vm.deal(bob, 1 ether);

        vm.signAndAttachDelegation(address(impl), pk);
        vm.prank(bob);
        Wallet(bob).execute(MODE_BATCH, abi.encode(_oneCall(address(target), 0, abi.encodeCall(Target.ping, (77)))));

        assertEq(target.value(), 77);
        assertEq(target.lastCaller(), bob);
    }
}
