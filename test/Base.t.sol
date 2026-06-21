// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
// forge-std 的 StdCheats 已定义 struct Account，故在测试里把合约别名为 Wallet。
// forge-std's StdCheats defines `struct Account`, so alias the contract to `Wallet` in tests.
import {Account as Wallet} from "../src/Account.sol";
import {Call} from "../src/lib/Types.sol";
import {SessionKeyValidator} from "../src/modules/SessionKeyValidator.sol";
import {WebAuthnValidator} from "../src/modules/WebAuthnValidator.sol";
import {SpendingLimitHook} from "../src/modules/SpendingLimitHook.sol";
import {ExampleExecutor} from "../src/modules/ExampleExecutor.sol";
import {P256Verifier} from "./vendor/P256Verifier.sol";

/// @dev 测试目标合约 / a simple call target used across tests.
contract Target {
    uint256 public value;
    uint256 public received;
    address public lastCaller;

    function ping(uint256 v) external payable {
        value = v;
        received += msg.value;
        lastCaller = msg.sender;
    }

    function boom() external pure {
        revert("boom");
    }

    receive() external payable {}
}

/// @dev 共享测试基座：把 Account 代码 etch 到 EOA（模拟 7702 委托），并在 0x100 放置 P256 verifier。
///      Shared base: etch Account code at the EOA (simulate 7702 delegation) and place a P256 verifier at 0x100.
contract BaseTest is Test {
    bytes32 internal constant MODE_BATCH = 0x0100000000000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant MODE_BATCH_OPDATA = 0x0100000000007821000100000000000000000000000000000000000000000000;

    uint256 internal constant MODULE_TYPE_VALIDATOR = 1;
    uint256 internal constant MODULE_TYPE_EXECUTOR = 2;
    uint256 internal constant MODULE_TYPE_HOOK = 4;

    Wallet internal impl;
    Wallet internal account; // = EOA with delegated code
    address payable internal eoa;
    uint256 internal eoaPk;

    address internal relayer = address(0xBEEF);
    Target internal target;

    SessionKeyValidator internal sessionValidator;
    WebAuthnValidator internal webauthnValidator;
    SpendingLimitHook internal spendingHook;
    ExampleExecutor internal exampleExecutor;

    function setUp() public virtual {
        impl = new Wallet();
        eoaPk = 0xA11CE;
        eoa = payable(vm.addr(eoaPk));

        // 模拟 7702：把实现的 runtime code 装到 EOA / simulate 7702 by installing runtime code at the EOA.
        vm.etch(eoa, address(impl).code);
        account = Wallet(eoa);
        vm.deal(eoa, 100 ether);

        // 本地 prague EVM 无 0x100 预编译，etch Daimo verifier / local prague EVM lacks 0x100; etch a verifier.
        vm.etch(address(0x100), address(new P256Verifier()).code);

        target = new Target();
        sessionValidator = new SessionKeyValidator();
        webauthnValidator = new WebAuthnValidator();
        spendingHook = new SpendingLimitHook();
        exampleExecutor = new ExampleExecutor();
    }

    // ───────────────────────── helpers ─────────────────────────

    function _oneCall(address to, uint256 value, bytes memory data) internal pure returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = Call(to, value, data);
    }

    /// @dev 账户自身安装模块（msg.sender==eoa==account）/ install a module as the account itself.
    function _install(uint256 typeId, address module, bytes memory initData) internal {
        vm.prank(eoa);
        account.installModule(typeId, module, initData);
    }

    function _uninstall(uint256 typeId, address module, bytes memory deInitData) internal {
        vm.prank(eoa);
        account.uninstallModule(typeId, module, deInitData);
    }

    /// @dev ROOT 签名 opData：validator==eoa，EOA secp256k1 签 execHash / root opData signed by the EOA key.
    function _rootOpData(Call[] memory calls) internal view returns (bytes memory) {
        bytes32 h = account.hashExecute(account.getNonce(), calls);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPk, h);
        return abi.encode(eoa, abi.encodePacked(r, s, v));
    }

    /// @dev session 签名 opData：validator==sessionValidator，sessionKey 签 execHash / session opData.
    function _sessionOpData(uint256 sessionPk, Call[] memory calls) internal view returns (bytes memory) {
        bytes32 h = account.hashExecute(account.getNonce(), calls);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionPk, h);
        return abi.encode(address(sessionValidator), abi.encodePacked(r, s, v));
    }
}
