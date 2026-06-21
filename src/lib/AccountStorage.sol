// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice ERC-7201 命名空间存储 / ERC-7201 namespaced storage.
/// @dev 7702 委托后 EOA 存储会跨实现持续存在；命名空间布局避免重委托时的槽位碰撞。
///      An EOA's storage persists across delegations under 7702; a namespaced layout avoids slot
///      collisions when the EOA re-delegates to a different implementation.
library AccountStorage {
    // keccak256(abi.encode(uint256(keccak256("my7702.account.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant SLOT = 0x4953604bd88c7ce5dfee847d76bed3043e3cf59086e19164803ba412c4f39200;

    struct Layout {
        uint256 nonce; // opData 签名路径重放守卫 / replay guard for the signed (opData) path
        mapping(address => bool) validators; // type 1 模块集合 / installed validators
        mapping(address => bool) executors; // type 2 模块集合 / installed executors
        mapping(address => bool) isHook; // type 4 去重 / hook membership
        address[] hooks; // type 4 有序列表 / ordered hooks
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 s = SLOT;
        assembly {
            l.slot := s
        }
    }
}
