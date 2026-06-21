// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {P256} from "./P256.sol";
import {Base64Url} from "./Base64Url.sol";

/// @notice 链上 WebAuthn (passkey) assertion 验证 / On-chain WebAuthn (passkey) assertion verification.
/// @dev 验证真实设备/浏览器 passkey 的 `navigator.credentials.get()` 断言。
///      Verifies a real device/browser passkey `navigator.credentials.get()` assertion.
library WebAuthn {
    /// @dev WebAuthn 断言负载 / a decoded WebAuthn assertion payload.
    struct WebAuthnAuth {
        bytes authenticatorData; // authenticator data bytes
        string clientDataJSON; // client data JSON (UTF-8)
        uint256 challengeIndex; // clientDataJSON 中 "challenge" 字段起始下标 / index of "challenge" field
        uint256 typeIndex; // clientDataJSON 中 "type" 字段起始下标 / index of "type" field
        bytes32 r; // P-256 签名 r / signature r
        bytes32 s; // P-256 签名 s / signature s
    }

    // authenticatorData flags（位于第 32 字节）/ flag bits at authenticatorData[32].
    bytes1 internal constant FLAG_UP = 0x01; // User Present
    bytes1 internal constant FLAG_UV = 0x04; // User Verified

    /// @notice 校验一个 WebAuthn 断言 / verify a WebAuthn assertion.
    /// @param challenge 期望的挑战（本账户算出的 execHash 或消息哈希）/ expected challenge (account execHash or message hash).
    /// @param requireUV 是否要求 User-Verified / whether User-Verified is required.
    /// @param auth abi.encode(WebAuthnAuth) 编码的断言 / the abi-encoded WebAuthnAuth.
    /// @param x,y 已注册的 passkey 公钥坐标 / the registered passkey public key coordinates.
    function verify(bytes32 challenge, bool requireUV, bytes memory auth, bytes32 x, bytes32 y)
        internal
        view
        returns (bool)
    {
        WebAuthnAuth memory a = abi.decode(auth, (WebAuthnAuth));
        bytes memory json = bytes(a.clientDataJSON);

        // 1. flags 检查 / flag checks (authenticatorData[32]).
        if (a.authenticatorData.length < 37) return false;
        bytes1 flags = a.authenticatorData[32];
        if (flags & FLAG_UP != FLAG_UP) return false; // 必须 User Present / UP must be set
        if (requireUV && (flags & FLAG_UV != FLAG_UV)) return false;

        // 2. type 必须为 "type":"webauthn.get" / type must be the WebAuthn 'get' ceremony.
        if (!_matches(json, a.typeIndex, '"type":"webauthn.get"')) return false;

        // 3. challenge 必须与期望的 base64url(challenge) 完全一致 / challenge must equal base64url(challenge).
        bytes memory expectedChallenge =
            abi.encodePacked('"challenge":"', Base64Url.encode(abi.encodePacked(challenge)), '"');
        if (!_matches(json, a.challengeIndex, string(expectedChallenge))) return false;

        // 4. 重建被签消息哈希 / reconstruct the signed message hash.
        //    msgHash = sha256(authenticatorData || sha256(clientDataJSON))
        bytes32 clientHash = sha256(json);
        bytes32 msgHash = sha256(abi.encodePacked(a.authenticatorData, clientHash));

        // 5. P-256 验签 / verify the P-256 signature.
        return P256.verify(msgHash, a.r, a.s, x, y);
    }

    /// @dev 校验 json[offset : offset+needle.len] == needle / check substring equality at offset.
    function _matches(bytes memory json, uint256 offset, string memory needle) private pure returns (bool) {
        bytes memory n = bytes(needle);
        if (offset + n.length > json.length) return false;
        for (uint256 i = 0; i < n.length; i++) {
            if (json[offset + i] != n[i]) return false;
        }
        return true;
    }
}
