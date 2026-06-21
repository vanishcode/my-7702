// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice 最小 base64url 编码（无填充），用于匹配 WebAuthn clientDataJSON 中的 challenge。
///         Minimal base64url encoder (no padding) to match the challenge in WebAuthn clientDataJSON.
library Base64Url {
    /// RFC 4648 §5 url-safe 字母表 / url-safe alphabet ('+'->'-', '/'->'_').
    bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

    function encode(bytes memory data) internal pure returns (string memory) {
        uint256 len = data.length;
        if (len == 0) return "";

        // 无填充输出长度 = ceil(len*4/3) / unpadded output length.
        uint256 outLen = (len * 8 + 5) / 6;
        bytes memory result = new bytes(outLen);
        bytes memory table = TABLE;

        uint256 i = 0;
        uint256 j = 0;
        // 每 3 字节 -> 4 字符 / process 3 input bytes -> 4 output chars.
        while (i + 3 <= len) {
            uint256 n =
                (uint256(uint8(data[i])) << 16) | (uint256(uint8(data[i + 1])) << 8) | uint256(uint8(data[i + 2]));
            result[j] = table[(n >> 18) & 0x3F];
            result[j + 1] = table[(n >> 12) & 0x3F];
            result[j + 2] = table[(n >> 6) & 0x3F];
            result[j + 3] = table[n & 0x3F];
            i += 3;
            j += 4;
        }

        uint256 rem = len - i; // 0,1,2
        if (rem == 1) {
            uint256 n = uint256(uint8(data[i])) << 16;
            result[j] = table[(n >> 18) & 0x3F];
            result[j + 1] = table[(n >> 12) & 0x3F];
        } else if (rem == 2) {
            uint256 n = (uint256(uint8(data[i])) << 16) | (uint256(uint8(data[i + 1])) << 8);
            result[j] = table[(n >> 18) & 0x3F];
            result[j + 1] = table[(n >> 12) & 0x3F];
            result[j + 2] = table[(n >> 6) & 0x3F];
        }
        return string(result);
    }
}
