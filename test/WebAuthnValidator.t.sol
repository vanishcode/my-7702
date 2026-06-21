// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest, Target} from "./Base.t.sol";
import {Call} from "../src/lib/Types.sol";
import {WebAuthn} from "../src/lib/WebAuthn.sol";
import {Base64Url} from "../src/lib/Base64Url.sol";

/// @notice Passkey/WebAuthn 验证器：真实浏览器向量 + 动态端到端 passkey 执行。
///         Passkey/WebAuthn validator: a real browser vector + a dynamic end-to-end passkey execution.
contract WebAuthnValidatorTest is BaseTest {
    uint256 internal constant P256_N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;

    /// @notice 用 Solady "Safari" 真实断言向量验证 WebAuthn 解析 + P256 / verify against a real Safari assertion.
    function test_RealBrowserVector() public {
        bytes32 x = 0x3f2be075ef57d6c8374ef412fe54fdd980050f70f4f3a00b5b1b32d2def7d28d;
        bytes32 y = 0x57095a365acc2590ade3583fabfe8fbd64a9ed3ec07520da00636fb21f0176c1;
        bytes32 challenge = 0xf631058a3ba1116acce12396fad0a125b5041c43f8e15723709f81aa8d5f4ccf;

        // 注册为本测试合约的 passkey（msg.sender == 本合约）/ register the passkey for this test contract.
        webauthnValidator.setPassKey(x, y, false);

        string memory clientDataJSON = string(
            abi.encodePacked(
                '{"type":"webauthn.get","challenge":"',
                Base64Url.encode(abi.encodePacked(challenge)),
                '","origin":"http://localhost:3005"}'
            )
        );

        WebAuthn.WebAuthnAuth memory a = WebAuthn.WebAuthnAuth({
            authenticatorData: hex"49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000101",
            clientDataJSON: clientDataJSON,
            challengeIndex: 23,
            typeIndex: 1,
            r: 0x60946081650523acad13c8eff94996a409b1ed60e923c90f9e366aad619adffa,
            s: 0x3216a237b73765d01b839e0832d73474bc7e63f4c86ef05fbbbfbeb34b35602b
        });

        assertTrue(webauthnValidator.validateSignature(challenge, abi.encode(a)));
        // 错误的 challenge 必须失败 / a wrong challenge must fail.
        assertFalse(webauthnValidator.validateSignature(keccak256("other"), abi.encode(a)));
    }

    /// @notice 动态端到端：派生 P256 公钥、对真实 execHash 签 WebAuthn 断言、经账户执行批量。
    ///         Dynamic e2e: derive a P256 pubkey, sign a WebAuthn assertion over the real execHash, execute.
    function test_Passkey_E2E_Execute() public {
        uint256 p256Pk = uint256(keccak256("passkey-private-key"));
        (uint256 x, uint256 y) = vm.publicKeyP256(p256Pk);

        // 安装 passkey 验证器并登记公钥 / install the passkey validator and register the key.
        _install(MODULE_TYPE_VALIDATOR, address(webauthnValidator), abi.encode(bytes32(x), bytes32(y), false));

        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (99)));
        bytes32 execHash = account.hashExecute(account.getNonce(), calls);

        bytes memory opData = _buildPasskeyOpData(p256Pk, execHash);

        vm.prank(relayer); // passkey 自身无法发交易，需任意提交者 / a passkey can't send txs; any submitter.
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));

        assertEq(target.value(), 99);
        assertEq(account.getNonce(), 1);
    }

    /// @notice 篡改 challenge 的 passkey 断言必须被拒 / a passkey assertion with the wrong challenge must revert.
    function test_Passkey_WrongChallengeReverts() public {
        uint256 p256Pk = uint256(keccak256("passkey-private-key"));
        (uint256 x, uint256 y) = vm.publicKeyP256(p256Pk);
        _install(MODULE_TYPE_VALIDATOR, address(webauthnValidator), abi.encode(bytes32(x), bytes32(y), false));

        Call[] memory calls = _oneCall(address(target), 0, abi.encodeCall(Target.ping, (99)));
        bytes memory opData = _buildPasskeyOpData(p256Pk, keccak256("not-the-exec-hash"));

        vm.prank(relayer);
        vm.expectRevert(); // InvalidSignature
        account.execute(MODE_BATCH_OPDATA, abi.encode(calls, opData));
    }

    /// @notice passkey 也可用于 ERC-1271 消息验签（对 PersonalSign 包裹摘要签名）。
    ///         A passkey can also satisfy ERC-1271 (signing the wrapped PersonalSign digest).
    function test_Passkey_ERC1271() public {
        uint256 p256Pk = uint256(keccak256("passkey-private-key"));
        (uint256 x, uint256 y) = vm.publicKeyP256(p256Pk);
        _install(MODULE_TYPE_VALIDATOR, address(webauthnValidator), abi.encode(bytes32(x), bytes32(y), false));

        bytes32 hash = keccak256("erc1271 message");
        // opData 结构 = abi.encode(validator, abi.encode(auth))，正是 isValidSignature 期望的 signature 编码。
        // opData layout = abi.encode(validator, abi.encode(auth)), which is exactly the signature isValidSignature wants.
        bytes memory signature = _buildPasskeyOpData(p256Pk, account.hashPersonalSign(hash));
        assertEq(account.isValidSignature(hash, signature), bytes4(0x1626ba7e));
    }

    /// @dev 用 P256 私钥对给定 challenge 构造 WebAuthn 断言并打包成 opData。
    ///      Build a WebAuthn assertion over `challenge` with a P256 key and pack it as opData.
    function _buildPasskeyOpData(uint256 p256Pk, bytes32 challenge) internal view returns (bytes memory) {
        string memory clientDataJSON = string(
            abi.encodePacked(
                '{"type":"webauthn.get","challenge":"',
                Base64Url.encode(abi.encodePacked(challenge)),
                '","origin":"http://localhost"}'
            )
        );
        // 37 字节 authenticatorData，flags=0x01(UP) / 37-byte authenticatorData with UP flag set.
        bytes memory authData = hex"49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630100000000";

        bytes32 msgHash = sha256(abi.encodePacked(authData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(p256Pk, msgHash);
        // vm.signP256 可能产出 high-s；归一化为 low-s 以通过可塑性检查 / normalize to low-s.
        if (uint256(s) > P256_N / 2) s = bytes32(P256_N - uint256(s));

        WebAuthn.WebAuthnAuth memory a = WebAuthn.WebAuthnAuth({
            authenticatorData: authData, clientDataJSON: clientDataJSON, challengeIndex: 23, typeIndex: 1, r: r, s: s
        });
        return abi.encode(address(webauthnValidator), abi.encode(a));
    }
}
