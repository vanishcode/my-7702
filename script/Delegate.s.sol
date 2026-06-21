// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Account as Wallet} from "../src/Account.sol";

/// @notice 把 EOA 委托到账户实现，并在同一笔 type-4 交易里安装一个 validator 模块（自调用）。
///         Delegate an EOA to the account implementation and install a validator module in the same type-4 tx.
/// @dev    env: PRIVATE_KEY(委托的 EOA), IMPL(账户实现), VALIDATOR(要安装的 type-1 模块)。
///         用法 / usage:
///         IMPL=0x.. VALIDATOR=0x.. forge script script/Delegate.s.sol \
///           --rpc-url megaeth_testnet --private-key $PRIVATE_KEY --broadcast
contract Delegate is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address impl = vm.envAddress("IMPL");
        address validator = vm.envAddress("VALIDATOR");
        address payable eoa = payable(vm.addr(pk));

        vm.startBroadcast(pk);
        // 把下一笔调用标记为 7702（设置委托代码）/ designate the next call as a 7702 tx (sets delegation code).
        vm.signAndAttachDelegation(impl, pk);
        // EOA 自调用安装模块：msg.sender == address(this) == eoa（ROOT）/ self-call install (ROOT path).
        Wallet(eoa).installModule(1, validator, "");
        vm.stopBroadcast();

        console2.log("Delegated EOA:", eoa);
        console2.log("Installed validator:", validator);
    }
}
