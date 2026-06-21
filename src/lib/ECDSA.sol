// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice 极简 secp256k1 恢复库，强制 low-s 防可塑性 / Minimal secp256k1 recovery enforcing low-s (anti-malleability).
library ECDSA {
    /// secp256k1n / 2，EIP-2 规定的 low-s 上界 / half curve order (EIP-2 low-s bound).
    uint256 internal constant HALF_N = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    /// @notice 从 65 字节签名恢复签名者；非法/可塑签名返回 address(0)。
    ///         Recover signer from a 65-byte signature; returns address(0) on invalid/malleable input.
    function recover(bytes32 hash, bytes memory sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 0x20))
            s := mload(add(sig, 0x40))
            v := byte(0, mload(add(sig, 0x60)))
        }
        if (uint256(s) > HALF_N) return address(0); // 拒绝 high-s / reject high-s
        if (v != 27 && v != 28) return address(0);
        return ecrecover(hash, v, r, s);
    }
}
