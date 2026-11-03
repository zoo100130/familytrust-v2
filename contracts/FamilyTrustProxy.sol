// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title FamilyTrustProxy：FamilyTrustV2 的代理合約（手動部署用）
/// @notice 部署參數：
///         implementation = 已部署的 FamilyTrustV2 實作合約地址
///         data           = initialize(c) 的 calldata（在 Remix 實作合約的 initialize 旁按 Calldata 複製）
///         之後前端、錢包一律使用這個代理合約的地址。
contract FamilyTrustProxy is ERC1967Proxy {
    constructor(address implementation, bytes memory data) ERC1967Proxy(implementation, data) {}
}
