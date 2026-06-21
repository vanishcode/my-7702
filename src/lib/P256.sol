// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice secp256r1 (P-256) 验签：调用 RIP-7212 / EIP-7951 预编译 0x100。
///         secp256r1 verification via the RIP-7212 / EIP-7951 precompile at 0x100.
/// @dev 安全要点 / security notes:
///      - 预编译失败返回**空 returndata**（非 32 字节 0），故成功判定必须含 `returndatasize == 32`。
///        The precompile returns EMPTY returndata on failure (not 32 zero bytes); success must require 32-byte output.
///      - 预编译**不强制 low-s**，本库自检 `s <= n/2` 并拒绝 r/s 越界，封堵可塑性重放。
///        The precompile does NOT enforce low-s; this lib enforces `s <= n/2` and rejects out-of-range r/s.
library P256 {
    address internal constant VERIFIER = 0x0000000000000000000000000000000000000100;

    // P-256 群阶 n 与 n/2 / curve order n and half order.
    uint256 internal constant N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    uint256 internal constant HALF_N = 0x7FFFFFFF800000007FFFFFFFFFFFFFFFDE737D56D38BCF4279DCE5617E3192A8;

    /// @notice 验证 P-256 签名 / verify a P-256 signature over `hash`.
    function verify(bytes32 hash, bytes32 r, bytes32 s, bytes32 x, bytes32 y) internal view returns (bool) {
        // 范围与 low-s 检查 / range + low-s checks
        if (uint256(r) == 0 || uint256(r) >= N) return false;
        if (uint256(s) == 0 || uint256(s) > HALF_N) return false;

        bytes memory input = abi.encodePacked(hash, r, s, x, y); // 160 bytes
        (bool ok, bytes memory ret) = VERIFIER.staticcall(input);
        // 成功 ≡ 调用成功 且 返回 32 字节 且 等于 1 / success iff call ok AND 32-byte output AND == 1.
        return ok && ret.length == 32 && abi.decode(ret, (uint256)) == 1;
    }
}
