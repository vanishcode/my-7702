// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest, Target} from "./Base.t.sol";
import {Account as Wallet} from "../src/Account.sol";
import {Call} from "../src/lib/Types.sol";
import {IModule} from "../src/interfaces/IERC7579Modules.sol";
import {WebAuthnValidator} from "../src/modules/WebAuthnValidator.sol";

/// @dev 重入攻击者：被调用时回调 account.execute / re-enters account.execute when called.
contract Reenterer {
    address payable internal account;
    bytes32 internal constant MODE_BATCH = 0x0100000000000000000000000000000000000000000000000000000000000000;

    constructor(address payable a) {
        account = a;
    }

    fallback() external payable {
        Wallet(account).execute(MODE_BATCH, abi.encode(new Call[](0)));
    }
}

/// @dev 恶意模块：onUninstall 故意 revert 想"自锁" / reverts in onUninstall to try to brick itself.
contract BadUninstallModule is IModule {
    function onInstall(bytes calldata) external {}

    function onUninstall(bytes calldata) external pure {
        revert("cannot uninstall me");
    }

    function isModuleType(uint256 typeId) external pure returns (bool) {
        return typeId == 1;
    }
}

/// @notice 对抗性测试：越权、重入、恶意模块、executor 隔离、hook 限额。
///         Adversarial tests: privilege escalation, reentrancy, malicious modules, executor isolation, hook caps.
contract SecurityTest is BaseTest {
    address internal operator = address(0x0FE7);

    // ───────────── 重入 / reentrancy ─────────────
    function test_Reentrancy_Blocked() public {
        Reenterer r = new Reenterer(eoa);
        Call[] memory calls = _oneCall(address(r), 0, "");

        vm.prank(eoa);
        vm.expectRevert(Wallet.Reentrancy.selector);
        account.execute(MODE_BATCH, abi.encode(calls));
    }

    // ───────────── 恶意模块拒卸 / malicious uninstall ─────────────
    function test_MaliciousModule_StillUninstalled() public {
        BadUninstallModule bad = new BadUninstallModule();
        _install(MODULE_TYPE_VALIDATOR, address(bad), "");
        assertTrue(account.isModuleInstalled(MODULE_TYPE_VALIDATOR, address(bad), ""));

        // onUninstall 会 revert，但 try/catch 吞掉，模块仍被移除 / removed despite reverting onUninstall.
        _uninstall(MODULE_TYPE_VALIDATOR, address(bad), "");
        assertFalse(account.isModuleInstalled(MODULE_TYPE_VALIDATOR, address(bad), ""));
    }

    // ───────────── executor 路径 / executor path ─────────────
    function test_Executor_HappyPath() public {
        _install(MODULE_TYPE_EXECUTOR, address(exampleExecutor), abi.encode(operator));

        Call[] memory calls = _oneCall(address(target), 1 ether, abi.encodeCall(Target.ping, (55)));
        vm.prank(operator);
        exampleExecutor.executeViaAccount(address(account), calls);

        assertEq(target.value(), 55);
        assertEq(target.received(), 1 ether);
    }

    function test_Executor_OnlyInstalled() public {
        // 未安装的地址直接调 executeFromExecutor / a non-installed caller hits executeFromExecutor.
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        vm.prank(address(0xDEAD));
        vm.expectRevert(Wallet.Unauthorized.selector);
        account.executeFromExecutor(MODE_BATCH, abi.encode(calls));
    }

    /// @notice 关键：即使是已安装的 executor，也无法触达账户自身的 admin 选择器。
    ///         Key: even an installed executor cannot reach the account's own admin selectors.
    function test_Executor_CannotReachAdmin() public {
        _install(MODULE_TYPE_EXECUTOR, address(exampleExecutor), abi.encode(operator));

        bytes memory adminCalldata = abi.encodeCall(Wallet.installModule, (MODULE_TYPE_VALIDATOR, address(0xBEEF), ""));
        Call[] memory calls = _oneCall(address(account), 0, adminCalldata);

        vm.prank(operator);
        vm.expectRevert(Wallet.SelfCallNotAllowed.selector);
        exampleExecutor.executeViaAccount(address(account), calls);
    }

    function test_Executor_OperatorGated() public {
        _install(MODULE_TYPE_EXECUTOR, address(exampleExecutor), abi.encode(operator));
        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (1)));
        // 非 operator 调 executor / a non-operator calls the executor.
        vm.prank(address(0xBAD));
        vm.expectRevert();
        exampleExecutor.executeViaAccount(address(account), calls);
    }

    /// @notice CRITICAL 回归：已安装 executor 不能驱动账户去配置其它模块（setPassKey 越权接管）。
    ///         CRITICAL regression: an installed executor cannot drive the account to configure another module.
    function test_Executor_CannotConfigureModule() public {
        _install(MODULE_TYPE_VALIDATOR, address(webauthnValidator), "");
        _install(MODULE_TYPE_EXECUTOR, address(exampleExecutor), abi.encode(operator));

        // executor 试图注册攻击者 passkey / attempt to register an attacker passkey via the validator module.
        bytes memory evil =
            abi.encodeCall(WebAuthnValidator.setPassKey, (bytes32(uint256(1)), bytes32(uint256(2)), false));
        Call[] memory calls = _oneCall(address(webauthnValidator), 0, evil);

        vm.prank(operator);
        vm.expectRevert(Wallet.ModuleTargetNotAllowed.selector);
        exampleExecutor.executeViaAccount(address(account), calls);
    }

    // ───────────── hook 限额 / hook cap ─────────────
    function test_Hook_BlocksOverLimit() public {
        _install(MODULE_TYPE_HOOK, address(spendingHook), abi.encode(uint256(1 ether)));

        // 实际从账户余额转出 2 ETH（> 1 ETH 上限），与 msg.value 无关 / true outflow 2 ETH > cap, not msg.value.
        Call[] memory calls = _oneCall(address(target), 2 ether, abi.encodeCall(Target.ping, (1)));
        vm.prank(eoa);
        vm.expectRevert(); // SpendingLimitExceeded
        account.execute(MODE_BATCH, abi.encode(calls));
    }

    function test_Hook_AllowsWithinLimit() public {
        _install(MODULE_TYPE_HOOK, address(spendingHook), abi.encode(uint256(5 ether)));

        Call[] memory calls = _oneCall(address(target), 1 ether, abi.encodeCall(Target.ping, (1)));
        vm.prank(eoa);
        account.execute{value: 1 ether}(MODE_BATCH, abi.encode(calls));
        assertEq(target.value(), 1);
    }

    // ───────────── admin 仅 self / admin only self ─────────────
    function test_Admin_UninstallOnlySelf() public {
        _install(MODULE_TYPE_VALIDATOR, address(sessionValidator), "");
        vm.prank(relayer);
        vm.expectRevert(Wallet.Unauthorized.selector);
        account.uninstallModule(MODULE_TYPE_VALIDATOR, address(sessionValidator), "");
    }
}
