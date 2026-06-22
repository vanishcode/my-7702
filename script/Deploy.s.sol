// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Account as Wallet} from "../src/Account.sol";
import {SessionKeyValidator} from "../src/modules/SessionKeyValidator.sol";
import {WebAuthnValidator} from "../src/modules/WebAuthnValidator.sol";
import {SpendingLimitHook} from "../src/modules/SpendingLimitHook.sol";
import {ExampleExecutor} from "../src/modules/ExampleExecutor.sol";
import {MultisigValidator} from "../src/modules/MultisigValidator.sol";

/// @notice 部署账户实现单例与五个示例模块 / deploy the account singleton and the five example modules.
/// @dev    用法 / usage:
///         forge script script/Deploy.s.sol --rpc-url megaeth_testnet --private-key $PRIVATE_KEY --broadcast
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        Wallet impl = new Wallet();
        SessionKeyValidator sessionValidator = new SessionKeyValidator();
        WebAuthnValidator webauthnValidator = new WebAuthnValidator();
        SpendingLimitHook spendingHook = new SpendingLimitHook();
        ExampleExecutor exampleExecutor = new ExampleExecutor();
        MultisigValidator multisigValidator = new MultisigValidator();

        vm.stopBroadcast();

        console2.log("Account (delegate impl):", address(impl));
        console2.log("SessionKeyValidator:    ", address(sessionValidator));
        console2.log("WebAuthnValidator:      ", address(webauthnValidator));
        console2.log("SpendingLimitHook:      ", address(spendingHook));
        console2.log("ExampleExecutor:        ", address(exampleExecutor));
        console2.log("MultisigValidator:      ", address(multisigValidator));
    }
}
