// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest, Target} from "./Base.t.sol";
import {Account as Wallet} from "../src/Account.sol";
import {Call} from "../src/lib/Types.sol";
import {SessionKeyValidator} from "../src/modules/SessionKeyValidator.sol";
import {WebAuthnValidator} from "../src/modules/WebAuthnValidator.sol";

/// @notice Session key：作用域内执行 + 各种越界/过期/撤销/越权拒绝。
///         Session keys: in-scope execution + out-of-scope / expiry / revoke / escalation rejections.
contract SessionKeyValidatorTest is BaseTest {
    uint256 internal sessionPk = 0x5E5510;
    address internal sessionKey;
    Target internal other;

    function setUp() public override {
        super.setUp();
        sessionKey = vm.addr(sessionPk);
        other = new Target();

        // 安装 session 验证器模块 / install the session validator module.
        _install(MODULE_TYPE_VALIDATOR, address(sessionValidator), "");
        // 登记一个 session：仅 target、仅 ping、单笔 ≤ 1 ETH、永不过期。
        // Register a session: only `target`, only ping, per-call <= 1 ETH, never expires.
        _installSession(0, 0, 1 ether, _targets(address(target)), _selectors(Target.ping.selector));
    }

    function test_Session_ExecutesWithinScope() public {
        Call[] memory calls = _oneCall(address(target), 0.5 ether, abi.encodeCall(Target.ping, (123)));
        bytes memory opData = _sessionOpData(sessionPk, calls);

        vm.prank(relayer);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));

        assertEq(target.value(), 123);
        assertEq(target.received(), 0.5 ether);
    }

    function test_Session_RejectsDisallowedTarget() public {
        Call[] memory calls = _oneCall(address(other), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _sessionOpData(sessionPk, calls);
        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_Session_RejectsDisallowedSelector() public {
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.boom, ()));
        bytes memory opData = _sessionOpData(sessionPk, calls);
        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_Session_RejectsOverValueCap() public {
        Call[] memory calls = _oneCall(address(target), 2 ether, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _sessionOpData(sessionPk, calls);
        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_Session_Expired() public {
        // 重新登记一个会过期的 session / re-register a session that expires.
        _installSession(
            0, uint48(block.timestamp + 100), 1 ether, _targets(address(target)), _selectors(Target.ping.selector)
        );
        vm.warp(block.timestamp + 101);

        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _sessionOpData(sessionPk, calls);
        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_Session_NotYetValid() public {
        _installSession(
            uint48(block.timestamp + 100), 0, 1 ether, _targets(address(target)), _selectors(Target.ping.selector)
        );

        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _sessionOpData(sessionPk, calls);
        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_Session_Revoked() public {
        vm.prank(eoa);
        sessionValidator.revokeSession(sessionKey);

        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _sessionOpData(sessionPk, calls);
        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    /// @notice 越权关键防线：session 不能把账户自身作为 target 去打 admin。
    ///         Key escalation defense: a session cannot target the account itself to reach admin.
    function test_Session_CannotSelfCall() public {
        bytes memory adminCalldata = abi.encodeCall(
            Wallet.installModule, (MODULE_TYPE_EXECUTOR, address(exampleExecutor), abi.encode(sessionKey))
        );
        Call[] memory calls = _oneCall(address(account), 0, adminCalldata);
        bytes memory opData = _sessionOpData(sessionPk, calls);

        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector); // session 校验阶段即拒绝 / rejected at validation
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    /// @notice address(0) 归一化为账户自身，也必须被拦 / address(0) normalizes to self and must be blocked too.
    function test_Session_CannotCallZeroAddress() public {
        Call[] memory calls = _oneCall(address(0), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _sessionOpData(sessionPk, calls);
        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    /// @notice 纵深防御：即使 owner 误把"已安装模块"加入 session 白名单，核心层仍拦截（防越权配置）。
    ///         Defense-in-depth: even if the owner wrongly allowlists an installed module, the core blocks it.
    function test_Session_CannotTargetInstalledModule() public {
        _install(MODULE_TYPE_VALIDATOR, address(webauthnValidator), "");
        _installSession(
            0, 0, 0, _targets(address(webauthnValidator)), _selectors(WebAuthnValidator.setPassKey.selector)
        );

        bytes memory evil =
            abi.encodeCall(WebAuthnValidator.setPassKey, (bytes32(uint256(1)), bytes32(uint256(2)), false));
        Call[] memory calls = _oneCall(address(webauthnValidator), 0, evil);
        bytes memory opData = _sessionOpData(sessionPk, calls);

        vm.prank(relayer);
        vm.expectRevert(Wallet.ModuleTargetNotAllowed.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_Session_WrongKeyRejected() public {
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        bytes memory opData = _sessionOpData(uint256(0xBADBAD), calls); // 未登记的 key / unregistered key
        vm.prank(relayer);
        vm.expectRevert(Wallet.InvalidSignature.selector);
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    // ───────────────────────── helpers ─────────────────────────

    function _installSession(
        uint48 validAfter,
        uint48 validUntil,
        uint256 cap,
        address[] memory targets,
        bytes4[] memory selectors
    ) internal {
        SessionKeyValidator.Policy memory p;
        p.validAfter = validAfter;
        p.validUntil = validUntil;
        p.perCallEthCap = cap;
        p.targets = targets;
        p.selectors = selectors;
        vm.prank(eoa);
        sessionValidator.installSession(sessionKey, p);
    }

    function _targets(address a) internal pure returns (address[] memory t) {
        t = new address[](1);
        t[0] = a;
    }

    function _selectors(bytes4 s) internal pure returns (bytes4[] memory r) {
        r = new bytes4[](1);
        r[0] = s;
    }
}
