// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Account as Wallet} from "../src/Account.sol";
import {Call} from "../src/lib/Types.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/// @dev 诊断用：fork MegaETH，模拟 7702 账户(etch impl code) 自发批量执行 mint。运行后删除。
contract ScratchForkMintTest is Test {
    bytes32 constant MODE_BATCH = 0x0100000000000000000000000000000000000000000000000000000000000000;
    address constant IMPL = 0x056EB0b17d8640b6DD1582f82B12A44A408aB5b5;
    address constant USDM = 0x1BeFa17Db4c32dA66ec5A22e6462Fd8af839C788;

    function test_fork_mint_only() public {
        vm.createSelectFork("megaeth_testnet");
        address acct = makeAddr("acct");
        vm.etch(acct, IMPL.code);
        vm.deal(acct, 1 ether);

        Call[] memory calls = new Call[](1);
        calls[0] = Call(USDM, 0, abi.encodeWithSignature("mint(address,uint256)", acct, uint256(100_000_000)));

        uint256 bal0 = IERC20(USDM).balanceOf(acct);
        vm.prank(acct);
        Wallet(payable(acct)).execute(MODE_BATCH, abi.encode(calls));
        uint256 bal1 = IERC20(USDM).balanceOf(acct);
        console2.log("mint-only minted:", bal1 - bal0);
        assertEq(bal1 - bal0, 100_000_000);
    }

    function test_fork_mint_plus_selftransfer() public {
        vm.createSelectFork("megaeth_testnet");
        address acct = makeAddr("acct2");
        vm.etch(acct, IMPL.code);
        vm.deal(acct, 1 ether);

        Call[] memory calls = new Call[](2);
        calls[0] = Call(USDM, 0, abi.encodeWithSignature("mint(address,uint256)", acct, uint256(100_000_000)));
        calls[1] = Call(acct, 0.0001 ether, "");

        uint256 bal0 = IERC20(USDM).balanceOf(acct);
        vm.prank(acct);
        Wallet(payable(acct)).execute(MODE_BATCH, abi.encode(calls));
        uint256 bal1 = IERC20(USDM).balanceOf(acct);
        console2.log("mint+transfer minted:", bal1 - bal0);
        assertEq(bal1 - bal0, 100_000_000);
    }
}
