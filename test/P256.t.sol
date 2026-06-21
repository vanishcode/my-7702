// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {P256} from "../src/lib/P256.sol";
import {P256Verifier} from "./vendor/P256Verifier.sol";

/// @notice P256 库：已知向量、low-s 强制、被篡改/零值拒绝。
///         P256 lib: known vectors, low-s enforcement, tampered/zero rejection.
contract P256Test is Test {
    function setUp() public {
        vm.etch(address(0x100), address(new P256Verifier()).code);
    }

    // go-ethereum p256Verify.json 首个合法向量 / canonical valid vector.
    function test_ValidVector() public view {
        assertTrue(
            P256.verify(
                0x4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d,
                0xa73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac,
                0x36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60,
                0x4aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff3,
                0x7618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e
            )
        );
    }

    // Daimo 可塑性向量（high-s），必须被 low-s 策略拒绝 / high-s must be rejected.
    function test_HighSRejected() public view {
        assertFalse(
            P256.verify(
                0x267f9ea080b54bbea2443dff8aa543604564329783b6a515c6663a691c555490,
                0x01655c1753db6b61a9717e4ccc5d6c4bf7681623dd54c2d6babc55125756661c,
                0xf073023b6de130f18510af41f64f067c39adccd59f8789a55dbbe822b0ea2317,
                0x65a2fa44daad46eab0278703edb6c4dcf5e30b8a9aec09fdc71a56f52aa392e4,
                0x4a7a9e4604aa36898209997288e902ac544a555e4b5e0a9efef2b59233f3f437
            )
        );
    }

    // 篡改 hash 最后一字节：预编译返回 0-word，应判无效 / tampered hash -> invalid.
    function test_TamperedHashRejected() public view {
        assertFalse(
            P256.verify(
                0x4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4e,
                0xa73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac,
                0x36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60,
                0x4aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff3,
                0x7618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e
            )
        );
    }

    function test_ZeroRorS_Rejected() public view {
        bytes32 one = bytes32(uint256(1));
        assertFalse(P256.verify(one, bytes32(0), one, one, one)); // r == 0
        assertFalse(P256.verify(one, one, bytes32(0), one, one)); // s == 0
    }
}
